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
	--metric-min=max_abs_yaw_rate:0.35

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
