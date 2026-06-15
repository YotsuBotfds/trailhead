#!/usr/bin/env python3
import argparse
import subprocess
import sys
from pathlib import Path

from terrain_def_parser import load_terrain_def

ROOT = Path(__file__).resolve().parents[1]
TERRAIN_DEF = load_terrain_def()
MODEL_ASSET_EXTENSIONS = {".glb", ".png"}
TERRAIN_MODEL_DIR = Path("assets/models/terrain")
FEATURE_MAX_PRIMITIVES = 16
PROP_MAX_PRIMITIVES = 32
SCATTER_MAX_PRIMITIVES = 16
VEHICLE_MAX_PRIMITIVES = 32
TERRAIN_SURFACE_ID_MAP = TERRAIN_DEF.surface_id_map_project_path
TERRAIN_VISUAL_TILE_PATHS = TERRAIN_DEF.visual_tile_project_paths
TERRAIN_SURFACE_ID_WIDTH, TERRAIN_SURFACE_ID_HEIGHT = TERRAIN_DEF.surface_map_size
TERRAIN_SURFACE_ID_VALUES = [1, 2, 3, 4, 5, 6, 7]
TERRAIN_SURFACE_ID_MIN_PIXELS = 16


def unique_values(values):
    unique = []
    for value in values:
        if value not in unique:
            unique.append(value)
    return unique


def terrain_asset_filenames():
    return [
        Path(project_path).name
        for project_path in unique_values([*TERRAIN_VISUAL_TILE_PATHS, TERRAIN_SURFACE_ID_MAP])
    ]


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
    "terrain": terrain_asset_filenames(),
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


def run(command, check=True):
    completed = subprocess.run(command, cwd=ROOT, check=False)
    if check and completed.returncode != 0:
        raise subprocess.CalledProcessError(completed.returncode, command)
    return completed.returncode


def check_glb(path, *args):
    run([sys.executable, "tools/check_glb.py", path, *args])


def check_glb_result(path, *args):
    return run([sys.executable, "tools/check_glb.py", path, *args], check=False) == 0


def surface_id_png_args():
    return [
        "--expected-width=" + str(TERRAIN_SURFACE_ID_WIDTH),
        "--expected-height=" + str(TERRAIN_SURFACE_ID_HEIGHT),
        "--expected-ids=" + ",".join(str(value) for value in TERRAIN_SURFACE_ID_VALUES),
        "--forbid-zero",
        "--require-grayscale",
        "--min-pixels-per-id=" + str(TERRAIN_SURFACE_ID_MIN_PIXELS),
    ]


def check_surface_id_png(path):
    run([sys.executable, "tools/check_surface_id_png.py", path, *surface_id_png_args()])


def check_surface_id_png_result(path):
    return run([sys.executable, "tools/check_surface_id_png.py", path, *surface_id_png_args()], check=False) == 0


def fail(message):
    print("fail: " + message)
    return False


def check_manifest_internal_consistency():
    ok = True
    ok = check_terrain_manifest_consistency() and ok
    for filename in GENERATED_ASSETS["features"]:
        if filename not in FEATURE_SURFACES:
            ok = fail("feature asset missing surface tag in manifest: " + filename) and ok
    for filename in FEATURE_SURFACES:
        if filename not in GENERATED_ASSETS["features"]:
            ok = fail("surface tag defined for non-feature asset: " + filename) and ok
    for filename in GENERATED_ASSETS["props"]:
        if filename not in PROP_BUDGETS:
            ok = fail("prop asset missing scale budget in manifest: " + filename) and ok
    for filename in PROP_BUDGETS:
        if filename not in GENERATED_ASSETS["props"]:
            ok = fail("scale budget defined for non-prop asset: " + filename) and ok
    for filename in GENERATED_ASSETS["scatter"]:
        if filename not in SCATTER_BUDGETS:
            ok = fail("scatter asset missing scale budget in manifest: " + filename) and ok
    for filename in SCATTER_BUDGETS:
        if filename not in GENERATED_ASSETS["scatter"]:
            ok = fail("scale budget defined for non-scatter asset: " + filename) and ok
    return ok


def check_terrain_manifest_consistency():
    ok = True
    active_tile_count = len(TERRAIN_DEF.active_tile_indices())
    if len(TERRAIN_VISUAL_TILE_PATHS) != active_tile_count:
        ok = fail(
            "TerrainDef visual_tile_paths count "
            + str(len(TERRAIN_VISUAL_TILE_PATHS))
            + " must match active tile count "
            + str(active_tile_count)
        ) and ok
    if not TERRAIN_VISUAL_TILE_PATHS:
        ok = fail("TerrainDef visual_tile_paths is empty") and ok
    observed_filenames = []
    for project_path in TERRAIN_VISUAL_TILE_PATHS:
        ok = check_terrain_project_path(project_path, ".glb", "visual tile") and ok
        observed_filenames.append(Path(project_path).name)
    ok = check_terrain_project_path(TERRAIN_SURFACE_ID_MAP, ".png", "surface-ID map") and ok
    observed_filenames.append(Path(TERRAIN_SURFACE_ID_MAP).name)
    if len(observed_filenames) != len(set(observed_filenames)):
        ok = fail("TerrainDef terrain asset paths must have unique filenames") and ok
    return ok


def check_terrain_project_path(project_path, expected_suffix, label):
    ok = True
    if not project_path:
        return fail("TerrainDef " + label + " path is empty")
    relative_path = Path(project_path)
    if relative_path.is_absolute():
        ok = fail("TerrainDef " + label + " path must be project-relative: " + project_path) and ok
    if relative_path.suffix != expected_suffix:
        ok = fail(
            "TerrainDef "
            + label
            + " path must end with "
            + expected_suffix
            + ": "
            + project_path
        ) and ok
    if relative_path.parent != TERRAIN_MODEL_DIR:
        ok = fail(
            "TerrainDef "
            + label
            + " path must live in "
            + TERRAIN_MODEL_DIR.as_posix()
            + ": "
            + project_path
        ) and ok
    return ok


def check_manifest_coverage():
    ok = check_manifest_internal_consistency()
    models_dir = ROOT / "assets/models"
    if not models_dir.is_dir():
        return fail("missing assets/models directory") and ok
    observed_subdirs = sorted(
        path.name
        for path in models_dir.iterdir()
        if path.is_dir() and any(child.suffix in MODEL_ASSET_EXTENSIONS for child in path.iterdir())
    )
    for subdir in observed_subdirs:
        if subdir not in GENERATED_ASSETS:
            ok = fail("assets/models contains unmanifested asset directory: " + subdir) and ok
    for subdir, expected_filenames in GENERATED_ASSETS.items():
        asset_dir = models_dir / subdir
        if not asset_dir.is_dir():
            ok = fail("missing asset directory: assets/models/" + subdir) and ok
            continue
        observed_filenames = sorted(
            path.name
            for path in asset_dir.iterdir()
            if path.is_file() and path.suffix in MODEL_ASSET_EXTENSIONS
        )
        expected_sorted = sorted(unique_values(expected_filenames))
        for filename in expected_sorted:
            if filename not in observed_filenames:
                ok = fail("manifested asset is missing: assets/models/" + subdir + "/" + filename) and ok
        for filename in observed_filenames:
            if filename not in expected_sorted:
                ok = fail("committed asset is not in manifest: assets/models/" + subdir + "/" + filename) and ok
    return ok


def check_visual_tiles():
    for project_path in TERRAIN_VISUAL_TILE_PATHS:
        check_glb(
            project_path,
            "--profile",
            "heightmesh",
            "--surface-id-map",
            TERRAIN_SURFACE_ID_MAP,
            "--max-triangles=200000",
        )


def check_assets():
    if not check_manifest_coverage():
        return 1
    check_surface_id_png(TERRAIN_SURFACE_ID_MAP)
    check_visual_tiles()
    run([sys.executable, "tools/check_godot_imports.py"])
    check_glb(
        "assets/models/vehicle/rc_buggy.glb",
        "--profile",
        "vehicle",
        "--require-render-attributes",
        "--max-dimension=1.0",
        "--max-primitives=" + str(VEHICLE_MAX_PRIMITIVES),
    )
    for filename in GENERATED_ASSETS["features"]:
        check_glb(
            "assets/models/features/" + filename,
            "--require-surface-tag",
            "--require-render-attributes",
            "--require-grounded-origin",
            "--surface-id=" + FEATURE_SURFACES[filename],
            "--max-primitives=" + str(FEATURE_MAX_PRIMITIVES),
        )
    for filename in GENERATED_ASSETS["props"]:
        min_dimension, max_dimension = PROP_BUDGETS[filename]
        check_glb(
            "assets/models/props/" + filename,
            "--profile",
            "prop",
            "--require-render-attributes",
            "--require-grounded-origin",
            "--min-dimension=" + f"{min_dimension:.2f}",
            "--max-dimension=" + f"{max_dimension:.2f}",
            "--max-primitives=" + str(PROP_MAX_PRIMITIVES),
        )
    for filename in GENERATED_ASSETS["scatter"]:
        min_dimension, max_dimension = SCATTER_BUDGETS[filename]
        check_glb(
            "assets/models/scatter/" + filename,
            "--profile",
            "scatter",
            "--require-render-attributes",
            "--require-grounded-origin",
            "--min-dimension=" + f"{min_dimension:.2f}",
            "--max-dimension=" + f"{max_dimension:.2f}",
            "--max-primitives=" + str(SCATTER_MAX_PRIMITIVES),
        )
    print("ok: asset GLB contracts passed")
    return 0


def check_candidate(subdir, filename, candidate_path, surface_id_map):
    if subdir not in GENERATED_ASSETS:
        fail("unknown asset manifest subdir: " + subdir)
        return 1
    if filename not in GENERATED_ASSETS[subdir]:
        fail("target asset is not in manifest: assets/models/" + subdir + "/" + filename)
        return 1
    candidate = Path(candidate_path)
    if not candidate.is_file():
        fail("candidate asset does not exist: " + str(candidate))
        return 1
    target_path = "assets/models/" + subdir + "/" + filename
    target_stem = Path(filename).stem
    if subdir == "features":
        ok = check_glb_result(
            str(candidate),
            "--require-surface-tag",
            "--require-render-attributes",
            "--require-grounded-origin",
            "--surface-id=" + FEATURE_SURFACES[filename],
            "--max-primitives=" + str(FEATURE_MAX_PRIMITIVES),
        )
    elif subdir == "props":
        min_dimension, max_dimension = PROP_BUDGETS[filename]
        ok = check_glb_result(
            str(candidate),
            "--profile",
            "prop",
            "--require-render-attributes",
            "--require-grounded-origin",
            "--expected-name",
            target_stem,
            "--min-dimension=" + f"{min_dimension:.2f}",
            "--max-dimension=" + f"{max_dimension:.2f}",
            "--max-primitives=" + str(PROP_MAX_PRIMITIVES),
        )
    elif subdir == "scatter":
        min_dimension, max_dimension = SCATTER_BUDGETS[filename]
        ok = check_glb_result(
            str(candidate),
            "--profile",
            "scatter",
            "--require-render-attributes",
            "--require-grounded-origin",
            "--expected-name",
            target_stem,
            "--min-dimension=" + f"{min_dimension:.2f}",
            "--max-dimension=" + f"{max_dimension:.2f}",
            "--max-primitives=" + str(SCATTER_MAX_PRIMITIVES),
        )
    elif subdir == "vehicle":
        ok = check_glb_result(
            str(candidate),
            "--profile",
            "vehicle",
            "--require-render-attributes",
            "--max-dimension=1.0",
            "--max-primitives=" + str(VEHICLE_MAX_PRIMITIVES),
        )
    elif subdir == "terrain" and filename.endswith(".glb"):
        if surface_id_map is None:
            fail("terrain GLB candidate requires --surface-id-map")
            return 1
        surface_ok = check_surface_id_png_result(surface_id_map)
        ok = check_glb_result(
            str(candidate),
            "--profile",
            "heightmesh",
            "--surface-id-map",
            surface_id_map,
            "--max-triangles=200000",
        ) and surface_ok
    elif subdir == "terrain" and filename.endswith(".png"):
        ok = check_surface_id_png_result(str(candidate))
    else:
        fail("candidate checks do not support target: " + target_path)
        return 1
    if not ok:
        fail("candidate does not satisfy manifest contract for " + target_path)
        return 1
    print("ok: candidate satisfies manifest contract for " + target_path)
    return 0


def list_generated(subdir):
    for filename in GENERATED_ASSETS[subdir]:
        print(filename)


def main():
    parser = argparse.ArgumentParser(description="Trailhead asset manifest helper.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check-assets")
    candidate_parser = subparsers.add_parser("check-candidate")
    candidate_parser.add_argument("subdir", choices=sorted(GENERATED_ASSETS.keys()))
    candidate_parser.add_argument("filename")
    candidate_parser.add_argument("candidate_path")
    candidate_parser.add_argument("--surface-id-map")
    list_parser = subparsers.add_parser("list-generated")
    list_parser.add_argument("subdir", choices=sorted(GENERATED_ASSETS.keys()))
    args = parser.parse_args()
    if args.command == "check-assets":
        return check_assets()
    if args.command == "check-candidate":
        return check_candidate(args.subdir, args.filename, args.candidate_path, args.surface_id_map)
    if args.command == "list-generated":
        list_generated(args.subdir)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
