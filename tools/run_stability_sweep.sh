#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out_dir="${OUT_DIR:-tests/out/stability}"
seeds="${SEEDS:-12345 67890 24680}"

mkdir -p "$out_dir"

run_sim() {
	out_file="$1"
	shift
	printf 'run: %s\n' "$out_file"
	"$godot_bin" --headless --fixed-fps 120 --path . res://scenes/sim_runner.tscn -- "$@" --out="$out_file"
}

assert_metrics() {
	printf 'assert: %s\n' "$1"
	./tools/assert_sim_metrics.py "$@"
}

run_log_ramp() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_cedar_hollow_log_ramp.json"
	run_sim "$out_file" \
		--scene=cedar_hollow \
		--controller=scripted \
		--scenario=log_ramp \
		--spawn=trailhead \
		--target=old_cedar \
		--seed="$seed" \
		--max-ticks=440 \
		--stuck-window=120 \
		--stuck-min-progress=0.02
	# The scripted ramp now approaches on packed_gravel, then climbs wood_plank.
	# Keep the sequence narrow so a future dirt-first line is visible.
	assert_metrics "$out_file" \
		--surface=wood_plank:20 \
		--surface-sequence=packed_gravel,wood_plank \
		--metric-min=max_y_position:0.18 \
		--metric-min=max_pitch_deg:4.0
}

run_flat_flipped_yawed() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_flat_flipped_yawed.json"
	run_sim "$out_file" \
		--scene=flat_plane \
		--controller=pd \
		--spawn=flat_flipped_yawed \
		--target=-3,0,-3 \
		--seed="$seed" \
		--max-ticks=840 \
		--stuck-window=120 \
		--stuck-min-progress=0.05
	assert_metrics "$out_file" \
		--surface=packed_dirt:10 \
		--predicate=self_right_heading_preserved \
		--metric-min=flipped_event_count:1 \
		--metric-min=self_righted_event_count:1 \
		--metric-near=self_right_heading_error_deg:0.0:1.0
}

run_old_cedar() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_cedar_hollow_old_cedar.json"
	run_sim "$out_file" \
		--scene=cedar_hollow \
		--controller=pd \
		--spawn=trailhead \
		--target=old_cedar \
		--seed="$seed" \
		--max-ticks=720 \
		--stuck-window=120 \
		--stuck-min-progress=0.05
	assert_metrics "$out_file" \
		--surface=packed_gravel:20 \
		--surface=packed_dirt:40 \
		--landmark=old_cedar
}

run_overlook_ridge() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_cedar_hollow_overlook_ridge.json"
	run_sim "$out_file" \
		--scene=cedar_hollow \
		--controller=pd \
		--spawn=trailhead \
		--target=overlook_ridge \
		--seed="$seed" \
		--max-ticks=1040 \
		--stuck-window=120 \
		--stuck-min-progress=0.05
	assert_metrics "$out_file" \
		--surface=loose_rock:20 \
		--landmark=overlook_ridge
}

run_bog_bottom() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_cedar_hollow_bog_bottom.json"
	run_sim "$out_file" \
		--scene=cedar_hollow \
		--controller=pd \
		--spawn=trailhead \
		--target=bog_bottom \
		--seed="$seed" \
		--max-ticks=840 \
		--stuck-window=120 \
		--stuck-min-progress=0.05
	assert_metrics "$out_file" \
		--surface=mud:2 \
		--landmark=bog_bottom
}

run_the_crossing() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_cedar_hollow_the_crossing.json"
	run_sim "$out_file" \
		--scene=cedar_hollow \
		--controller=pd \
		--spawn=trailhead \
		--target=the_crossing \
		--target-radius=0.15 \
		--seed="$seed" \
		--max-ticks=1240 \
		--stuck-window=120 \
		--stuck-min-progress=0.05
	assert_metrics "$out_file" \
		--surface=wood_plank:8 \
		--surface=mud:15 \
		--surface=wet_stone:5 \
		--surface-sequence=wood_plank,mud,wet_stone \
		--landmark=the_crossing
}

run_boardwalk_end() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_cedar_hollow_boardwalk_end.json"
	run_sim "$out_file" \
		--scene=cedar_hollow \
		--controller=pd \
		--spawn=trailhead \
		--target=boardwalk_end \
		--target-radius=0.25 \
		--seed="$seed" \
		--max-ticks=840 \
		--stuck-window=120 \
		--stuck-min-progress=0.05
	assert_metrics "$out_file" \
		--surface=wood_plank:7 \
		--landmark=boardwalk_end
}

run_culvert_mouth() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_cedar_hollow_culvert_mouth.json"
	run_sim "$out_file" \
		--scene=cedar_hollow \
		--controller=pd \
		--spawn=trailhead \
		--target=culvert_mouth \
		--seed="$seed" \
		--max-ticks=1040 \
		--stuck-window=120 \
		--stuck-min-progress=0.05
	assert_metrics "$out_file" \
		--surface=packed_dirt:50 \
		--landmark=culvert_mouth
}

run_trailhead_to_culvert_segment() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_cedar_hollow_segment_trailhead_to_culvert_mouth.json"
	run_sim "$out_file" \
		--scene=cedar_hollow \
		--controller=pd \
		--route-segment=trailhead_to_culvert_mouth \
		--seed="$seed" \
		--max-ticks=1040 \
		--stuck-window=120 \
		--stuck-min-progress=0.05
	assert_metrics "$out_file" \
		--surface=tall_grass:20 \
		--surface=packed_dirt:50 \
		--landmark=culvert_mouth
}

run_overlook_to_old_cedar_segment() {
	seed="$1"
	out_file="$out_dir/seed_${seed}_cedar_hollow_segment_overlook_to_old_cedar.json"
	run_sim "$out_file" \
		--scene=cedar_hollow \
		--controller=pd \
		--route-segment=overlook_to_old_cedar \
		--seed="$seed" \
		--max-ticks=3200 \
		--stuck-window=120 \
		--stuck-min-progress=0.015
	# The route is now a rock descent with only a brief packed-dirt handoff
	# near Old Cedar, replacing the old dirt-heavy line.
	assert_metrics "$out_file" \
		--surface=loose_rock:200 \
		--surface=packed_dirt:3 \
		--landmark=old_cedar
}

for seed in $seeds; do
	printf 'seed: %s\n' "$seed"
	run_flat_flipped_yawed "$seed"
	run_log_ramp "$seed"
	run_old_cedar "$seed"
	run_overlook_ridge "$seed"
	run_bog_bottom "$seed"
	run_the_crossing "$seed"
	run_boardwalk_end "$seed"
	run_culvert_mouth "$seed"
	run_trailhead_to_culvert_segment "$seed"
	run_overlook_to_old_cedar_segment "$seed"
done

printf 'ok: Cedar Hollow stability sweep passed for seeds: %s\n' "$seeds"
