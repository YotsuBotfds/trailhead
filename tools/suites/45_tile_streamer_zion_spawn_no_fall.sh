printf 'run: Zion stream spawn west holds above collision\n'

run_sim "$out_dir/zion_stream_spawn_west_no_fall.json" \
	--stream-route=cedar_hollow_zion_stream_route \
	--spawn=stream_west \
	--target=stream_east \
	--controller=scripted \
	--scenario=stream_spawn_no_fall \
	--stream-workers=0 \
	--stream-force-unready-cell=11,8 \
	--stream-force-unready-trigger-x=1150.0 \
	--stream-force-unready-ticks=720 \
	--max-ticks=900 \
	--stuck-window=120 \
	--stuck-min-progress=0.0 \
	--seed=12345

assert_metrics "$out_dir/zion_stream_spawn_west_no_fall.json" \
	--metric-min=streaming_collision_freeze_ticks:720 \
	--metric-min=streaming_collision_frozen_sample_ticks:720 \
	--metric-max=streaming_collision_freeze_expired_event_count:0 \
	--metric-max=streaming_collision_freeze_expired_count:0 \
	--metric-min=streaming_collision_release_count:1 \
	--metric-max=streaming_collision_release_max_downward_speed_mps:0.001 \
	--metric-max=streaming_collision_freeze_max_descent_from_initial:0.001 \
	--metric-max=max_descent_from_initial:0.12 \
	--metric-min=stream_force_unready_applied:1

printf 'run: Zion stream spawn wall vista does not fall when ground is unconfirmed\n'

run_sim "$out_dir/zion_stream_spawn_wall_vista_no_fall.json" \
	--stream-route=cedar_hollow_zion_stream_route \
	--spawn=stream_wall_vista \
	--target=stream_west \
	--controller=scripted \
	--scenario=stream_spawn_no_fall \
	--stream-workers=0 \
	--stream-force-unready-cell=15,5 \
	--stream-force-unready-trigger-x=1550.0 \
	--stream-force-unready-ticks=720 \
	--max-ticks=900 \
	--stuck-window=120 \
	--stuck-min-progress=0.0 \
	--seed=12345

assert_metrics "$out_dir/zion_stream_spawn_wall_vista_no_fall.json" \
	--metric-min=streaming_collision_freeze_ticks:840 \
	--metric-min=streaming_collision_frozen_sample_ticks:840 \
	--metric-max=streaming_collision_freeze_expired_event_count:0 \
	--metric-max=streaming_collision_freeze_expired_count:0 \
	--metric-max=streaming_collision_release_count:0 \
	--metric-max=streaming_collision_release_max_downward_speed_mps:0.001 \
	--metric-max=streaming_collision_freeze_max_descent_from_initial:0.001 \
	--metric-max=max_descent_from_initial:0.001 \
	--metric-min=stream_force_unready_applied:1

printf 'run: Zion stream default scenic spawn holds above collision\n'

run_sim "$out_dir/zion_stream_spawn_demo_canyon_junction_no_fall.json" \
	--stream-route=cedar_hollow_zion_stream_route \
	--spawn=demo_canyon_junction \
	--target=stream_west \
	--controller=scripted \
	--scenario=stream_spawn_no_fall \
	--stream-workers=0 \
	--stream-force-unready-cell=15,15 \
	--stream-force-unready-trigger-x=1550.0 \
	--stream-force-unready-ticks=720 \
	--max-ticks=900 \
	--stuck-window=120 \
	--stuck-min-progress=0.0 \
	--seed=12345

assert_metrics "$out_dir/zion_stream_spawn_demo_canyon_junction_no_fall.json" \
	--metric-min=streaming_collision_freeze_ticks:720 \
	--metric-min=streaming_collision_frozen_sample_ticks:720 \
	--metric-max=streaming_collision_freeze_expired_event_count:0 \
	--metric-max=streaming_collision_freeze_expired_count:0 \
	--metric-min=streaming_collision_release_count:1 \
	--metric-max=streaming_collision_release_max_downward_speed_mps:0.001 \
	--metric-max=streaming_collision_freeze_max_descent_from_initial:0.001 \
	--metric-max=max_descent_from_initial:0.12 \
	--metric-min=stream_force_unready_applied:1
