printf 'run: tile streamer seam stays above terrain\n'

run_sim "$out_dir/tile_streamer_seam_above_terrain.json" \
	--stream-route=spike_1km_route \
	--segment=west_gate_to_east_gate \
	--controller=pd \
	--stream-workers=0 \
	--stream-force-unready-cell=5,4 \
	--stream-force-unready-trigger-x=499.8 \
	--stream-force-unready-ticks=120 \
	--seed=12345 \
	--max-ticks=3000 \
	--stuck-window=240 \
	--stuck-min-progress=0.02
assert_metrics "$out_dir/tile_streamer_seam_above_terrain.json" \
	--predicate=reached_target \
	--predicate=target_landmark_event_observed \
	--landmark=east_gate \
	--metric-max=max_chassis_penetration_m:0.02 \
	--metric-min=chassis_clearance_sample_ticks:120 \
	--metric-max=max_flipped_ticks:0 \
	--metric-max=max_position_delta_m:0.35 \
	--metric-min=streaming_collision_freeze_ticks:1 \
	--metric-min=stream_force_unready_applied:1
