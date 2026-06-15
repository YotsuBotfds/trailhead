golden_sample_count() {
	python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
samples = data.get("samples", [])
if not isinstance(samples, list) or not samples:
	raise SystemExit(f"{path}: replay has no samples")
print(len(samples))
PY
}

assert_golden_replay() {
	expected_samples="$(golden_sample_count "$2")"
	assert_metrics "$1" \
		--predicate=golden_replay_matched \
		--metric-near="golden_replay.compared_samples:$expected_samples:0" \
		--metric-min=golden_replay.compared_surface_ticks:1 \
		--metric-min=golden_replay.compared_event_counts:4
}

run_sim "$out_dir/golden_flat_target.json" \
	--scene=flat_plane \
	--controller=replay \
	--replay=tests/golden/flat_target_replay.json \
	--spawn=flat_spawn \
	--target=flat_target \
	--seed=12345 \
	--max-ticks=440 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_flat_target.json" "tests/golden/flat_target_replay.json"

run_sim "$out_dir/golden_flat_flipped.json" \
	--scene=flat_plane \
	--controller=replay \
	--replay=tests/golden/flat_flipped_replay.json \
	--spawn=flat_flipped \
	--target=0,0,-3 \
	--seed=12345 \
	--max-ticks=840 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_flat_flipped.json" "tests/golden/flat_flipped_replay.json"

run_sim "$out_dir/golden_cedar_hollow_zion_pa_rus_flat_segment.json" \
	--scene=cedar_hollow_zion \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_zion_pa_rus_flat_segment_replay.json \
	--scenario=real_terrain_flat_segment \
	--spawn=trailhead \
	--target=0,0,-50 \
	--target-radius=0.05 \
	--seed=12345 \
	--max-ticks=6200 \
	--stuck-window=240 \
	--stuck-min-progress=0.02
assert_golden_replay "$out_dir/golden_cedar_hollow_zion_pa_rus_flat_segment.json" "tests/golden/cedar_hollow_zion_pa_rus_flat_segment_replay.json"

run_sim "$out_dir/golden_cedar_hollow_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_old_cedar_replay.json \
	--spawn=trailhead \
	--target=old_cedar \
	--seed=12345 \
	--max-ticks=720 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_cedar_hollow_old_cedar.json" "tests/golden/cedar_hollow_old_cedar_replay.json"

run_sim "$out_dir/golden_cedar_hollow_overlook_ridge.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_overlook_ridge_replay.json \
	--spawn=trailhead \
	--target=overlook_ridge \
	--seed=12345 \
	--max-ticks=1040 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_cedar_hollow_overlook_ridge.json" "tests/golden/cedar_hollow_overlook_ridge_replay.json"

run_sim "$out_dir/golden_cedar_hollow_bog_bottom.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_bog_bottom_replay.json \
	--spawn=trailhead \
	--target=bog_bottom \
	--seed=12345 \
	--max-ticks=840 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_cedar_hollow_bog_bottom.json" "tests/golden/cedar_hollow_bog_bottom_replay.json"

run_sim "$out_dir/golden_cedar_hollow_the_crossing.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_the_crossing_replay.json \
	--spawn=trailhead \
	--target=the_crossing \
	--target-radius=0.15 \
	--seed=12345 \
	--max-ticks=1240 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_cedar_hollow_the_crossing.json" "tests/golden/cedar_hollow_the_crossing_replay.json"

run_sim "$out_dir/golden_cedar_hollow_boardwalk_end.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_boardwalk_end_replay.json \
	--spawn=trailhead \
	--target=boardwalk_end \
	--target-radius=0.25 \
	--seed=12345 \
	--max-ticks=840 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_cedar_hollow_boardwalk_end.json" "tests/golden/cedar_hollow_boardwalk_end_replay.json"

run_sim "$out_dir/golden_cedar_hollow_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_culvert_mouth_replay.json \
	--spawn=trailhead \
	--target=culvert_mouth \
	--seed=12345 \
	--max-ticks=1040 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_cedar_hollow_culvert_mouth.json" "tests/golden/cedar_hollow_culvert_mouth_replay.json"

run_sim "$out_dir/golden_cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_trailhead_to_culvert_mouth_replay.json \
	--route-segment=trailhead_to_culvert_mouth \
	--seed=12345 \
	--max-ticks=1040 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_cedar_hollow_segment_trailhead_to_culvert_mouth.json" "tests/golden/cedar_hollow_segment_trailhead_to_culvert_mouth_replay.json"

run_sim "$out_dir/golden_cedar_hollow_segment_overlook_to_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_overlook_to_old_cedar_replay.json \
	--route-segment=overlook_to_old_cedar \
	--seed=12345 \
	--max-ticks=3200 \
	--stuck-window=120 \
	--stuck-min-progress=0.015
assert_golden_replay "$out_dir/golden_cedar_hollow_segment_overlook_to_old_cedar.json" "tests/golden/cedar_hollow_segment_overlook_to_old_cedar_replay.json"

run_sim "$out_dir/golden_cedar_hollow_segment_overlook_to_ridge_gate.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_overlook_to_ridge_gate_replay.json \
	--route-segment=overlook_to_ridge_gate \
	--seed=12345 \
	--max-ticks=900 \
	--stuck-window=120 \
	--stuck-min-progress=0.015
assert_golden_replay "$out_dir/golden_cedar_hollow_segment_overlook_to_ridge_gate.json" "tests/golden/cedar_hollow_segment_overlook_to_ridge_gate_replay.json"

run_sim "$out_dir/golden_cedar_hollow_segment_ridge_gate_to_pine_floor.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_ridge_gate_to_pine_floor_replay.json \
	--route-segment=ridge_gate_to_pine_floor \
	--seed=12345 \
	--max-ticks=2200 \
	--stuck-window=120 \
	--stuck-min-progress=0.015
assert_golden_replay "$out_dir/golden_cedar_hollow_segment_ridge_gate_to_pine_floor.json" "tests/golden/cedar_hollow_segment_ridge_gate_to_pine_floor_replay.json"

run_sim "$out_dir/golden_cedar_hollow_segment_pine_floor_to_far_mile_marker.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_pine_floor_to_far_mile_marker_replay.json \
	--route-segment=pine_floor_to_far_mile_marker \
	--seed=12345 \
	--max-ticks=4000 \
	--stuck-window=120 \
	--stuck-min-progress=0.015
assert_golden_replay "$out_dir/golden_cedar_hollow_segment_pine_floor_to_far_mile_marker.json" "tests/golden/cedar_hollow_segment_pine_floor_to_far_mile_marker_replay.json"
