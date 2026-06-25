printf 'run: tile streamer expected activation ticks\n'
python3 tools/expected_activation_ticks_fixture.py

printf 'run: tile streamer prewarm crossing cook counter\n'
"$godot_bin" --headless --fixed-fps 120 --path . res://tools/tile_streamer_prewarm_fixture.tscn
