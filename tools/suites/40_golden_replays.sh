run_sim "$out_dir/golden_flat_target.json" \
	--scene=flat_plane \
	--controller=replay \
	--replay=tests/golden/flat_target_replay.json \
	--spawn=flat_spawn \
	--target=flat_target \
	--seed=12345 \
	--max-ticks=220 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_flat_flipped.json" \
	--scene=flat_plane \
	--controller=replay \
	--replay=tests/golden/flat_flipped_replay.json \
	--spawn=flat_flipped \
	--target=0,0,-3 \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_old_cedar_replay.json \
	--spawn=trailhead \
	--target=old_cedar \
	--seed=12345 \
	--max-ticks=360 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_overlook_ridge.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_overlook_ridge_replay.json \
	--spawn=trailhead \
	--target=overlook_ridge \
	--seed=12345 \
	--max-ticks=520 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_bog_bottom.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_bog_bottom_replay.json \
	--spawn=trailhead \
	--target=bog_bottom \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_the_crossing.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_the_crossing_replay.json \
	--spawn=trailhead \
	--target=the_crossing \
	--target-radius=0.15 \
	--seed=12345 \
	--max-ticks=620 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_boardwalk_end.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_boardwalk_end_replay.json \
	--spawn=trailhead \
	--target=boardwalk_end \
	--target-radius=0.25 \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_culvert_mouth_replay.json \
	--spawn=trailhead \
	--target=culvert_mouth \
	--seed=12345 \
	--max-ticks=520 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_trailhead_to_culvert_mouth_replay.json \
	--route-segment=trailhead_to_culvert_mouth \
	--seed=12345 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_segment_overlook_to_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_overlook_to_old_cedar_replay.json \
	--route-segment=overlook_to_old_cedar \
	--seed=12345 \
	--stuck-window=60 \
	--stuck-min-progress=0.015
