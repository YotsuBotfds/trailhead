#!/usr/bin/env python3
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

GENERATED_ASSETS = {
    "features": [
        "boardwalk_segment.glb",
        "culvert_pipe.glb",
        "log_ramp.glb",
        "stepping_stone.glb",
    ],
    "props": [
        "bottle_cap.glb",
        "carabiner.glb",
        "fire_ring.glb",
        "hiking_boot.glb",
        "kiosk.glb",
        "mile_marker.glb",
        "old_cedar_stump.glb",
        "park_bench.glb",
        "picnic_table.glb",
        "trail_sign.glb",
        "water_bottle.glb",
    ],
    "scatter": [
        "boulder_a.glb",
        "branch_a.glb",
        "cattail.glb",
        "fern_clump.glb",
        "grass_tuft.glb",
        "pinecone.glb",
        "trail_blaze.glb",
    ],
    "terrain": [
        "cedar_hollow_heightmesh.glb",
        "cedar_hollow_surface_id.png",
    ],
    "vehicle": [
        "rc_buggy.glb",
    ],
}

FEATURE_SURFACES = {
    "boardwalk_segment.glb": "wood_plank",
    "culvert_pipe.glb": "packed_dirt",
    "log_ramp.glb": "wood_plank",
    "stepping_stone.glb": "wet_stone",
}

PROP_BUDGETS = {
    "bottle_cap.glb": (0.07, 0.35),
    "carabiner.glb": (0.08, 0.45),
    "fire_ring.glb": (0.40, 1.40),
    "hiking_boot.glb": (0.25, 0.90),
    "kiosk.glb": (0.80, 2.60),
    "mile_marker.glb": (0.35, 1.10),
    "old_cedar_stump.glb": (0.60, 2.20),
    "park_bench.glb": (0.70, 2.20),
    "picnic_table.glb": (0.80, 2.40),
    "trail_sign.glb": (0.50, 1.60),
    "water_bottle.glb": (0.25, 0.90),
}

SCATTER_BUDGETS = {
    "boulder_a.glb": (0.20, 1.20),
    "branch_a.glb": (0.30, 1.40),
    "cattail.glb": (0.30, 1.00),
    "fern_clump.glb": (0.15, 0.80),
    "grass_tuft.glb": (0.20, 0.80),
    "pinecone.glb": (0.08, 0.35),
    "trail_blaze.glb": (0.25, 0.90),
}


def run(command):
    subprocess.run(command, cwd=ROOT, check=True)


def check_glb(path, *args):
    run([sys.executable, "tools/check_glb.py", path, *args])


def check_heightmesh_if_present():
    path = ROOT / "assets/models/terrain/cedar_hollow_heightmesh.glb"
    surface_id_map = "assets/models/terrain/cedar_hollow_surface_id.png"
    if path.is_file():
        check_glb(
            "assets/models/terrain/cedar_hollow_heightmesh.glb",
            "--profile",
            "heightmesh",
            "--surface-id-map",
            surface_id_map,
            "--max-triangles=200000",
        )
    else:
        print("skip: cedar_hollow_heightmesh.glb pending")


def check_assets():
    check_heightmesh_if_present()
    run([sys.executable, "tools/check_godot_imports.py"])
    check_glb("assets/models/vehicle/rc_buggy.glb", "--profile", "vehicle", "--max-dimension=1.0")
    for filename in GENERATED_ASSETS["features"]:
        check_glb(
            "assets/models/features/" + filename,
            "--require-surface-tag",
            "--surface-id=" + FEATURE_SURFACES[filename],
        )
    for filename in GENERATED_ASSETS["props"]:
        min_dimension, max_dimension = PROP_BUDGETS[filename]
        check_glb(
            "assets/models/props/" + filename,
            "--profile",
            "prop",
            "--min-dimension=" + f"{min_dimension:.2f}",
            "--max-dimension=" + f"{max_dimension:.2f}",
        )
    for filename in GENERATED_ASSETS["scatter"]:
        min_dimension, max_dimension = SCATTER_BUDGETS[filename]
        check_glb(
            "assets/models/scatter/" + filename,
            "--profile",
            "scatter",
            "--min-dimension=" + f"{min_dimension:.2f}",
            "--max-dimension=" + f"{max_dimension:.2f}",
        )
    print("ok: asset GLB contracts passed")


def list_generated(subdir):
    for filename in GENERATED_ASSETS[subdir]:
        print(filename)


def main():
    parser = argparse.ArgumentParser(description="Trailhead asset manifest helper.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check-assets")
    list_parser = subparsers.add_parser("list-generated")
    list_parser.add_argument("subdir", choices=sorted(GENERATED_ASSETS.keys()))
    args = parser.parse_args()
    if args.command == "check-assets":
        check_assets()
        return 0
    if args.command == "list-generated":
        list_generated(args.subdir)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
