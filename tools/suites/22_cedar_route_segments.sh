run_sim "$out_dir/cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=trailhead_to_culvert_mouth \
	--seed=12345 \
	--max-ticks=1040 \
	--stuck-window=120 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_segment_overlook_to_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=overlook_to_old_cedar \
	--seed=12345 \
	--max-ticks=3200 \
	--stuck-window=120 \
	--stuck-min-progress=0.015
