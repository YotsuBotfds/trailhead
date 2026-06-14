run_sim "$out_dir/terrain_surface_map_probe.json" \
	--scene=terrain_surface_map_probe \
	--controller=pd \
	--spawn=flat_spawn \
	--target=5.0,0,-7.8 \
	--target-radius=0.25 \
	--seed=12345 \
	--max-ticks=1560 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
