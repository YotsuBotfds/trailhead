stability_seed=67890

run_sim "$out_dir/stability_seed_${stability_seed}_cedar_hollow_overlook_ridge.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=overlook_ridge \
	--seed="$stability_seed" \
	--max-ticks=1040 \
	--stuck-window=120 \
	--stuck-min-progress=0.05

assert_metrics "$out_dir/stability_seed_${stability_seed}_cedar_hollow_overlook_ridge.json" \
	--surface=loose_rock:80 \
	--landmark=overlook_ridge

run_sim "$out_dir/stability_seed_${stability_seed}_cedar_hollow_segment_overlook_to_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=overlook_to_old_cedar \
	--seed="$stability_seed" \
	--max-ticks=3200 \
	--stuck-window=120 \
	--stuck-min-progress=0.015

# The feel re-record keeps this segment rock-heavy through Old Cedar.
# Keep the floor near the golden route so future dirt-heavy drift is visible.
assert_metrics "$out_dir/stability_seed_${stability_seed}_cedar_hollow_segment_overlook_to_old_cedar.json" \
	--surface=loose_rock:150 \
	--landmark=old_cedar
