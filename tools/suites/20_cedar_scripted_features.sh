run_sim "$out_dir/cedar_hollow_log_ramp.json" \
	--scene=cedar_hollow \
	--controller=scripted \
	--scenario=log_ramp \
	--spawn=trailhead \
	--target=old_cedar \
	--seed=12345 \
	--max-ticks=440 \
	--stuck-window=120 \
	--stuck-min-progress=0.02
