run_sim "$out_dir/standstill_yaw_rate.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=standstill_yaw_rate \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=320 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/standstill_yaw_rate.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=max_abs_yaw_rate:0.06 \
	--metric-max=max_abs_yaw_rate:0.27

run_sim "$out_dir/steering_speed_ramp.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=steering_speed_ramp \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/steering_speed_ramp.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=steering_speed_low_sample_ticks:6 \
	--metric-min=steering_speed_mid_sample_ticks:6 \
	--metric-min=steering_speed_high_sample_ticks:6 \
	--metric-min=steering_speed_high_max_abs_yaw_rate:0.30

run_sim "$out_dir/offtrail_escape_tall_grass.json" \
	--scene=offtrail_escape \
	--controller=scripted \
	--scenario=offtrail_escape \
	--spawn=offtrail_tall_grass \
	--seed=12345 \
	--max-ticks=340 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/offtrail_escape_tall_grass.json" \
	--predicate=scenario_passed \
	--surface=tall_grass:40 \
	--metric-min=max_initial_forward_displacement:0.55

run_sim "$out_dir/offtrail_escape_loose_rock.json" \
	--scene=offtrail_escape \
	--controller=scripted \
	--scenario=offtrail_escape \
	--spawn=offtrail_loose_rock \
	--seed=12345 \
	--max-ticks=340 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/offtrail_escape_loose_rock.json" \
	--predicate=scenario_passed \
	--surface=loose_rock:40 \
	--metric-min=max_initial_forward_displacement:0.55

run_sim "$out_dir/recover_to_trail.json" \
	--scene=recovery_trap \
	--controller=scripted \
	--scenario=recover_to_trail \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=440 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/recover_to_trail.json" \
	--predicate=scenario_passed \
	--predicate=event_bus_contract \
	--surface=packed_dirt:40 \
	--metric-min=recovered_to_trail_event_count:1 \
	--metric-min=max_recovery_displacement:0.025

run_sim "$out_dir/hill_hold_grade.json" \
	--scene=hill_hold_probe \
	--controller=scripted \
	--scenario=hill_hold \
	--spawn=hill_hold_grade \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/hill_hold_grade.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-max=max_flat_displacement_from_initial:0.04

run_sim "$out_dir/hill_hold_steep.json" \
	--scene=hill_hold_probe \
	--controller=scripted \
	--scenario=hill_hold \
	--spawn=hill_hold_steep \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/hill_hold_steep.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=final_flat_displacement_from_initial:0.08 \
	--metric-max=final_flat_displacement_from_initial:1.6

run_sim "$out_dir/lateral_slide.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=lateral_slide \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=440 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/lateral_slide.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=max_abs_lateral_speed:0.18 \
	--metric-max=final_abs_lateral_speed:0.08

run_sim "$out_dir/suspension_drop.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=suspension_drop \
	--spawn=suspension_drop \
	--seed=12345 \
	--max-ticks=360 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/suspension_drop.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=contact_normal_sample_ticks:80 \
	--metric-min=max_speed:2.0 \
	--metric-max=post_settle_y_amplitude:0.02 \
	--metric-max=max_post_settle_vertical_speed:0.08

run_sim "$out_dir/roll_stability.json" \
	--scene=roll_stability_probe \
	--controller=scripted \
	--scenario=roll_stability \
	--spawn=roll_stability_side_slope \
	--seed=12345 \
	--max-ticks=360 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/roll_stability.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=contact_normal_sample_ticks:80 \
	--metric-min=max_contact_normal_tilt_deg:16.0 \
	--metric-min=max_initial_forward_displacement:1.2 \
	--metric-max=max_abs_roll_deg:30.0
