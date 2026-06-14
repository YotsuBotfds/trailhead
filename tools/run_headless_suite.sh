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
	"$godot_bin" --headless --fixed-fps 120 --path . res://scenes/sim_runner.tscn -- "$@" --out="$out_file"
}

assert_metrics() {
	printf 'assert: %s\n' "$1"
	./tools/assert_sim_metrics.py "$@"
}

for suite_path in tools/suites/*.sh; do
	if [ ! -e "$suite_path" ]; then
		continue
	fi
	printf 'suite: %s\n' "$suite_path"
	. "$suite_path"
done
