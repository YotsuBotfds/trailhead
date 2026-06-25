#!/usr/bin/env python3
"""Analyze a Trailhead --perf-log frames CSV: classify hitches + health-check.

The windowed debug build (tools/windows-debug/run-logged.bat, or any
`<godot> ... -- --perf-log` run) writes a per-frame CSV. The owner round-trips
these via send-debug; this tool turns one into an actionable hitch report so
each perf iteration is data-driven instead of guesswork.

Usage:  python3 tools/analyze_perf_csv.py <frames.csv> [hitch_threshold_ms=100]

Hitch classes:
  BOOT            frames 1-4, the initial world materialization
  collision       collision_cooks>0 on new CSVs
  visual-commit   visual_commits is high or visual_commit_ms dominates the frame
  other           everything else

Old CSVs without subsystem columns keep the earlier object-delta/crossing
fallback so historical captures still produce a useful report.
"""
import csv
import sys


ATTRIBUTION_COLUMNS = {"collision_cooks", "visual_commits", "visual_commit_ms"}
VISUAL_COMMIT_COUNT_HIGH = 4
VISUAL_COMMIT_DOMINANCE_RATIO = 0.50
VISUAL_COMMIT_DOMINANCE_MIN_MS = 10.0


def fnum(row, key, default=0.0):
    try:
        return float(row.get(key, default) or default)
    except (TypeError, ValueError):
        return default


def inum(row, key, default=0):
    return int(fnum(row, key, float(default)))


def flag(row, key):
    return (row.get(key, "0") or "0").strip() in ("1", "1.0", "True", "true")


def classify_hitch(row, frame, dt_ms, at_crossing, object_delta, has_attribution):
    if frame <= 4:
        return "BOOT"
    if has_attribution:
        collision_cooks = inum(row, "collision_cooks")
        visual_commits = inum(row, "visual_commits")
        visual_commit_ms = fnum(row, "visual_commit_ms")
        if collision_cooks > 0:
            return "collision"
        if visual_commits >= VISUAL_COMMIT_COUNT_HIGH:
            return "visual-commit"
        if visual_commit_ms >= max(VISUAL_COMMIT_DOMINANCE_MIN_MS, dt_ms * VISUAL_COMMIT_DOMINANCE_RATIO):
            return "visual-commit"
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


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    thr = float(sys.argv[2]) if len(sys.argv) > 2 else 100.0
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        fieldnames = set(reader.fieldnames or [])
    if not rows:
        print(f"{path}: no data rows (capture may have been killed before a flush)")
        return 1
    has_attribution = ATTRIBUTION_COLUMNS.issubset(fieldnames)

    n = len(rows)
    dts = [fnum(r, "dt_ms") for r in rows]
    sdt = sorted(dts)
    print(f"=== {path}")
    print(f"frames={n}  duration~{sum(dts)/1000:.1f}s  "
          f"median={sdt[n//2]:.1f}ms (~{1000/(sdt[n//2] or 1):.0f}fps)  "
          f"p99={sdt[int(n*0.99)]:.1f}ms  p99.9={sdt[int(n*0.999)]:.1f}ms")

    # health
    vm = [fnum(r, "video_mem_mb") for r in rows]
    post = vm[min(20, n - 1)]
    print(f"video_mem_mb: boot={max(vm[:5] or [0]):.0f} end={vm[-1]:.0f} "
          f"(post-boot growth {vm[-1]-post:+.0f} MB){'  <-- possible leak' if vm[-1]-post > 200 else ''}")

    # hitches
    labels = ["BOOT", "collision", "visual-commit", "other"] if has_attribution else ["BOOT", "crossing-collision", "visual-commit", "other"]
    stats = {label: {"count": 0, "total_ms": 0.0, "max_ms": 0.0} for label in labels}
    print(f"\n--- hitches > {thr:.0f}ms ---")
    base_header = f"{'frame':>7} {'dt_ms':>8} {'cell':>7} {'atc':>4} {'dobj':>6} {'ddraw':>6}"
    if has_attribution:
        print(f"{base_header} {'cooks':>5} {'vcom':>5} {'vc_ms':>8}  class")
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
        cls = classify_hitch(r, fr, dts[i], atc, dobj, has_attribution)
        update_stats(stats, cls, dts[i])
        if has_attribution:
            print(f"{fr:>7} {dts[i]:>8.0f} {r.get('current_cell','?'):>7} "
                  f"{'Y' if atc else 'n':>4} {dobj:>6} {ddraw:>6} "
                  f"{inum(r, 'collision_cooks'):>5} {inum(r, 'visual_commits'):>5} "
                  f"{fnum(r, 'visual_commit_ms'):>8.1f}  {cls}")
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
              f"or visual_commit_ms>={VISUAL_COMMIT_DOMINANCE_RATIO:.0%} of dt.")
    else:
        print("legacy CSV: visual-commit uses object delta; crossing-collision uses hitch_at_crossing.")
    print("New 'other' hitches = next target.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
