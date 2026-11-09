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

### Second pass: main-thread bookkeeping (output-identical)

These remove script-level sorting and scans from the streamer's main-thread
maintenance. Every queue, commit and free happens in the same order as before.

- **Cached active-cell center.** `_active_cell_center()` sorted the ~49 active cells
  with a GDScript comparator on every call. It feeds every detail/full-res/foliage
  radius check, which run per cell in the detail and MidLOD refresh sweeps and per
  queued commit/foliage subcommit (roughly 150+ sorts per cell crossing, and ~6 per
  frame while foliage streams). It is now computed once per activation/eviction.
  Integer sums are order-independent, so the value is identical.
- **Native cell sorts.** `_sorted_cells` and the stream-HLOD priority sort pack
  each cell into one int64 key and sort a `PackedInt64Array` natively instead of
  calling a script comparator per comparison. This matters most for the boot-time
  sort of all ~3.1k Zion region cells and the HLOD queue resort that runs on every
  activation/eviction frame until all HLOD chunks have dispatched (~1 per frame,
  so roughly the first 50 s of a drive). Out-of-range coordinates fall back to the
  original comparator.
- **Near-densify walk.** `_queue_near_stream_hlod_densification` sorted every
  committed HLOD chunk (eventually the whole region) on each activation/eviction
  frame to find the 11x11 ring. It now walks that square directly. Walking x-outer,
  y-inner produces the same `_cell_less` order.
- **MidLOD desired cells** are generated in `_cell_less` order, so their sort is gone.
- **Foliage subcommit index.** `_remove_queued_foliage_subcommits` rebuilt the whole
  subcommit queue (hundreds to ~1k entries after a crossing) for every evicted,
  unprefetched, downgraded or freed cell, even cells with nothing queued. A per-cell
  count now skips those calls. The detail refresh alone made ~24 such calls per
  activation frame.
- **Scheduler fix.** A pending-free queue holding only retained cells (normal while
  driving) counted as commit work. That let a no-op drain claim the scheduler's
  guaranteed over-deadline slot, so a budget-starved frame made no progress when the
  cursor reached it. Only free-eligible cells count now.

The maintenance phase runs before the commit drains and shares the same 4 ms window
(`_commit_phase_start_usec` is stamped first), so cheaper maintenance also leaves more
of the window for commits. In captures, compare `detail_refresh_ms`,
`midlod_refresh_ms`, `hlod_queue_ms` and `evict_ms` on crossing frames, plus
`visual_commits` per frame under load.

These changes were written without a Godot binary available, so the second-pass
fixture checks below have **not been executed yet**. Run the headless fixture before
the GPU capture. It compares each native path against the original comparator or
scan inside the engine.

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
  Second pass (not yet run, see above): retained frees are not commit work; native
  `_sorted_cells` and HLOD priority sorts match the comparators, including random
  sets, negative coordinates, int32 extremes, non-cell entries and the fallback
  range; the cached center matches a fresh mean across set/erase/clear; MidLOD
  desired cells stay sorted; the near-densify walk matches the old full-sort scan
  for dense and sparse chunk sets; and the subcommit index matches a queue recount
  after push, pop, no-op removal, removal and drain. It also prints informational
  native-vs-comparator timings for 3,136-cell sorts.
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
