printf 'run: project opens headless\n'
"$godot_bin" --headless --path . --quit

printf 'run: project input map defaults\n'
"$godot_bin" --headless --path . res://tools/input_map_inspector.tscn

printf 'run: gamepad bindings (host-injected, no device)\n'
"$godot_bin" --headless --path . res://tools/gamepad_binding_inspector.tscn
