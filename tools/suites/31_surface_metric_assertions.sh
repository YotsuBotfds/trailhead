assert_metrics "$out_dir/surface_sweep.json" \
	--surface=packed_dirt:8 \
	--surface=tall_grass:10 \
	--surface=mud:10 \
	--surface=wet_stone:8 \
	--surface-sequence=packed_dirt,tall_grass,mud,wet_stone \
	--metric-min=max_abs_slip_angle_deg:2.0 \
	--metric-min=max_vehicle_contamination.dust:0.5 \
	--metric-min=max_vehicle_contamination.mud:0.5 \
	--metric-min=max_vehicle_contamination.wetness:0.4

assert_metrics "$out_dir/terrain_surface_map_probe.json" \
	--surface=mud:10 \
	--surface=wet_stone:5 \
	--surface-sequence=packed_dirt,tall_grass,mud,wet_stone \
	--source-min=terrain:100
