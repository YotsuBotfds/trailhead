printf 'run: Zion river ribbon height\n'
"$godot_bin" --headless --path . res://tools/zion_water_ribbon_height_fixture.tscn

printf 'run: Zion playable streamed visuals\n'
"$godot_bin" --headless --path . res://tools/zion_playable_inspector.tscn

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

printf 'run: render tile streamer lifecycle\n'
"$godot_bin" --headless --path . res://tools/render_tile_streamer_fixture.tscn

printf 'run: rendered hull vs streamed terrain clearance\n'
"$godot_bin" --headless --path . res://tools/rendered_hull_terrain_clearance_fixture.tscn

printf 'run: render dynamic resolution controller\n'
"$godot_bin" --headless --path . res://tools/render_dynamic_resolution_fixture.tscn

printf 'run: data resources\n'
"$godot_bin" --headless --path . res://tools/data_resource_inspector.tscn

printf 'run: chase camera rod (FX-25 horizontal-rod guard)\n'
"$godot_bin" --headless --path . --script res://tools/chase_camera_rod_fixture.gd

printf 'run: chase camera stop-lock (stationary freeze guard)\n'
"$godot_bin" --headless --path . res://tools/chase_camera_stop_lock_fixture.tscn
