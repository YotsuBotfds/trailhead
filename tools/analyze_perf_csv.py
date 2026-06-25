#!/usr/bin/env python3
"""Analyze a Trailhead --perf-log frames CSV: classify hitches + health-check.

The windowed debug build (tools/windows-debug/run-logged.bat, or any
`<godot> ... -- --perf-log` run) writes a per-frame CSV. The owner round-trips
these via send-debug; this tool turns one into an actionable hitch report so
each perf iteration is data-driven instead of guesswork.

Usage:  python3 tools/analyze_perf_csv.py <frames.csv> [hitch_threshold_ms=100]

Hitch classes (see planning/hitch-landscape-20260625.md):
  BOOT            frames 1-4, the initial world materialization
  crossing-coll.  hitch_at_crossing=1 + small object delta = HeightMapShape3D cook
  visual-commit   large +objects in one frame = a fat tile's MultiMeshInstances
  other           everything else
"""
import csv
import sys


def fnum(row, key, default=0.0):
    try:
        return float(row.get(key, default) or default)
    except (TypeError, ValueError):
        return default


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    thr = float(sys.argv[2]) if len(sys.argv) > 2 else 100.0
    with open(path, newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        print(f"{path}: no data rows (capture may have been killed before a flush)")
        return 1

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
    counts = {"BOOT": 0, "crossing-collision": 0, "visual-commit": 0, "other": 0}
    print(f"\n--- hitches > {thr:.0f}ms ---")
    print(f"{'frame':>7} {'dt_ms':>8} {'cell':>7} {'atc':>4} {'dobj':>6} {'ddraw':>6}  class")
    for i in range(n):
        if dts[i] <= thr:
            continue
        r = rows[i]
        p = rows[i - 1] if i > 0 else {}
        dobj = int(fnum(r, "objects") - fnum(p, "objects"))
        ddraw = int(fnum(r, "draw_calls") - fnum(p, "draw_calls"))
        atc = (r.get("hitch_at_crossing", "0") or "0").strip() in ("1", "1.0", "True")
        fr = int(fnum(r, "frame"))
        if fr <= 4:
            cls = "BOOT"
        elif dobj >= 150:
            cls = "visual-commit"
        elif atc:
            cls = "crossing-collision"
        else:
            cls = "other"
        counts[cls] += 1
        print(f"{fr:>7} {dts[i]:>8.0f} {r.get('current_cell','?'):>7} "
              f"{'Y' if atc else 'n':>4} {dobj:>6} {ddraw:>6}  {cls}")

    print(f"\nSUMMARY: " + "  ".join(f"{k}={v}" for k, v in counts.items()))
    print("BOOT/visual-commit → render materialization budget (boot fix ed0d56f20).")
    print("crossing-collision → collision prewarm (freeze fix, build #1).")
    print("If a class is ~0, that fix worked. New 'other' hitches = next target.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
