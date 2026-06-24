#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

status=0

check() {
	name="$1"
	shift
	if "$@"; then
		printf 'ok: %s\n' "$name"
	else
		printf 'fail: %s\n' "$name" >&2
		status=1
	fi
}

check "no var := declarations" sh -c '! rg -n "^[[:space:]]*var[[:space:]].*:=" --glob "*.gd" .'
check "no untyped member vars" sh -c '
	! rg -n "^[[:space:]]*var[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(=|$)" --glob "*.gd" . &&
	findings="$(rg -n -P "^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*var\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*((Array|Dictionary)(?!\s*\[)|Array\s*\[\s*Dictionary\s*\])" \
		autoload data scenes systems tests tools --glob "*.gd" || true)" &&
	filtered="$(printf "%s\n" "$findings" | rg -v "^systems/sim/sim_runner\.gd:[0-9]+:var _telemetry: Array\[Dictionary\] = \[\]$" || true)" &&
	if [ -n "$filtered" ]; then
		printf "%s\n" "$filtered" >&2
		exit 1
	fi
'
check "no generic float/int math helpers" sh -c '! rg -n "\\b(max|min|abs|clamp|snapped)\\s*\\(" --glob "*.gd" .'
check "EventBus signal names are snake_case groups" sh -c '! rg -n -P "^signal[[:space:]]+(?!vehicle_|world_|camera_|sim_)[A-Za-z0-9_]+" autoload systems --glob "*.gd"'
check "sim/render determinism boundary" sh -c '
	! rg -n "\\b(Input|Camera3D|AudioStreamPlayer|MeshInstance3D)\\b" systems/sim systems/vehicle systems/world --glob "*.gd" &&
	time_findings="$(rg -n "\\bTIME\\b" systems scenes data --glob "*.gdshader" --glob "*.shader" --glob "*.gd" || true)" &&
	time_filtered="" &&
	if [ -n "$time_findings" ]; then
		time_filtered="$(printf "%s\n" "$time_findings" | rg -v "^systems/render/water_visual\\.gdshader:|^systems/render/grass_billboard\\.gdshader:" || true)"
	fi &&
	if [ -n "$time_filtered" ]; then
		printf "%s\n" "$time_filtered" >&2
		exit 1
	fi
'
check "no wall-clock in sim/vehicle/world" sh -c '! rg -n -P "\bTime\.|OS\.get_unix_time|OS\.get_system_time|OS\.get_datetime|get_ticks_usec|get_ticks_msec" systems/sim systems/vehicle systems/world --glob "*.gd"'
check "no sim-path render asset dependencies" sh -c '! rg -n "res://(systems/render|assets/models)" systems/sim systems/vehicle systems/world --glob "*.gd"'
check "Python tool syntax" sh -c 'python3 -m py_compile tools/*.py'
check "shell tool syntax" sh -c 'for path in tools/*.sh; do sh -n "$path" || exit 1; done'
check "headless suite aggregates failures" sh tools/test_run_headless_suite_aggregation.sh
check "every inspector/fixture is suite-wired or allowlisted" sh -c '
	missing="" &&
	for file in tools/*_inspector.gd tools/*_fixture.gd tools/*_fixture.py; do
		[ -e "$file" ] || continue
		base="${file##*/}"
		stem="${base%.*}"
		if rg -q "$stem" tools/suites/*.sh; then
			continue
		fi
		if rg -q -x "$stem" tools/manual_tools_allowlist.txt; then
			continue
		fi
		missing="${missing}${file}
"
	done
	if [ -n "$missing" ]; then
		printf "%s" "$missing" >&2
		exit 1
	fi
'
check "Zion bake determinism" python3 tools/check_zion_bake_determinism.py
check "collision tile integrity" python3 tools/check_collision_tile_integrity.py data/regions/spike_1km
check "Zion collision tile integrity" python3 tools/check_collision_tile_integrity.py data/regions/cedar_hollow_zion
check "Godot binary SHA pin" tools/check_godot_binary_sha.sh
check "Zion surface-ID PNG" python3 tools/check_surface_id_png.py data/terrain/cedar_hollow_zion_surface_id.png --require-grayscale --min-ids 4 --expected-ids 1,2,3,4,5,6 --forbid-zero
check "Zion macro-albedo PNG" python3 tools/check_zion_macro_albedo_png.py data/terrain/cedar_hollow_zion_macro_albedo.png --expected-width 256 --expected-height 265 --require-color-type 2

exit "$status"
