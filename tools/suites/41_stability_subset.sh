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
	--surface=loose_rock:12 \
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

run_sim "$out_dir/stability_seed_${stability_seed}_cedar_hollow_segment_overlook_to_ridge_gate.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=overlook_to_ridge_gate \
	--seed="$stability_seed" \
	--max-ticks=900 \
	--stuck-window=120 \
	--stuck-min-progress=0.015

assert_metrics "$out_dir/stability_seed_${stability_seed}_cedar_hollow_segment_overlook_to_ridge_gate.json" \
	--surface=packed_dirt:20 \
	--source-min=terrain:40 \
	--landmark=ridge_gate

run_sim "$out_dir/stability_seed_${stability_seed}_cedar_hollow_segment_ridge_gate_to_pine_floor.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=ridge_gate_to_pine_floor \
	--seed="$stability_seed" \
	--max-ticks=2200 \
	--stuck-window=120 \
	--stuck-min-progress=0.015

assert_metrics "$out_dir/stability_seed_${stability_seed}_cedar_hollow_segment_ridge_gate_to_pine_floor.json" \
	--surface=packed_dirt:120 \
	--source-min=terrain:120 \
	--landmark=pine_floor

run_sim "$out_dir/stability_seed_${stability_seed}_cedar_hollow_segment_pine_floor_to_far_mile_marker.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=pine_floor_to_far_mile_marker \
	--seed="$stability_seed" \
	--max-ticks=4000 \
	--stuck-window=120 \
	--stuck-min-progress=0.015

assert_metrics "$out_dir/stability_seed_${stability_seed}_cedar_hollow_segment_pine_floor_to_far_mile_marker.json" \
	--surface=packed_dirt:180 \
	--source-min=terrain:180 \
	--landmark=far_mile_marker
