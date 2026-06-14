#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

check_feature() {
	path="$1"
	surface_id="$2"
	./tools/check_glb.py "$path" --require-surface-tag --surface-id="$surface_id"
}

check_prop() {
	path="$1"
	min_dimension="$2"
	max_dimension="$3"
	./tools/check_glb.py "$path" --profile prop --min-dimension="$min_dimension" --max-dimension="$max_dimension"
}

check_scatter() {
	path="$1"
	min_dimension="$2"
	max_dimension="$3"
	./tools/check_glb.py "$path" --profile scatter --min-dimension="$min_dimension" --max-dimension="$max_dimension"
}

check_vehicle() {
	path="$1"
	./tools/check_glb.py "$path" --profile vehicle --max-dimension=1.0
}

check_heightmesh_if_present() {
	path="assets/models/terrain/cedar_hollow_heightmesh.glb"
	surface_id_map="assets/models/terrain/cedar_hollow_surface_id.png"
	if [ -f "$path" ]; then
		./tools/check_glb.py "$path" \
			--profile heightmesh \
			--surface-id-map "$surface_id_map" \
			--max-triangles=200000
	else
		printf 'skip: cedar_hollow_heightmesh.glb pending\n'
	fi
}

check_heightmesh_if_present
./tools/check_godot_imports.py
check_vehicle assets/models/vehicle/rc_buggy.glb

check_feature assets/models/features/boardwalk_segment.glb wood_plank
check_feature assets/models/features/culvert_pipe.glb packed_dirt
check_feature assets/models/features/log_ramp.glb wood_plank
check_feature assets/models/features/stepping_stone.glb wet_stone

check_prop assets/models/props/bottle_cap.glb 0.07 0.35
check_prop assets/models/props/carabiner.glb 0.08 0.45
check_prop assets/models/props/fire_ring.glb 0.40 1.40
check_prop assets/models/props/hiking_boot.glb 0.25 0.90
check_prop assets/models/props/kiosk.glb 0.80 2.60
check_prop assets/models/props/mile_marker.glb 0.35 1.10
check_prop assets/models/props/old_cedar_stump.glb 0.60 2.20
check_prop assets/models/props/park_bench.glb 0.70 2.20
check_prop assets/models/props/picnic_table.glb 0.80 2.40
check_prop assets/models/props/trail_sign.glb 0.50 1.60
check_prop assets/models/props/water_bottle.glb 0.25 0.90

check_scatter assets/models/scatter/boulder_a.glb 0.20 1.20
check_scatter assets/models/scatter/branch_a.glb 0.30 1.40
check_scatter assets/models/scatter/cattail.glb 0.30 1.00
check_scatter assets/models/scatter/fern_clump.glb 0.15 0.80
check_scatter assets/models/scatter/grass_tuft.glb 0.20 0.80
check_scatter assets/models/scatter/pinecone.glb 0.08 0.35
check_scatter assets/models/scatter/trail_blaze.glb 0.25 0.90

printf 'ok: asset GLB contracts passed\n'
