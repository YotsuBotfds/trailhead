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

run_sim "$out_dir/cedar_hollow_segment_overlook_to_ridge_gate.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=overlook_to_ridge_gate \
	--seed=12345 \
	--max-ticks=900 \
	--stuck-window=120 \
	--stuck-min-progress=0.015

run_sim "$out_dir/cedar_hollow_segment_ridge_gate_to_pine_floor.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=ridge_gate_to_pine_floor \
	--seed=12345 \
	--max-ticks=2200 \
	--stuck-window=120 \
	--stuck-min-progress=0.015

run_sim "$out_dir/cedar_hollow_segment_pine_floor_to_far_mile_marker.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=pine_floor_to_far_mile_marker \
	--seed=12345 \
	--max-ticks=4000 \
	--stuck-window=120 \
	--stuck-min-progress=0.015
