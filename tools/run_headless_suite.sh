#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out_dir="${OUT_DIR:-tests/out}"

mkdir -p "$out_dir"

run_sim() {
	out_file="$1"
	shift
	printf 'run: %s\n' "$out_file"
	"$godot_bin" --headless --fixed-fps 60 --path . res://scenes/sim_runner.tscn -- "$@" --out="$out_file"
}

assert_metrics() {
	printf 'assert: %s\n' "$1"
	./tools/assert_sim_metrics.py "$@"
}

printf 'run: project opens headless\n'
"$godot_bin" --headless --path . --quit

printf 'run: project input map defaults\n'
"$godot_bin" --headless --path . res://tools/input_map_inspector.tscn

run_sim "$out_dir/flat_target.json" \
	--scene=flat_plane \
	--controller=pd \
	--spawn=flat_spawn \
	--target=flat_target \
	--seed=12345 \
	--max-ticks=220 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/flat_flipped.json" \
	--scene=flat_plane \
	--controller=pd \
	--spawn=flat_flipped \
	--target=0,0,-3 \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/flat_flipped_yawed.json" \
	--scene=flat_plane \
	--controller=pd \
	--spawn=flat_flipped_yawed \
	--target=-3,0,-3 \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/ebrake_drift.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=ebrake_drift \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=220 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/launch_wheelie.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=launch_wheelie \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=160 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/reverse_drive.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=reverse_drive \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=160 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/surface_sweep.json" \
	--scene=surface_strips \
	--controller=scripted \
	--scenario=surface_sweep \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=220 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

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

run_sim "$out_dir/cedar_hollow_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=old_cedar \
	--seed=12345 \
	--max-ticks=360 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_overlook_ridge.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=overlook_ridge \
	--seed=12345 \
	--max-ticks=520 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_bog_bottom.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=bog_bottom \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_the_crossing.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=the_crossing \
	--target-radius=0.15 \
	--seed=12345 \
	--max-ticks=620 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_boardwalk_end.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=boardwalk_end \
	--target-radius=0.25 \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=culvert_mouth \
	--seed=12345 \
	--max-ticks=520 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=trailhead_to_culvert_mouth \
	--seed=12345 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_segment_overlook_to_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--route-segment=overlook_to_old_cedar \
	--seed=12345 \
	--stuck-window=60 \
	--stuck-min-progress=0.015

assert_metrics "$out_dir/flat_flipped.json" \
	--surface=packed_dirt:10 \
	--metric-min=flipped_event_count:1 \
	--metric-min=self_righted_event_count:1

assert_metrics "$out_dir/flat_flipped_yawed.json" \
	--surface=packed_dirt:10 \
	--metric-min=flipped_event_count:1 \
	--metric-min=self_righted_event_count:1

assert_metrics "$out_dir/ebrake_drift.json" \
	--surface=packed_dirt:40 \
	--metric-min=ebrake_ticks:80 \
	--metric-min=max_abs_slip_angle_deg:90.0 \
	--metric-min=max_abs_yaw_rate:10.0 \
	--metric-min=max_speed:2.5

assert_metrics "$out_dir/launch_wheelie.json" \
	--surface=packed_dirt:25 \
	--metric-min=front_air_rear_contact_ticks:8 \
	--metric-min=max_pitch_deg:8.0 \
	--metric-min=max_speed:3.0

assert_metrics "$out_dir/reverse_drive.json" \
	--surface=packed_dirt:25 \
	--metric-min=reverse_ticks:70 \
	--metric-min=max_reverse_distance:0.45

assert_metrics "$out_dir/surface_sweep.json" \
	--surface=packed_dirt:8 \
	--surface=tall_grass:10 \
	--surface=mud:10 \
	--surface=wet_stone:8 \
	--surface-sequence=packed_dirt,tall_grass,mud,wet_stone \
	--metric-min=max_abs_slip_angle_deg:3.0

assert_metrics "$out_dir/cedar_hollow_log_ramp.json" \
	--surface=wood_plank:20 \
	--surface-sequence=wood_plank,tall_grass,wood_plank \
	--metric-min=max_y_position:0.18 \
	--metric-min=max_pitch_deg:4.0

assert_metrics "$out_dir/cedar_hollow_old_cedar.json" \
	--surface=packed_dirt:40 \
	--landmark=old_cedar

assert_metrics "$out_dir/cedar_hollow_overlook_ridge.json" \
	--surface=loose_rock:20 \
	--landmark=overlook_ridge

assert_metrics "$out_dir/cedar_hollow_bog_bottom.json" \
	--surface=mud:2 \
	--landmark=bog_bottom

assert_metrics "$out_dir/cedar_hollow_the_crossing.json" \
	--surface=wood_plank:8 \
	--surface=mud:15 \
	--surface=wet_stone:5 \
	--surface-sequence=wood_plank,mud,wet_stone \
	--landmark=the_crossing

assert_metrics "$out_dir/cedar_hollow_boardwalk_end.json" \
	--surface=wood_plank:7 \
	--landmark=boardwalk_end

assert_metrics "$out_dir/cedar_hollow_culvert_mouth.json" \
	--surface=packed_dirt:50 \
	--landmark=culvert_mouth

assert_metrics "$out_dir/cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--surface=tall_grass:20 \
	--surface=packed_dirt:50 \
	--landmark=culvert_mouth

assert_metrics "$out_dir/cedar_hollow_segment_overlook_to_old_cedar.json" \
	--surface=loose_rock:20 \
	--surface=packed_dirt:90 \
	--landmark=old_cedar

run_sim "$out_dir/golden_flat_target.json" \
	--scene=flat_plane \
	--controller=replay \
	--replay=tests/golden/flat_target_replay.json \
	--spawn=flat_spawn \
	--target=flat_target \
	--seed=12345 \
	--max-ticks=220 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_flat_flipped.json" \
	--scene=flat_plane \
	--controller=replay \
	--replay=tests/golden/flat_flipped_replay.json \
	--spawn=flat_flipped \
	--target=0,0,-3 \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_old_cedar_replay.json \
	--spawn=trailhead \
	--target=old_cedar \
	--seed=12345 \
	--max-ticks=360 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_overlook_ridge.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_overlook_ridge_replay.json \
	--spawn=trailhead \
	--target=overlook_ridge \
	--seed=12345 \
	--max-ticks=520 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_bog_bottom.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_bog_bottom_replay.json \
	--spawn=trailhead \
	--target=bog_bottom \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_the_crossing.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_the_crossing_replay.json \
	--spawn=trailhead \
	--target=the_crossing \
	--target-radius=0.15 \
	--seed=12345 \
	--max-ticks=620 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_boardwalk_end.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_boardwalk_end_replay.json \
	--spawn=trailhead \
	--target=boardwalk_end \
	--target-radius=0.25 \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_culvert_mouth_replay.json \
	--spawn=trailhead \
	--target=culvert_mouth \
	--seed=12345 \
	--max-ticks=520 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_segment_trailhead_to_culvert_mouth.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_trailhead_to_culvert_mouth_replay.json \
	--route-segment=trailhead_to_culvert_mouth \
	--seed=12345 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/golden_cedar_hollow_segment_overlook_to_old_cedar.json" \
	--scene=cedar_hollow \
	--controller=replay \
	--replay=tests/golden/cedar_hollow_segment_overlook_to_old_cedar_replay.json \
	--route-segment=overlook_to_old_cedar \
	--seed=12345 \
	--stuck-window=60 \
	--stuck-min-progress=0.015

printf 'run: cedar feature visuals\n'
"$godot_bin" --headless --path . res://tools/cedar_visual_inspector.tscn

printf 'run: flat visuals\n'
"$godot_bin" --headless --path . res://tools/flat_visual_inspector.tscn

printf 'run: audio output preview\n'
"$godot_bin" --headless --path . res://tools/audio_output_inspector.tscn

printf 'run: terrain surface palette\n'
"$godot_bin" --headless --path . res://tools/terrain_palette_inspector.tscn

printf 'run: data resources\n'
"$godot_bin" --headless --path . res://tools/data_resource_inspector.tscn

./tools/check_assets.sh
./tools/check_generated_assets.sh
./tools/check.sh
