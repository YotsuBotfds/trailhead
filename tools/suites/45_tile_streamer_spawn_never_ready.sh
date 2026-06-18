printf 'run: tile streamer fresh spawn holds while collision is unready\n'

run_sim "$out_dir/tile_streamer_spawn_never_ready.json" \
	--stream-route=spike_1km_route \
	--segment=west_gate_to_east_gate \
	--controller=pd \
	--stream-workers=0 \
	--stream-force-unready-cell=4,4 \
	--stream-force-unready-trigger-x=455.0 \
	--stream-force-unready-ticks=720 \
	--seed=12345 \
	--max-ticks=3600 \
	--stuck-window=900 \
	--stuck-min-progress=0.0
assert_metrics "$out_dir/tile_streamer_spawn_never_ready.json" \
	--predicate=reached_target \
	--predicate=target_landmark_event_observed \
	--landmark=east_gate \
	--metric-min=streaming_collision_freeze_ticks:720 \
	--metric-min=streaming_collision_max_consecutive_freeze_ticks:720 \
	--metric-min=streaming_collision_frozen_sample_ticks:720 \
	--metric-max=streaming_collision_freeze_expired_event_count:0 \
	--metric-max=streaming_collision_freeze_expired_count:0 \
	--metric-min=streaming_collision_release_count:1 \
	--metric-max=streaming_collision_release_count:1 \
	--metric-max=streaming_collision_freeze_max_descent_from_initial:0.001 \
	--metric-max=streaming_collision_freeze_max_flat_displacement_from_initial:0.001 \
	--metric-max=streaming_collision_release_max_downward_speed_mps:0.001 \
	--metric-max=max_chassis_penetration_m:0.02 \
	--metric-min=final_body_heightfield_clearance_m:0.01 \
	--metric-max=max_flipped_ticks:0 \
	--metric-min=stream_force_unready_applied:1
