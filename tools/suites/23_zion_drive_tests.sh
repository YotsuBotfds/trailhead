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
	--surface=packed_gravel:120 \
	--source-min=terrain:120 \
	--terrain-id-min=6:120 \
	--metric-min=max_initial_forward_displacement:50 \
	--metric-min=contact_normal_sample_ticks:120 \
	--metric-max=max_flipped_ticks:0

run_sim "$out_dir/zion_surface_map_probe.json" \
	--scene=zion_surface_map_probe \
	--controller=pd \
	--spawn=flat_spawn \
	--target=0,0,-11.4 \
	--target-radius=0.35 \
	--seed=12345 \
	--max-ticks=2400 \
	--stuck-window=180 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/zion_surface_map_probe.json" \
	--surface=wet_stone:5 \
	--surface=packed_gravel:20 \
	--surface=packed_dirt:5 \
	--surface=loose_rock:5 \
	--surface=tall_grass:5 \
	--surface-sequence=wet_stone,packed_gravel,packed_dirt,loose_rock,tall_grass,packed_gravel \
	--source-min=terrain:120 \
	--terrain-id-min=1:5 \
	--terrain-id-min=2:5 \
	--terrain-id-min=3:5 \
	--terrain-id-min=4:5 \
	--terrain-id-min=5:5 \
	--terrain-id-min=6:5 \
	--metric-min=max_vehicle_contamination.wetness:0.2 \
	--metric-min=max_vehicle_contamination.dust:0.2 \
	--metric-max=max_flipped_ticks:0

run_watchman_grade_sim() {
	out_file="$1"
	shift
	printf 'run: %s\n' "$out_file"
	"$godot_bin" --headless --fixed-fps 120 --path . res://scenes/test_zion_watchman_grade.tscn -- "$@" --out="$out_file"
}

run_watchman_grade_sim "$out_dir/cedar_hollow_zion_watchman_grade.json" \
	--scene=heightmap_ramp_probe \
	--controller=scripted \
	--scenario=clip_descent \
	--spawn=heightmap_ramp_start \
	--target=0,0,-5.25 \
	--seed=12345 \
	--max-ticks=700 \
	--stuck-window=120 \
	--stuck-min-progress=0.02
assert_metrics "$out_dir/cedar_hollow_zion_watchman_grade.json" \
	--predicate=scenario_passed \
	--predicate=reached_target \
	--surface=packed_dirt:80 \
	--metric-min=chassis_clearance_sample_ticks:80 \
	--metric-min=contact_normal_sample_ticks:80 \
	--metric-min=max_contact_normal_tilt_deg:13.0 \
	--metric-min=max_descent_from_initial:5.8 \
	--metric-max=max_chassis_penetration_m:0.0 \
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
