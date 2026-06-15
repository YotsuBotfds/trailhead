printf 'run: spike 1km route resource inspector\n'
"$godot_bin" --headless --fixed-fps 120 --path . res://tools/spike_1km_route_inspector.tscn

run_sim "$out_dir/spike_1km_route_segment_0_smoke.json" \
	--route spike_1km_route \
	--segment 0
