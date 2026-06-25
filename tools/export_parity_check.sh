#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
preset="${EXPORT_PRESET:-Windows Desktop}"
build_dir="$root/build/parity"
pck_path="$build_dir/trailhead.pck"
result_path="$build_dir/export_parity_smoke.json"
isolated_dir="${TMPDIR:-/tmp}/trailhead-export-parity-$$"

cleanup() {
	rm -rf "$isolated_dir"
}
trap cleanup EXIT INT TERM

fail() {
	printf 'export-parity: fail: %s\n' "$1" >&2
	exit 1
}

assert_no_godot() {
	running="$(pgrep -fl Godot 2>/dev/null | grep -v -E 'codex|computer-use|grep|pgrep' || true)"
	if [ -n "$running" ]; then
		printf 'export-parity: another Godot process is running; refusing to start a second headless/export process:\n%s\n' "$running" >&2
		exit 2
	fi
}

if [ ! -x "$godot_bin" ]; then
	fail "Godot binary is missing or not executable: $godot_bin"
fi

mkdir -p "$build_dir"
rm -f "$pck_path" "$result_path"

printf 'export-parity: exporting pack with real Windows preset strip rules\n'
printf 'export-parity: %s --headless --path . --export-pack "%s" %s\n' "$godot_bin" "$preset" "$pck_path"
assert_no_godot
"$godot_bin" --headless --path . --export-pack "$preset" "$pck_path"

if [ ! -s "$pck_path" ]; then
	fail "export did not create a non-empty pack: $pck_path"
fi

mkdir -p "$isolated_dir"
printf 'export-parity: running smoke from isolated empty dir so res:// cannot shadow to the raw checkout\n'
printf 'export-parity: (cd %s && %s --headless --main-pack %s res://tools/export_parity_smoke.tscn -- --out=%s)\n' "$isolated_dir" "$godot_bin" "$pck_path" "$result_path"
assert_no_godot
set +e
(
	cd "$isolated_dir"
	"$godot_bin" --headless --main-pack "$pck_path" res://tools/export_parity_smoke.tscn -- --out="$result_path"
)
smoke_rc=$?
set -e

if [ "$smoke_rc" -ne 0 ]; then
	if [ -f "$result_path" ]; then
		printf 'export-parity: smoke result:\n'
		sed -n '1,220p' "$result_path"
	fi
	fail "packed smoke scene exited with $smoke_rc"
fi

if [ ! -f "$result_path" ]; then
	fail "packed smoke scene did not write result: $result_path"
fi

if ! grep -q '"ok"[[:space:]]*:[[:space:]]*true' "$result_path"; then
	printf 'export-parity: smoke result:\n'
	sed -n '1,220p' "$result_path"
	fail "packed smoke scene reported failure"
fi

printf 'export-parity: PASS %s\n' "$result_path"
