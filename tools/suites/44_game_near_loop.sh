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
printf 'run: campfire silence zone fixture\n'
python3 tools/campfire_silence_zone_fixture.py
