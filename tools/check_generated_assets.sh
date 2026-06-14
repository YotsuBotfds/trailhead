#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/trailhead-generated-assets.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

printf 'run: generated asset freshness\n'

python3 tools/generate_feature_glbs.py --out-dir "$tmp_dir/features" >/dev/null
python3 tools/generate_prop_glbs.py --out-dir "$tmp_dir/props" >/dev/null
python3 tools/generate_scatter_glbs.py --out-dir "$tmp_dir/scatter" >/dev/null
python3 tools/generate_heightmesh_assets.py --out-dir "$tmp_dir/terrain" >/dev/null
python3 tools/generate_vehicle_glbs.py --out-dir "$tmp_dir/vehicle" >/dev/null

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
	if ! cmp -s "$generated_path" "$committed_path"; then
		printf 'generated asset is stale: %s\n' "$committed_path" >&2
		printf 'regenerate with the matching tools/generate_* script, inspect the diff, then rerun this check.\n' >&2
		exit 1
	fi
	printf 'ok: %s\n' "$committed_path"
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

check_dir features \
	boardwalk_segment.glb \
	culvert_pipe.glb \
	log_ramp.glb \
	stepping_stone.glb

check_dir props \
	fire_ring.glb \
	hiking_boot.glb \
	old_cedar_stump.glb \
	picnic_table.glb \
	trail_sign.glb \
	water_bottle.glb

check_dir scatter \
	boulder_a.glb \
	branch_a.glb \
	cattail.glb \
	fern_clump.glb \
	grass_tuft.glb \
	pinecone.glb \
	trail_blaze.glb

check_dir terrain \
	cedar_hollow_heightmesh.glb \
	cedar_hollow_surface_id.png

check_dir vehicle \
	rc_buggy.glb
