# Streaming CPU test branch

Base: `3b35424e7d9e95fbc685c47152a0a16159454b11` (`main` at review time).

This branch reduces render-host CPU work without changing simulation code, terrain
resolution, foliage density, materials, or render-quality defaults. GPU performance
and visual streaming cadence still need a real-device playtest.

## Changes

- Terrain jobs reuse foliage already prefetched, partially attached, live, or
  retained for an LOD0 promotion. Coarse-to-full-resolution mesh upgrades no longer
  generate a second foliage payload.
- Spawn-apron spacing uses neighboring spatial buckets instead of scanning every
  accepted point. Candidate order and the original distance comparison are preserved.
- Windowed commit queues share one soft 4 ms deadline. Service rotates under load,
  so HLOD, detail, foliage, MidLOD and evictions all make progress. Headless keeps
  the existing drain order and per-queue count budgets.

The deadline remains soft: one atomic commit can exceed 4 ms, and maintenance,
worker-result staging, deferred engine frees and renderer work have their own costs.
This change prevents each subsequent queue from taking another over-budget turn;
it does not promise a 4 ms total frame or streamer time.

## Local validation

Environment: Linux, Godot 4.6.3 official, headless/Dummy renderer.

- `tools/streaming_cpu_fixture.tscn`: checks shared-budget fairness and progress,
  preserves headless ordering, verifies first-load/upgrade foliage behavior and
  original payload identity, and compares spatial spacing decisions against the
  original linear scan, including negative coordinates and exact boundaries.
- Existing `tools/render_tile_streamer_fixture.tscn` completed its lifecycle,
  full-resolution upgrade, in-flight prefetch, LOD promotion and eviction assertions.
- `tools/suites/90_render_and_data_inspectors.sh` exited 0, including the new fixture.
  Headless texture-array cache and renderer cleanup diagnostics also occur on the
  unchanged base; this run does not establish GPU texture/rendering correctness.
- `tools/check.sh` passed source-boundary, typing, syntax-of-Python, suite-wiring,
  export-safe loading, collision-data and surface-image checks. It is **not fully
  green** here. The same three failures were reproduced on the unchanged base:
  its shell syntax loop invokes `sh` on Bash-only `tools/run_drive_capture.sh`,
  installed NumPy is 2.3.5 rather than pinned 2.4.6, and this Linux Godot binary
  does not match `tools/godot_binary_sha.txt`. No pins or golden data were updated.

CPU observations are component timings, not FPS or target-hardware guarantees:

- Before this branch, sampled Zion foliage tiles took about 26–43 ms each to
  generate. An upgrade now omits that second generation entirely.
- An alternating old/new spawn **placement** comparison on the same six terrain
  tiles measured grass at 15.1–16.6 ms before vs 9.6–10.0 ms after (median reduction
  about 38%). All 620 grass, 190 branch and 96 boulder transforms and colors matched
  the base exactly. Branch placement was roughly unchanged; boulders showed a small
  timing regression (~0.1 ms). Mesh creation/attachment is additional work, and the
  optimized grass operation still runs synchronously after reveal.

## Run the headless regression

From the repository root, with `godot` pointing to your engine binary:

```sh
godot --headless --editor --path . --import
godot --headless --path . res://tools/streaming_cpu_fixture.tscn
```

The fixture is also wired into suite 90. Its printed timings are informational;
acceptance tests do not depend on machine-specific millisecond thresholds.

## Compare on a GPU device

Use separate checkouts of the base and this branch, the same engine binary,
1080p window, mood and quality settings. Import each checkout first. Keep the
window foreground and capture about 90 seconds, then close normally to flush CSV.
Run the base with `baseline.csv`, then this branch with `branch.csv`:

```sh
godot --path . -- --autodrive --perf-log=tests/out/perf/branch.csv
python3 tools/analyze_perf_csv.py tests/out/perf/branch.csv 20
```

The existing autodrive changes its FPS cap during the run; compare equivalent
sections of each capture. Check window focus and `scaling_3d_scale` before
comparing GPU times, because dynamic resolution remains enabled. Compare boot,
cell crossings and steady driving separately. Look for lower commit/crossing
hitches, near-car terrain and foliage appearing promptly, stable tracks through
terrain upgrades, and clean turnarounds across recently evicted cells.

The heavy far-terrain shader and tire-track rendering costs from the review are
not changed in this branch. GPU profiling should decide those visual tradeoffs.
