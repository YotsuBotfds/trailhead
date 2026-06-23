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

# Re-baselined 2026-06-23 (Q78): the id-6 paved_road strip is 13 scattered patches
# (largest ~60x30m), none on this corridor — there is no long paved road here. This
# golden's job is to validate STREAMING along the corridor; pavement-surface coverage is
# asserted by the pa_rus + zion_surface_map_probe goldens. So assert the corridor's real
# dominant surface (loose_rock, ~1394 ticks) instead of the stale paved_road expectation.
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
	--surface=loose_rock:1200 \
	--metric-min=surface_source_terrain_count:1 \
	--metric-max=surface_source_fallback_count:0 \
	--metric-min=activation_tick_count:25 \
	--metric-max=max_flipped_ticks:0
