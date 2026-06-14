#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/trailhead-generated-assets.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

printf 'run: generated asset freshness\n'

if ! pillow_error="$(python3 - <<'PY' 2>&1
try:
    import PIL  # noqa: F401
except ImportError as exc:
    raise SystemExit(f"ImportError: {exc}")
PY
)"; then
	printf 'error: Pillow is required for generated asset checks but could not be imported.\n' >&2
	printf 'Install dependencies with: python3 -m pip install -r requirements.txt\n' >&2
	printf '%s\n' "$pillow_error" >&2
	exit 1
fi

python3 tools/generate_feature_glbs.py --out-dir "$tmp_dir/features" >/dev/null
python3 tools/generate_prop_glbs.py --out-dir "$tmp_dir/props" >/dev/null
python3 tools/generate_scatter_glbs.py --out-dir "$tmp_dir/scatter" >/dev/null
python3 tools/generate_heightmesh_assets.py --out-dir "$tmp_dir/terrain" >/dev/null
python3 tools/generate_vehicle_glbs.py --out-dir "$tmp_dir/vehicle" >/dev/null
python3 tools/generate_vehicle_residue_textures.py --out-dir "$tmp_dir/vehicle_residue" >/dev/null

check_file() {
	generated_path="$1"
	committed_path="$2"
	if [ ! -f "$generated_path" ]; then
		printf 'missing generated asset: %s\n' "$generated_path" >&2
		exit 1
	fi
	if [ ! -f "$committed_path" ]; then
		printf 'missing committed asset: %s\n' "$committed_path" >&2
		exit 1
	fi
	if ! generated_file_matches "$generated_path" "$committed_path"; then
		printf 'generated asset is stale: %s\n' "$committed_path" >&2
		printf 'regenerate with the matching tools/generate_* script, inspect the diff, then rerun this check.\n' >&2
		exit 1
	fi
	printf 'ok: %s\n' "$committed_path"
}

generated_file_matches() {
	generated_path="$1"
	committed_path="$2"
	case "$committed_path" in
		*.png)
			python3 - "$generated_path" "$committed_path" <<'PY'
from pathlib import Path
import sys

from PIL import Image, ImageChops

generated_path = Path(sys.argv[1])
committed_path = Path(sys.argv[2])
generated_image = Image.open(generated_path).convert("RGBA")
committed_image = Image.open(committed_path).convert("RGBA")
if generated_image.size != committed_image.size:
    raise SystemExit(1)
difference = ImageChops.difference(generated_image, committed_image)
raise SystemExit(0 if difference.getbbox() is None else 1)
PY
			;;
		*)
			cmp -s "$generated_path" "$committed_path"
			;;
	esac
}

check_dir() {
	subdir="$1"
	shift
	generated_dir="$tmp_dir/$subdir"
	committed_dir="assets/models/$subdir"
	expected_count="$#"
	generated_count="$(find "$generated_dir" -type f | wc -l | tr -d ' ')"
	if [ "$generated_count" -ne "$expected_count" ]; then
		printf 'generated asset count mismatch for %s: expected %s, got %s\n' "$subdir" "$expected_count" "$generated_count" >&2
		find "$generated_dir" -type f -print >&2
		exit 1
	fi
	for filename in "$@"; do
		check_file "$generated_dir/$filename" "$committed_dir/$filename"
	done
}

check_manifest_dir() {
	subdir="$1"
	shift
	set -- $(python3 tools/asset_manifest.py list-generated "$subdir")
	check_dir "$subdir" "$@"
}

check_manifest_dir features
check_manifest_dir props
check_manifest_dir scatter
check_manifest_dir terrain
check_manifest_dir vehicle
check_file "$tmp_dir/vehicle_residue/SOURCES.md" "assets/textures/vehicle/residue/SOURCES.md"
check_file "$tmp_dir/vehicle_residue/mud_body_mask.png" "assets/textures/vehicle/residue/mud_body_mask.png"
check_file "$tmp_dir/vehicle_residue/dust_body_mask.png" "assets/textures/vehicle/residue/dust_body_mask.png"
check_file "$tmp_dir/vehicle_residue/wetness_body_mask.png" "assets/textures/vehicle/residue/wetness_body_mask.png"
check_file "$tmp_dir/vehicle_residue/mud_tire_mask.png" "assets/textures/vehicle/residue/mud_tire_mask.png"
check_file "$tmp_dir/vehicle_residue/dust_tire_mask.png" "assets/textures/vehicle/residue/dust_tire_mask.png"
check_file "$tmp_dir/vehicle_residue/wetness_tire_mask.png" "assets/textures/vehicle/residue/wetness_tire_mask.png"
