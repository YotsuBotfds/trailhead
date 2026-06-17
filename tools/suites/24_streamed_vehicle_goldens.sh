run_sim "$out_dir/spike_1km_streamed_west_gate_to_east_gate.json" \
	--stream-route=spike_1km_route \
	--segment=west_gate_to_east_gate \
	--controller=pd \
	--stream-workers=0 \
	--seed=12345 \
	--max-ticks=3000 \
	--stuck-window=240 \
	--stuck-min-progress=0.02
assert_metrics "$out_dir/spike_1km_streamed_west_gate_to_east_gate.json" \
	--predicate=reached_target \
	--predicate=target_landmark_event_observed \
	--landmark=east_gate \
	--surface=loose_rock:1100 \
	--surface=packed_dirt:120 \
	--metric-min=surface_source_terrain_count:1 \
	--metric-max=surface_source_fallback_count:0 \
	--metric-min=activation_tick_count:25 \
	--metric-max=max_flipped_ticks:0

run_sim "$out_dir/cedar_hollow_zion_streamed_corridor.json" \
	--stream-route=cedar_hollow_zion_stream_route \
	--segment=stream_west_to_east \
	--controller=pd \
	--stream-workers=0 \
	--seed=12345 \
	--max-ticks=3000 \
	--stuck-window=240 \
	--stuck-min-progress=0.02
assert_metrics "$out_dir/cedar_hollow_zion_streamed_corridor.json" \
	--predicate=reached_target \
	--predicate=target_landmark_event_observed \
	--landmark=stream_east \
	--surface=paved_road:1200 \
	--metric-min=surface_source_terrain_count:1 \
	--metric-max=surface_source_fallback_count:0 \
	--metric-min=activation_tick_count:25 \
	--metric-max=max_flipped_ticks:0
