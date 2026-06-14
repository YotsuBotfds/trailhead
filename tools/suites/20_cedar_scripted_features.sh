run_sim "$out_dir/cedar_hollow_log_ramp.json" \
	--scene=cedar_hollow \
	--controller=scripted \
	--scenario=log_ramp \
	--spawn=trailhead \
	--target=old_cedar \
	--seed=12345 \
	--max-ticks=220 \
	--stuck-window=60 \
	--stuck-min-progress=0.02
