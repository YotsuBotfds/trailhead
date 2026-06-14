run_sim "$out_dir/flat_target.json" \
	--scene=flat_plane \
	--controller=pd \
	--spawn=flat_spawn \
	--target=flat_target \
	--seed=12345 \
	--max-ticks=440 \
	--stuck-window=120 \
	--stuck-min-progress=0.05

run_sim "$out_dir/flat_flipped.json" \
	--scene=flat_plane \
	--controller=pd \
	--spawn=flat_flipped \
	--target=0,0,-3 \
	--seed=12345 \
	--max-ticks=840 \
	--stuck-window=120 \
	--stuck-min-progress=0.05

run_sim "$out_dir/flat_flipped_yawed.json" \
	--scene=flat_plane \
	--controller=pd \
	--spawn=flat_flipped_yawed \
	--target=-3,0,-3 \
	--seed=12345 \
	--max-ticks=840 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
