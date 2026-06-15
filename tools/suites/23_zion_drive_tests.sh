run_sim "$out_dir/cedar_hollow_zion_pa_rus_flat_segment.json" \
	--scene=cedar_hollow_zion \
	--controller=scripted \
	--scenario=real_terrain_flat_segment \
	--spawn=trailhead \
	--target=0,0,-50.1 \
	--target-radius=0.05 \
	--seed=12345 \
	--max-ticks=6200 \
	--stuck-window=240 \
	--stuck-min-progress=0.02
assert_metrics "$out_dir/cedar_hollow_zion_pa_rus_flat_segment.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:120 \
	--source-min=tagged:120 \
	--metric-min=max_initial_forward_displacement:50 \
	--metric-min=contact_normal_sample_ticks:120 \
	--metric-max=max_flipped_ticks:0

run_sim "$out_dir/zion_heightmap_ramp_15_percent.json" \
	--scene=heightmap_ramp_probe \
	--controller=scripted \
	--scenario=clip_descent \
	--spawn=heightmap_ramp_start \
	--target=0,0,-5.25 \
	--seed=12345 \
	--max-ticks=500 \
	--stuck-window=120 \
	--stuck-min-progress=0.02
assert_metrics "$out_dir/zion_heightmap_ramp_15_percent.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:80 \
	--metric-min=chassis_clearance_sample_ticks:80 \
	--metric-min=contact_normal_sample_ticks:80 \
	--metric-min=max_descent_from_initial:0.18 \
	--metric-max=max_chassis_penetration_m:0.01 \
	--metric-max=max_flipped_ticks:0
