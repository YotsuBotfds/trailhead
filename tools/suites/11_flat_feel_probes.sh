run_sim "$out_dir/ebrake_drift.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=ebrake_drift \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=220 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/launch_wheelie.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=launch_wheelie \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=160 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/reverse_drive.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=reverse_drive \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=160 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/surface_sweep.json" \
	--scene=surface_strips \
	--controller=scripted \
	--scenario=surface_sweep \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=220 \
	--stuck-window=60 \
	--stuck-min-progress=0.05
