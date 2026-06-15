# The scripted ramp now approaches on packed_gravel, then climbs wood_plank.
# Keep the sequence narrow so a future dirt-first line is visible.
assert_metrics "$out_dir/cedar_hollow_log_ramp.json" \
	--surface=wood_plank:20 \
	--surface-sequence=packed_gravel,wood_plank \
	--metric-min=max_y_position:0.115 \
	--metric-min=max_pitch_deg:2.0

assert_metrics "$out_dir/cedar_hollow_clip_descent.json" \
	--predicate=scenario_passed \
	--surface=loose_rock:20 \
	--metric-min=chassis_clearance_sample_ticks:80 \
	--metric-min=max_speed:2.5 \
	--metric-min=max_descent_from_initial:0.18 \
	--metric-max=max_chassis_penetration_m:0.01

assert_metrics "$out_dir/cedar_hollow_old_cedar.json" \
	--surface=packed_gravel:20 \
	--surface=packed_dirt:40 \
	--landmark=old_cedar

assert_metrics "$out_dir/cedar_hollow_overlook_ridge.json" \
	--surface=loose_rock:12 \
	--metric-min=contact_normal_sample_ticks:40 \
	--metric-min=max_contact_normal_tilt_deg:1.5 \
	--landmark=overlook_ridge

assert_metrics "$out_dir/cedar_hollow_bog_bottom.json" \
	--surface=mud:2 \
	--landmark=bog_bottom

assert_metrics "$out_dir/cedar_hollow_the_crossing.json" \
	--surface=wood_plank:8 \
	--surface=mud:15 \
	--surface=wet_stone:5 \
	--surface-sequence=wood_plank,mud,wet_stone \
	--landmark=the_crossing

assert_metrics "$out_dir/cedar_hollow_boardwalk_end.json" \
	--surface=wood_plank:7 \
	--landmark=boardwalk_end

assert_metrics "$out_dir/cedar_hollow_culvert_mouth.json" \
	--surface=packed_dirt:40 \
	--landmark=culvert_mouth

assert_metrics "$out_dir/cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--surface=tall_grass:20 \
	--surface=packed_dirt:50 \
	--landmark=culvert_mouth

# The overlook-to-old-cedar route stays rock-heavy after the feel re-record.
# Keep the floor near the golden route so future dirt-heavy drift is visible.
assert_metrics "$out_dir/cedar_hollow_segment_overlook_to_old_cedar.json" \
	--surface=loose_rock:140 \
	--landmark=old_cedar

assert_metrics "$out_dir/cedar_hollow_segment_overlook_to_ridge_gate.json" \
	--surface=packed_dirt:20 \
	--source-min=terrain:40 \
	--landmark=ridge_gate

assert_metrics "$out_dir/cedar_hollow_segment_ridge_gate_to_pine_floor.json" \
	--surface=packed_dirt:120 \
	--source-min=terrain:120 \
	--landmark=pine_floor

assert_metrics "$out_dir/cedar_hollow_segment_pine_floor_to_far_mile_marker.json" \
	--surface=packed_dirt:180 \
	--source-min=terrain:180 \
	--landmark=far_mile_marker
