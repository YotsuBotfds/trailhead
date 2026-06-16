printf 'run: cedar feature visuals\n'
"$godot_bin" --headless --path . res://tools/cedar_visual_inspector.tscn

printf 'run: visual bar assertions\n'
"$godot_bin" --headless --path . res://tools/cedar_visual_inspector.tscn

printf 'run: flat visuals\n'
"$godot_bin" --headless --path . res://tools/flat_visual_inspector.tscn

printf 'run: audio output preview\n'
"$godot_bin" --headless --path . res://tools/audio_output_inspector.tscn

printf 'run: terrain surface palette\n'
"$godot_bin" --headless --path . res://tools/terrain_palette_inspector.tscn

printf 'run: terrain surface sampler\n'
"$godot_bin" --headless --path . res://tools/terrain_surface_sampler_inspector.tscn

printf 'run: spike 1km render LOD\n'
"$godot_bin" --headless --path . res://tools/spike_1km_render_inspector.tscn

printf 'run: data resources\n'
"$godot_bin" --headless --path . res://tools/data_resource_inspector.tscn

printf 'run: chase camera rod (FX-25 horizontal-rod guard)\n'
"$godot_bin" --headless --path . --script res://tools/chase_camera_rod_fixture.gd
