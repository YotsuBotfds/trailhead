#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

check_feature() {
	path="$1"
	surface_id="$2"
	./tools/check_glb.py "$path" --require-surface-tag --surface-id="$surface_id"
}

check_decoration() {
	path="$1"
	./tools/check_glb.py "$path"
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
check_vehicle assets/models/vehicle/rc_buggy.glb

check_feature assets/models/features/boardwalk_segment.glb wood_plank
check_feature assets/models/features/culvert_pipe.glb packed_dirt
check_feature assets/models/features/log_ramp.glb wood_plank
check_feature assets/models/features/stepping_stone.glb wet_stone

for path in assets/models/props/*.glb; do
	check_decoration "$path"
done

for path in assets/models/scatter/*.glb; do
	check_decoration "$path"
done

printf 'ok: asset GLB contracts passed\n'
