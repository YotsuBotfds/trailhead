#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
pin_file="$root/tools/godot_binary_sha.txt"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

if [ ! -f "$pin_file" ]; then
	printf 'fail: missing Godot binary SHA pin: %s\n' "$pin_file" >&2
	exit 1
fi

expected_sha="$(sed -n '1p' "$pin_file" | tr -d '[:space:]')"
if ! printf '%s\n' "$expected_sha" | rg -q '^[0-9a-f]{64}$'; then
	printf 'fail: Godot binary SHA pin must be one lowercase SHA-256: %s\n' "$pin_file" >&2
	exit 1
fi

if [ ! -x "$godot_bin" ]; then
	printf 'fail: Godot binary is missing or not executable: %s\n' "$godot_bin" >&2
	exit 1
fi

actual_sha="$(shasum -a 256 "$godot_bin" | awk '{print $1}')"
if [ "$actual_sha" != "$expected_sha" ]; then
	printf 'fail: Godot binary SHA mismatch for %s\n' "$godot_bin" >&2
	printf 'expected: %s\n' "$expected_sha" >&2
	printf 'actual:   %s\n' "$actual_sha" >&2
	printf 'Update tools/godot_binary_sha.txt only when the Godot binary is deliberately upgraded and golden data has been revalidated.\n' >&2
	exit 1
fi

printf 'ok: Godot binary SHA %s\n' "$actual_sha"
