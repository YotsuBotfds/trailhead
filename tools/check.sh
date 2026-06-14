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
check "no untyped member vars" sh -c '! rg -n "^[[:space:]]*var[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(=|$)" --glob "*.gd" .'
check "no generic float/int math helpers" sh -c '! rg -n "\\b(max|min|abs|clamp|snapped)\\s*\\(" --glob "*.gd" .'
check "EventBus signal names are snake_case groups" sh -c '! rg -n -P "^signal[[:space:]]+(?!vehicle_|world_|camera_|sim_)[A-Za-z0-9_]+" autoload systems --glob "*.gd"'
check "no sim-path render/input/audio access" sh -c '! rg -n "\\b(Input|Camera3D|AudioStreamPlayer|MeshInstance3D)\\b" systems/sim systems/vehicle systems/world --glob "*.gd"'
check "no sim-path render asset dependencies" sh -c '! rg -n "res://(systems/render|assets/models)" systems/sim systems/vehicle systems/world --glob "*.gd"'
check "Python tool syntax" sh -c 'python3 -m py_compile tools/*.py'
check "shell tool syntax" sh -c 'for path in tools/*.sh; do sh -n "$path" || exit 1; done'

exit "$status"
