#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out_dir="${OUT_DIR:-tests/out}"

mkdir -p "$out_dir"

# ------------------------------------------------------------------
# Concurrency guard. The full suite spawns many headless Godot processes in
# sequence; running several suites at once (e.g. many parallel executor lanes)
# swarms the machine and deadlocks, leaving orphaned Godot that accumulate all
# session. Serialize every suite run machine-wide with a macOS-safe mkdir mutex,
# and self-terminate (releasing the lock + reaping our Godot children) if we
# ever hang, so a stall can never wedge the queue or leak processes.
# Tunables: TRAILHEAD_SUITE_LOCK, SUITE_LOCK_WAIT_MAX, SUITE_DEADLINE_SECS.
# ------------------------------------------------------------------
main_pid=$$
lock_dir="${TRAILHEAD_SUITE_LOCK:-/tmp/trailhead-suite.lock}"
lock_wait_max="${SUITE_LOCK_WAIT_MAX:-2400}"
suite_deadline="${SUITE_DEADLINE_SECS:-900}"
watchdog_pid=""

cleanup() {
	[ -n "$watchdog_pid" ] && kill "$watchdog_pid" 2>/dev/null || true
	pkill -9 -P "$main_pid" 2>/dev/null || true
	rm -rf "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

waited=0
while ! mkdir "$lock_dir" 2>/dev/null; do
	holder="$(cat "$lock_dir/pid" 2>/dev/null || true)"
	if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
		# Lock holder is dead — reclaim a stale lock.
		rm -rf "$lock_dir" 2>/dev/null || true
		continue
	fi
	if [ "$waited" -ge "$lock_wait_max" ]; then
		echo "suite: timed out after ${lock_wait_max}s waiting for $lock_dir (held by ${holder:-?})" >&2
		exit 2
	fi
	sleep 3
	waited=$((waited + 3))
done
printf '%s\n' "$main_pid" > "$lock_dir/pid"

# Self-terminating watchdog: if the whole run exceeds the deadline it is hung —
# reap headless Godot, release the lock, and kill the run so the queue advances.
(
	sleep "$suite_deadline"
	echo "suite: WATCHDOG fired after ${suite_deadline}s — killing hung run" >&2
	pkill -9 -f "MacOS/Godot.*headless" 2>/dev/null || true
	rm -rf "$lock_dir" 2>/dev/null || true
	kill -9 "$main_pid" 2>/dev/null || true
) &
watchdog_pid=$!

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
