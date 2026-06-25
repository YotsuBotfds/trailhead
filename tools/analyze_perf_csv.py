#!/usr/bin/env python3
"""Analyze a Trailhead --perf-log frames CSV: classify hitches + health-check.

The windowed debug build (tools/windows-debug/run-logged.bat, or any
`<godot> ... -- --perf-log` run) writes a per-frame CSV. The owner round-trips
these via send-debug; this tool turns one into an actionable hitch report so
each perf iteration is data-driven instead of guesswork.

Usage:  python3 tools/analyze_perf_csv.py <frames.csv> [hitch_threshold_ms=100]
        [--fail-p99-ms=N] [--fail-leak-mb=N] [--fail-other-hitch-count=N]

Hitch classes:
  BOOT            frames 1-4, the initial world materialization
  collision       collision_cooks>0 on new CSVs
  visual-commit   visual_commits is high or visual_commit_ms dominates the frame
  render-*        a new render-streamer *_ms column dominates the frame
  other           everything else

Old CSVs without subsystem columns keep the earlier object-delta/crossing
fallback so historical captures still produce a useful report.
"""
import argparse
import csv
import sys


ATTRIBUTION_COLUMNS = {"collision_cooks", "visual_commits", "visual_commit_ms"}
STREAMER_MS_COLUMNS = [
    ("detail_refresh_ms", "render-detail-refresh", "detail"),
    ("detail_sort_ms", "render-detail-refresh", "dsort"),
    ("detail_ensure_ms", "render-detail-refresh", "densure"),
    ("detail_downgrade_ms", "render-detail-refresh", "ddown"),
    ("detail_sync_build_ms", "render-detail-refresh", "dsync"),
    ("evict_ms", "render-evict", "evict"),
    ("hlod_queue_ms", "render-hlod-queue", "hlodq"),
    ("hlod_dispatch_ms", "render-hlod-dispatch", "hdisp"),
    ("hlod_densify_ms", "render-hlod-densify", "hden"),
    ("hlod_sync_ms", "render-hlod-sync", "hsync"),
    ("midlod_refresh_ms", "render-midlod-refresh", "midref"),
    ("worker_result_ms", "render-worker-result", "result"),
    ("visual_build_ms", "render-visual-build", "vbuild"),
    ("midlod_build_ms", "render-midlod-build", "mbuild"),
    ("hlod_build_ms", "render-hlod-build", "hbuild"),
    ("foliage_build_ms", "render-foliage-build", "fbuild"),
]
STREAMER_COUNT_COLUMNS = [
    ("detail_refresh_sweeps", "sweeps"),
]
HLOD_SPLIT_COLUMNS = {"hlod_dispatch_ms", "hlod_densify_ms", "hlod_sync_ms"}
DERIVED_HLOD_MAINTENANCE_COLUMN = "__hlod_maintenance_ms"
VISUAL_COMMIT_COUNT_HIGH = 4
VISUAL_COMMIT_DOMINANCE_RATIO = 0.50
VISUAL_COMMIT_DOMINANCE_MIN_MS = 10.0
STREAMER_DOMINANCE_RATIO = 0.50
STREAMER_DOMINANCE_MIN_MS = 10.0
OTHER_PROCESS_ID_NAMES = {
    0: "none",
    1: "cedar_hollow_host",
    2: "minimap_view",
    3: "vehicle_juice_rig",
    4: "photograph_system",
    5: "render_dynamic_resolution_controller",
    6: "recoverable_object_render",
    7: "debug_overlay_hud",
    8: "controls_hint_hud",
    9: "speed_hud",
    10: "terrain_visual_builder",
    11: "title_card_hud",
}


def fnum(row, key, default=0.0):
    try:
        return float(row.get(key, default) or default)
    except (TypeError, ValueError):
        return default


def inum(row, key, default=0):
    return int(fnum(row, key, float(default)))


def flag(row, key):
    return (row.get(key, "0") or "0").strip() in ("1", "1.0", "True", "true")


def available_streamer_columns(fieldnames):
    has_hlod_split = HLOD_SPLIT_COLUMNS.issubset(fieldnames) and "hlod_queue_ms" in fieldnames
    columns = []
    for item in STREAMER_MS_COLUMNS:
        column = item[0]
        if column == "hlod_queue_ms" and has_hlod_split:
            continue
        if column in fieldnames:
            columns.append(item)
    if has_hlod_split:
        columns.append((DERIVED_HLOD_MAINTENANCE_COLUMN, "render-hlod-maint", "hmaint"))
    return columns


def available_streamer_count_columns(fieldnames):
    return [item for item in STREAMER_COUNT_COLUMNS if item[0] in fieldnames]


def streamer_value(row, column):
    if column == DERIVED_HLOD_MAINTENANCE_COLUMN:
        return max(0.0, (
            fnum(row, "hlod_queue_ms")
            - fnum(row, "hlod_dispatch_ms")
            - fnum(row, "hlod_densify_ms")
            - fnum(row, "hlod_sync_ms")
        ))
    return fnum(row, column)


def dominant_streamer_column(row, streamer_columns):
    label = ""
    value = 0.0
    for column, candidate_label, _short_name in streamer_columns:
        candidate_value = streamer_value(row, column)
        if candidate_value > value:
            label = candidate_label
            value = candidate_value
    return label, value


def format_streamer_columns(row, streamer_columns, streamer_count_columns):
    if not streamer_columns and not streamer_count_columns:
        return ""
    parts = []
    for column, _label, short_name in streamer_columns:
        value = streamer_value(row, column)
        if value > 0.0:
            parts.append(f"{short_name}={value:.1f}")
    for column, short_name in streamer_count_columns:
        value = inum(row, column)
        if value > 0:
            parts.append(f"{short_name}={value}")
    return " ".join(parts) if parts else "-"


def format_other_process(row):
    process_id = inum(row, "top_other_process_id")
    process_ms = fnum(row, "top_other_process_ms")
    name = OTHER_PROCESS_ID_NAMES.get(process_id, f"id{process_id}")
    return f"{name}:{process_ms:.1f}"


def classify_hitch(row, frame, dt_ms, at_crossing, object_delta, has_attribution, streamer_columns):
    if frame <= 4:
        return "BOOT"
    if has_attribution:
        collision_cooks = inum(row, "collision_cooks")
        visual_commits = inum(row, "visual_commits")
        visual_commit_ms = fnum(row, "visual_commit_ms")
        if visual_commits >= VISUAL_COMMIT_COUNT_HIGH:
            return "visual-commit"
        if visual_commit_ms >= max(VISUAL_COMMIT_DOMINANCE_MIN_MS, dt_ms * VISUAL_COMMIT_DOMINANCE_RATIO):
            return "visual-commit"
        streamer_label, streamer_ms = dominant_streamer_column(row, streamer_columns)
        if streamer_label and streamer_ms >= max(STREAMER_DOMINANCE_MIN_MS, dt_ms * STREAMER_DOMINANCE_RATIO):
            return streamer_label
        if collision_cooks > 0:
            return "collision"
        return "other"
    if object_delta >= 150:
        return "visual-commit"
    if at_crossing:
        return "crossing-collision"
    return "other"


def update_stats(stats, label, dt_ms):
    if label not in stats:
        stats[label] = {"count": 0, "total_ms": 0.0, "max_ms": 0.0}
    stats[label]["count"] += 1
    stats[label]["total_ms"] += dt_ms
    stats[label]["max_ms"] = max(stats[label]["max_ms"], dt_ms)


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Analyze a Trailhead --perf-log frames CSV.",
        allow_abbrev=False,
    )
    parser.add_argument("path", help="frames CSV written by --perf-log")
    parser.add_argument(
        "hitch_threshold_ms",
        nargs="?",
        type=float,
        default=100.0,
        help="frame-time threshold for hitch rows (default: 100)",
    )
    parser.add_argument(
        "--fail-p99-ms",
        type=float,
        default=None,
        help="exit non-zero when analyzed p99 frame time exceeds this many ms",
    )
    parser.add_argument(
        "--fail-leak-mb",
        type=float,
        default=None,
        help="exit non-zero when post-boot video memory growth exceeds this many MB",
    )
    parser.add_argument(
        "--fail-other-hitch-count",
        type=int,
        default=None,
        help="exit non-zero when classified 'other' hitch count exceeds this value",
    )
    return parser.parse_args(argv)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    args = parse_args(sys.argv[1:])
    path = args.path
    thr = args.hitch_threshold_ms
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        fieldnames = set(reader.fieldnames or [])
    if not rows:
        print(f"{path}: no data rows (capture may have been killed before a flush)")
        return 1
    has_attribution = ATTRIBUTION_COLUMNS.issubset(fieldnames)
    has_other_process = {"top_other_process_ms", "top_other_process_id"}.issubset(fieldnames)
    streamer_columns = available_streamer_columns(fieldnames)
    streamer_count_columns = available_streamer_count_columns(fieldnames)

    n = len(rows)
    dts = [fnum(r, "dt_ms") for r in rows]
    sdt = sorted(dts)
    median_ms = sdt[n//2]
    p99_ms = sdt[int(n*0.99)]
    p999_ms = sdt[int(n*0.999)]
    print(f"=== {path}")
    print(f"frames={n}  duration~{sum(dts)/1000:.1f}s  "
          f"median={median_ms:.1f}ms (~{1000/(median_ms or 1):.0f}fps)  "
          f"p99={p99_ms:.1f}ms  p99.9={p999_ms:.1f}ms")

    # health
    vm = [fnum(r, "video_mem_mb") for r in rows]
    post = vm[min(20, n - 1)]
    leak_mb = vm[-1] - post
    print(f"video_mem_mb: boot={max(vm[:5] or [0]):.0f} end={vm[-1]:.0f} "
          f"(post-boot growth {leak_mb:+.0f} MB){'  <-- possible leak' if leak_mb > 200 else ''}")

    # hitches
    labels = ["BOOT", "collision", "visual-commit"] if has_attribution else ["BOOT", "crossing-collision", "visual-commit"]
    labels.extend(label for _column, label, _short_name in streamer_columns)
    labels.append("other")
    stats = {label: {"count": 0, "total_ms": 0.0, "max_ms": 0.0} for label in labels}
    print(f"\n--- hitches > {thr:.0f}ms ---")
    base_header = f"{'frame':>7} {'dt_ms':>8} {'cell':>7} {'atc':>4} {'dobj':>6} {'ddraw':>6}"
    if has_attribution:
        other_header = f" {'top_other':>42}" if has_other_process else ""
        if streamer_columns or streamer_count_columns:
            print(f"{base_header} {'cooks':>5} {'vcom':>5} {'vc_ms':>8} {'wrk':>4}{other_header}  streamer_attr  class")
        else:
            print(f"{base_header} {'cooks':>5} {'vcom':>5} {'vc_ms':>8} {'wrk':>4}{other_header}  class")
    else:
        print(f"{base_header}  class")
    for i in range(n):
        if dts[i] <= thr:
            continue
        r = rows[i]
        p = rows[i - 1] if i > 0 else {}
        dobj = int(fnum(r, "objects") - fnum(p, "objects"))
        ddraw = int(fnum(r, "draw_calls") - fnum(p, "draw_calls"))
        atc = flag(r, "hitch_at_crossing")
        fr = inum(r, "frame")
        cls = classify_hitch(r, fr, dts[i], atc, dobj, has_attribution, streamer_columns)
        update_stats(stats, cls, dts[i])
        if has_attribution:
            base = (f"{fr:>7} {dts[i]:>8.0f} {r.get('current_cell','?'):>7} "
                    f"{'Y' if atc else 'n':>4} {dobj:>6} {ddraw:>6} "
                    f"{inum(r, 'collision_cooks'):>5} {inum(r, 'visual_commits'):>5} "
                    f"{fnum(r, 'visual_commit_ms'):>8.1f} {inum(r, 'worker_count'):>4}")
            if has_other_process:
                base = f"{base} {format_other_process(r):>42}"
            if streamer_columns or streamer_count_columns:
                print(f"{base}  {format_streamer_columns(r, streamer_columns, streamer_count_columns):<112}  {cls}")
            else:
                print(f"{base}  {cls}")
        else:
            print(f"{fr:>7} {dts[i]:>8.0f} {r.get('current_cell','?'):>7} "
                  f"{'Y' if atc else 'n':>4} {dobj:>6} {ddraw:>6}  {cls}")

    print("\nSUMMARY: " + "  ".join(f"{k}={stats[k]['count']}" for k in stats))
    print("SUBSYSTEM HITCH TOTALS:")
    for label in stats:
        item = stats[label]
        print(f"  {label:17} count={item['count']:>3} total_ms={item['total_ms']:>8.0f} max_ms={item['max_ms']:>8.0f}")
    if has_attribution:
        print(f"collision → collision_cooks>0; visual-commit → visual_commits>={VISUAL_COMMIT_COUNT_HIGH} "
              f"or visual_commit_ms>={VISUAL_COMMIT_DOMINANCE_RATIO:.0%} of dt. Measured render durations "
              "win over collision cook counts when they dominate.")
        if streamer_columns or streamer_count_columns:
            names = [
                "hlod_maintenance_ms(derived)" if column == DERIVED_HLOD_MAINTENANCE_COLUMN else column
                for column, _label, _short_name in streamer_columns
            ]
            names.extend(column for column, _short_name in streamer_count_columns)
            print(f"render-streamer → dominant new *_ms column >= {STREAMER_DOMINANCE_RATIO:.0%} of dt "
                  f"(columns present: {', '.join(names)}).")
        if has_other_process:
            legend = ", ".join(f"{key}={value}" for key, value in OTHER_PROCESS_ID_NAMES.items())
            print("other → top_other_process_id/top_other_process_ms name the largest instrumented "
                  "non-streamer _process from the elapsed frame; compare top_other_process_ms to dt_ms.")
            print(f"top_other_process_id legend: {legend}.")
    else:
        print("legacy CSV: visual-commit uses object delta; crossing-collision uses hitch_at_crossing.")
    print("New 'other' hitches = next target.")
    failures = []
    if args.fail_p99_ms is not None and p99_ms > args.fail_p99_ms:
        failures.append(f"p99 {p99_ms:.1f}ms > --fail-p99-ms {args.fail_p99_ms:.1f}ms")
    if args.fail_leak_mb is not None and leak_mb > args.fail_leak_mb:
        failures.append(f"post-boot video_mem growth {leak_mb:.0f} MB > --fail-leak-mb {args.fail_leak_mb:.0f} MB")
    other_hitches = stats.get("other", {}).get("count", 0)
    if args.fail_other_hitch_count is not None and other_hitches > args.fail_other_hitch_count:
        failures.append(
            f"other hitch count {other_hitches} > --fail-other-hitch-count {args.fail_other_hitch_count}"
        )
    if failures:
        print("THRESHOLD FAILURES:")
        for failure in failures:
            print(f"  {failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
