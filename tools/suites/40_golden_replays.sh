assert_golden_replay() {
	assert_metrics "$1" \
		--predicate=golden_replay_matched \
		--metric-min=golden_replay.compared_samples:1 \
		--metric-min=golden_replay.compared_slip_samples:1 \
		--metric-min=golden_replay.compared_motor_rpm_samples:1 \
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
assert_golden_replay "$out_dir/golden_flat_target.json"

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
assert_golden_replay "$out_dir/golden_flat_flipped.json"

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
assert_golden_replay "$out_dir/golden_cedar_hollow_old_cedar.json"

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
assert_golden_replay "$out_dir/golden_cedar_hollow_overlook_ridge.json"

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
assert_golden_replay "$out_dir/golden_cedar_hollow_bog_bottom.json"

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
assert_golden_replay "$out_dir/golden_cedar_hollow_the_crossing.json"

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
assert_golden_replay "$out_dir/golden_cedar_hollow_boardwalk_end.json"

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
assert_golden_replay "$out_dir/golden_cedar_hollow_culvert_mouth.json"

run_sim "$out_dir/golden_cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_trailhead_to_culvert_mouth_replay.json \
	--route-segment=trailhead_to_culvert_mouth \
	--seed=12345 \
	--max-ticks=1040 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_golden_replay "$out_dir/golden_cedar_hollow_segment_trailhead_to_culvert_mouth.json"

run_sim "$out_dir/golden_cedar_hollow_segment_overlook_to_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_overlook_to_old_cedar_replay.json \
	--route-segment=overlook_to_old_cedar \
	--seed=12345 \
	--max-ticks=3200 \
	--stuck-window=120 \
	--stuck-min-progress=0.015
assert_golden_replay "$out_dir/golden_cedar_hollow_segment_overlook_to_old_cedar.json"
