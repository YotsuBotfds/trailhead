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
