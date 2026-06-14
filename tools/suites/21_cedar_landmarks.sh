run_sim "$out_dir/cedar_hollow_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=old_cedar \
	--seed=12345 \
	--max-ticks=720 \
	--stuck-window=120 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_overlook_ridge.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=overlook_ridge \
	--seed=12345 \
	--max-ticks=1040 \
	--stuck-window=120 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_bog_bottom.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=bog_bottom \
	--seed=12345 \
	--max-ticks=840 \
	--stuck-window=120 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_the_crossing.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=the_crossing \
	--target-radius=0.15 \
	--seed=12345 \
	--max-ticks=1240 \
	--stuck-window=120 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_boardwalk_end.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=boardwalk_end \
	--target-radius=0.25 \
	--seed=12345 \
	--max-ticks=840 \
	--stuck-window=120 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=culvert_mouth \
	--seed=12345 \
	--max-ticks=1040 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
