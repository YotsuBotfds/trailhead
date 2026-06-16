assert_metrics "$out_dir/flat_flipped.json" \
	--surface=packed_dirt:10 \
	--metric-min=flipped_event_count:1 \
	--metric-min=self_righted_event_count:1 \
	--metric-min=pace_clock_incident_event_count:1 \
	--metric-min=logbook_entry_written_event_count:1

assert_metrics "$out_dir/flat_flipped_yawed.json" \
	--surface=packed_dirt:10 \
	--metric-min=flipped_event_count:1 \
	--metric-min=self_righted_event_count:1

assert_metrics "$out_dir/ebrake_drift.json" \
	--surface=packed_dirt:40 \
	--metric-min=ebrake_ticks:120 \
	--metric-min=max_abs_slip_angle_deg:45.0 \
	--metric-min=max_abs_yaw_rate:1.3 \
	--metric-min=max_speed:2.5

assert_metrics "$out_dir/launch_wheelie.json" \
	--surface=packed_dirt:25 \
	--metric-min=front_air_rear_contact_ticks:16 \
	--metric-min=max_pitch_deg:8.0 \
	--metric-min=max_speed:3.0

assert_metrics "$out_dir/reverse_drive.json" \
	--surface=packed_dirt:25 \
	--metric-min=reverse_ticks:140 \
	--metric-min=max_reverse_distance:0.45
