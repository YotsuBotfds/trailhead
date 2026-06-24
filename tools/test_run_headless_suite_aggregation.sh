#!/bin/sh
# Pure-shell self-test for tools/run_headless_suite.sh's suite aggregation.
# Does NOT launch Godot: it writes three fake suites into a temp tree, points the
# runner at them via TRAILHEAD_SUITE_GLOB, and asserts the runner runs all three,
# reports a non-zero exit, and prints SUITE FAILED for the failing one.
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

fail() {
	printf 'test_run_headless_suite_aggregation: FAIL: %s\n' "$*" >&2
	exit 1
}

tmp="$(mktemp -d 2>/dev/null || mktemp -d -t trailhead-suite)"
cleanup() {
	rm -rf "$tmp" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

suites_dir="$tmp/suites"
mkdir -p "$suites_dir" "$tmp/out"

# Fake suite 1: succeeds.
cat >"$suites_dir/01_ok.sh" <<'EOF'
#!/bin/sh
touch "$OUT_DIR/marker_01_ok"
EOF

# Fake suite 2: fails through an ordinary command error. This must NOT stop the
# runner from reaching 03, but commands after the failed assertion-like command
# must not continue inside the failing suite.
cat >"$suites_dir/02_fail.sh" <<'EOF'
#!/bin/sh
touch "$OUT_DIR/marker_02_fail"
false
touch "$OUT_DIR/marker_02_after_false"
EOF

# Fake suite 3: succeeds; proves the runner continued past the failure.
cat >"$suites_dir/03_ok.sh" <<'EOF'
#!/bin/sh
touch "$OUT_DIR/marker_03_ok"
EOF

# Drive the runner against the fake suites. Its own mutex/watchdog still apply;
# we give it a private lock + a short deadline so a bug can't hang the test.
# Capture merged stdout+stderr (SUITE FAILED is on stderr). set +e around it so
# the non-zero exit we want to assert on doesn't trip our own set -e.
set +e
runner_output="$(
	TRAILHEAD_SUITE_GLOB="$suites_dir/*.sh" \
	TRAILHEAD_SUITE_LOCK="$tmp/lock" \
	OUT_DIR="$tmp/out" \
	SUITE_DEADLINE_SECS=30 \
	SUITE_LOCK_WAIT_MAX=30 \
	"$root/tools/run_headless_suite.sh" 2>&1
)"
runner_rc=$?
set -e

# Assertions.
[ "$runner_rc" -ne 0 ] || fail "runner exited 0 despite a failing suite (rc=$runner_rc)"
[ -f "$tmp/out/marker_01_ok" ] || fail "suite 01 did not run (no marker_01_ok)"
[ -f "$tmp/out/marker_02_fail" ] || fail "suite 02 did not run (no marker_02_fail)"
[ ! -f "$tmp/out/marker_02_after_false" ] || fail "suite 02 continued after a failing command"
[ -f "$tmp/out/marker_03_ok" ] || fail "suite 03 did not run (no marker_03_ok) - runner did not continue past the failure"
case "$runner_output" in
	*SUITE\ FAILED*) : ;;
	*) fail "runner output did not contain 'SUITE FAILED'" ;;
esac

printf 'aggregation self-test passed: 3 suites ran, 1 failure reported, runner exited %s\n' "$runner_rc"
