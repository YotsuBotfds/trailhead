# Reserved by the forward gate-zero pass.
# Track C appends recover/photo/pace/logbook/mud-key/golden-line fixtures here.
printf 'run: recover proximity fixture\n'
python3 tools/recover_proximity_fixture.py
printf 'run: recoverable render fixture\n'
python3 tools/recoverable_render_fixture.py
printf 'run: pace clock fixture\n'
python3 tools/pace_clock_fixture.py
printf 'run: photo stationary fixture\n'
python3 tools/photo_stationary_fixture.py
printf 'run: logbook entry fixture\n'
python3 tools/logbook_entry_fixture.py
printf 'run: frequency livery fixture\n'
python3 tools/frequency_livery_fixture.py
printf 'run: mud key fixture\n'
python3 tools/mud_key_fixture.py
printf 'run: golden line fixture\n'
python3 tools/golden_line_fixture.py
run_sim "$out_dir/event_bus_coverage.json" \
	--scene=cedar_hollow \
	--controller=scripted \
	--scenario=event_bus_coverage \
	--spawn=trailhead \
	--target=old_cedar \
	--seed=12345 \
	--max-ticks=160
assert_metrics "$out_dir/event_bus_coverage.json" \
	--predicate=scenario_passed \
	--metric-min=recoverable_object_tagged_event_count:1 \
	--metric-min=egg_triggered_event_count:1 \
	--metric-min=logbook_entry_written_event_count:1
printf 'run: campfire silence zone fixture\n'
python3 tools/campfire_silence_zone_fixture.py
