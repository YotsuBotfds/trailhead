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
assert_metrics "$out_dir/golden_flat_target.json" \
	--metric-near=max_abs_slip_angle_deg:62.2645440587807:2.0 \
	--metric-near=surface_event_count:1:0 \
	--metric-near=landmark_event_count:0:0 \
	--metric-near=flipped_event_count:0:0 \
	--metric-near=self_righted_event_count:0:0 \
	--metric-near=surface_contact_ticks.packed_dirt:82:2

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
assert_metrics "$out_dir/golden_flat_flipped.json" \
	--metric-near=max_abs_slip_angle_deg:0.00212384573826514:2.0 \
	--metric-near=surface_event_count:1:0 \
	--metric-near=landmark_event_count:0:0 \
	--metric-near=flipped_event_count:1:0 \
	--metric-near=self_righted_event_count:1:0 \
	--metric-near=surface_contact_ticks.packed_dirt:12:2

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
assert_metrics "$out_dir/golden_cedar_hollow_old_cedar.json" \
	--metric-near=max_abs_slip_angle_deg:26.7449785632081:2.0 \
	--metric-near=surface_event_count:2:0 \
	--metric-near=landmark_event_count:2:0 \
	--metric-near=flipped_event_count:0:0 \
	--metric-near=self_righted_event_count:0:0 \
	--metric-near=surface_contact_ticks.packed_dirt:46:2 \
	--metric-near=surface_contact_ticks.packed_gravel:8:2

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
assert_metrics "$out_dir/golden_cedar_hollow_overlook_ridge.json" \
	--metric-near=max_abs_slip_angle_deg:50.7789286863385:2.0 \
	--metric-near=surface_event_count:4:0 \
	--metric-near=landmark_event_count:2:0 \
	--metric-near=flipped_event_count:3:0 \
	--metric-near=self_righted_event_count:3:0 \
	--metric-near=surface_contact_ticks.loose_rock:40:2 \
	--metric-near=surface_contact_ticks.packed_dirt:31:2 \
	--metric-near=surface_contact_ticks.packed_gravel:8:2 \
	--metric-near=surface_contact_ticks.tall_grass:42:2

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
assert_metrics "$out_dir/golden_cedar_hollow_bog_bottom.json" \
	--metric-near=max_abs_slip_angle_deg:30.3369443118665:2.0 \
	--metric-near=surface_event_count:6:0 \
	--metric-near=landmark_event_count:2:0 \
	--metric-near=flipped_event_count:1:0 \
	--metric-near=self_righted_event_count:1:0 \
	--metric-near=surface_contact_ticks.mud:2:2 \
	--metric-near=surface_contact_ticks.packed_dirt:12:2 \
	--metric-near=surface_contact_ticks.packed_gravel:12:2 \
	--metric-near=surface_contact_ticks.tall_grass:24:2

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
assert_metrics "$out_dir/golden_cedar_hollow_the_crossing.json" \
	--metric-near=max_abs_slip_angle_deg:40.3807989580728:2.0 \
	--metric-near=surface_event_count:6:0 \
	--metric-near=landmark_event_count:2:0 \
	--metric-near=flipped_event_count:2:0 \
	--metric-near=self_righted_event_count:2:0 \
	--metric-near=surface_contact_ticks.mud:17:2 \
	--metric-near=surface_contact_ticks.packed_dirt:3:2 \
	--metric-near=surface_contact_ticks.packed_gravel:16:2 \
	--metric-near=surface_contact_ticks.tall_grass:31:2 \
	--metric-near=surface_contact_ticks.wet_stone:5:2 \
	--metric-near=surface_contact_ticks.wood_plank:18:2

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
assert_metrics "$out_dir/golden_cedar_hollow_boardwalk_end.json" \
	--metric-near=max_abs_slip_angle_deg:48.1222104954461:2.0 \
	--metric-near=surface_event_count:4:0 \
	--metric-near=landmark_event_count:2:0 \
	--metric-near=flipped_event_count:1:0 \
	--metric-near=self_righted_event_count:1:0 \
	--metric-near=surface_contact_ticks.packed_gravel:17:2 \
	--metric-near=surface_contact_ticks.tall_grass:51:2 \
	--metric-near=surface_contact_ticks.wood_plank:9:2

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
assert_metrics "$out_dir/golden_cedar_hollow_culvert_mouth.json" \
	--metric-near=max_abs_slip_angle_deg:54.179604742007:2.0 \
	--metric-near=surface_event_count:7:0 \
	--metric-near=landmark_event_count:2:0 \
	--metric-near=flipped_event_count:0:0 \
	--metric-near=self_righted_event_count:0:0 \
	--metric-near=surface_contact_ticks.packed_dirt:60:2 \
	--metric-near=surface_contact_ticks.packed_gravel:22:2 \
	--metric-near=surface_contact_ticks.tall_grass:35:2

run_sim "$out_dir/golden_cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_trailhead_to_culvert_mouth_replay.json \
	--route-segment=trailhead_to_culvert_mouth \
	--seed=12345 \
	--stuck-window=60 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/golden_cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--metric-near=max_abs_slip_angle_deg:73.2729306988195:2.0 \
	--metric-near=surface_event_count:3:0 \
	--metric-near=landmark_event_count:2:0 \
	--metric-near=flipped_event_count:0:0 \
	--metric-near=self_righted_event_count:0:0 \
	--metric-near=surface_contact_ticks.packed_dirt:52:2 \
	--metric-near=surface_contact_ticks.packed_gravel:17:2 \
	--metric-near=surface_contact_ticks.tall_grass:28:2

run_sim "$out_dir/golden_cedar_hollow_segment_overlook_to_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_overlook_to_old_cedar_replay.json \
	--route-segment=overlook_to_old_cedar \
	--seed=12345 \
	--stuck-window=60 \
	--stuck-min-progress=0.015
assert_metrics "$out_dir/golden_cedar_hollow_segment_overlook_to_old_cedar.json" \
	--metric-near=max_abs_slip_angle_deg:179.523626635105:2.0 \
	--metric-near=surface_event_count:10:0 \
	--metric-near=landmark_event_count:2:0 \
	--metric-near=flipped_event_count:8:0 \
	--metric-near=self_righted_event_count:8:0 \
	--metric-near=surface_contact_ticks.loose_rock:102:2 \
	--metric-near=surface_contact_ticks.packed_dirt:177:2
