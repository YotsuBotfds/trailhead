printf 'run: tile streamer freeze expiry fallback\n'

run_sim "$out_dir/tile_streamer_freeze_expiry.json" \
	--stream-route=spike_1km_route \
	--segment=west_gate_to_east_gate \
	--controller=pd \
	--stream-workers=0 \
	--stream-force-unready-cell=5,4 \
	--stream-force-unready-trigger-x=499.8 \
	--stream-force-unready-ticks=720 \
	--seed=12345 \
	--max-ticks=4200 \
	--stuck-window=900 \
	--stuck-min-progress=0.0
assert_metrics "$out_dir/tile_streamer_freeze_expiry.json" \
	--predicate=reached_target \
	--predicate=target_landmark_event_observed \
	--landmark=east_gate \
	--metric-min=streaming_collision_freeze_ticks:600 \
	--metric-min=streaming_collision_max_consecutive_freeze_ticks:600 \
	--metric-max=streaming_collision_max_consecutive_freeze_ticks:600 \
	--metric-min=streaming_collision_freeze_expired_event_count:1 \
	--metric-max=streaming_collision_freeze_expired_event_count:1 \
	--metric-min=streaming_collision_freeze_expired_count:1 \
	--metric-max=streaming_collision_freeze_expired_count:1 \
	--metric-min=streaming_collision_freeze_expired_max_ticks:600 \
	--metric-max=streaming_collision_freeze_expired_max_ticks:600 \
	--metric-min=streaming_collision_release_count:1 \
	--metric-max=streaming_collision_release_max_downward_speed_mps:0.001 \
	--metric-max=max_chassis_penetration_m:0.02 \
	--metric-min=final_body_heightfield_clearance_m:0.01 \
	--metric-max=max_flipped_ticks:0 \
	--metric-min=stream_force_unready_applied:1
