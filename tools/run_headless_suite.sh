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

printf 'run: project opens headless\n'
"$godot_bin" --headless --path . --quit

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
	--target=flat_target \
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

run_sim "$out_dir/surface_sweep.json" \
	--scene=surface_strips \
	--controller=scripted \
	--scenario=surface_sweep \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=220 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

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
	--seed=12345 \
	--max-ticks=520 \
	--stuck-window=60 \
	--stuck-min-progress=0.05

run_sim "$out_dir/cedar_hollow_boardwalk_end.json" \
	--scene=cedar_hollow \
	--controller=pd \
	--spawn=trailhead \
	--target=boardwalk_end \
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
	--stuck-min-progress=0.03

./tools/check.sh
