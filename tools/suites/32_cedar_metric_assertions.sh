# The scripted ramp now approaches on packed_gravel, then climbs wood_plank.
# Keep the sequence narrow so a future dirt-first line is visible.
assert_metrics "$out_dir/cedar_hollow_log_ramp.json" \
	--surface=wood_plank:20 \
	--surface-sequence=packed_gravel,wood_plank \
	--metric-min=max_y_position:0.18 \
	--metric-min=max_pitch_deg:4.0

assert_metrics "$out_dir/cedar_hollow_old_cedar.json" \
	--surface=packed_gravel:20 \
	--surface=packed_dirt:40 \
	--landmark=old_cedar

assert_metrics "$out_dir/cedar_hollow_overlook_ridge.json" \
	--surface=loose_rock:20 \
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
	--surface=packed_dirt:50 \
	--landmark=culvert_mouth

assert_metrics "$out_dir/cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--surface=tall_grass:20 \
	--surface=packed_dirt:50 \
	--landmark=culvert_mouth

# The overlook-to-old-cedar route is a rock descent with only a brief
# packed-dirt handoff near Old Cedar, replacing the old dirt-heavy line.
assert_metrics "$out_dir/cedar_hollow_segment_overlook_to_old_cedar.json" \
	--surface=loose_rock:150 \
	--landmark=old_cedar
