#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
GAME_CONFIG_PATH = ROOT / "autoload/game_config.gd"
INPUT_MANIFEST_PATH = ROOT / "data/bake_inputs/zion_dem_input_manifest.json"
OUTPUT_MANIFEST_PATH = ROOT / "data/bake_inputs/zion_bake_output_manifest.json"
INPUT_DEM_PATH = ROOT / "data/bake_inputs/zion_dem_10m_corridor.tif"
TERRAIN_DEF_PATH = ROOT / "data/terrain/cedar_hollow_zion_terrain_def.tres"
REGION_BASE_DIR = ROOT / "data/regions"
COLLISION_OUT_DIR = ROOT / "data/collision"
COLLISION_RESOURCE_WRITER = ROOT / "tools/write_heightmap_collision_resources.gd"
EXPECTED_NUMPY_VERSION = "2.4.6"
EXPECTED_RASTERIO_VERSION = "1.4.3"
EXPECTED_CRS = "EPSG:32612"
DEFAULT_REGION_ID = "cedar_hollow_zion"
DEFAULT_GODOT_BIN = "/Applications/Godot.app/Contents/MacOS/Godot"
CELL_SPACING_M = 1.0
COLLISION_GRID_SAMPLES = 101
EROSION_ALPHA = 0.05
EROSION_SEED = 20260615
EROSION_WORK_GRID_MAX = 1024
EROSION_WORK_GRID_MIN = 256


@dataclass(frozen=True)
class ZionBakeConfig:
    region_id: str
    origin_easting: float
    origin_northing: float
    max_easting: float
    max_northing: float
    tile_cols: int
    tile_rows: int
    tile_size_m: float

    @property
    def width_m(self) -> float:
        return self.max_easting - self.origin_easting

    @property
    def height_m(self) -> float:
        return self.max_northing - self.origin_northing

    @property
    def tile_width_m(self) -> float:
        return float(self.tile_cols) * self.tile_size_m

    @property
    def tile_height_m(self) -> float:
        return float(self.tile_rows) * self.tile_size_m

    @property
    def tile_max_easting(self) -> float:
        return self.origin_easting + self.tile_width_m

    @property
    def tile_max_northing(self) -> float:
        return self.origin_northing + self.tile_height_m

    @property
    def grid_width_samples(self) -> int:
        return int(round(self.tile_width_m / CELL_SPACING_M)) + 1

    @property
    def grid_height_samples(self) -> int:
        return int(round(self.tile_height_m / CELL_SPACING_M)) + 1

    @property
    def tile_bounds(self) -> tuple[float, float, float, float]:
        return (
            self.origin_easting,
            self.origin_northing,
            self.tile_max_easting,
            self.tile_max_northing,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bake the Cedar Hollow Zion-inspired terrain corridor.")
    parser.add_argument("--source", choices=("10m", "1m"), default="10m", help="DEM source tier to bake.")
    parser.add_argument("--region-id", default=DEFAULT_REGION_ID, help="Output region id under data/regions/.")
    parser.add_argument("--dry-run", action="store_true", help="Validate inputs/configuration without writing artifacts.")
    parser.add_argument(
        "--godot-bin",
        default=os.environ.get("GODOT_BIN", DEFAULT_GODOT_BIN),
        help="Godot executable used to derive binary HeightMapShape3D .res tiles.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        _assert_python_deps()
        config = _load_bake_config(args.region_id)
    except Exception as exc:
        print("fail: " + str(exc), file=sys.stderr)
        return 1

    if args.dry_run:
        print("ok: zion bake dry-run")
        print("source: " + args.source)
        print("crs: " + EXPECTED_CRS)
        print("region: " + config.region_id)
        print(
            "utm_bounds: "
            + f"{config.origin_easting:.6f},{config.origin_northing:.6f} -> "
            + f"{config.max_easting:.6f},{config.max_northing:.6f}"
        )
        print("tile_grid: " + str(config.tile_cols) + "x" + str(config.tile_rows))
        print("extent_m: " + f"{config.width_m:.3f}x{config.height_m:.3f}")
        print("padded_tile_extent_m: " + f"{config.tile_width_m:.3f}x{config.tile_height_m:.3f}")
        return 0

    try:
        if args.source != "10m":
            raise ValueError("1m source is gated to Z3-B; run Z2-B with --source 10m")
        result = _bake_10m(config, args.godot_bin)
    except Exception as exc:
        print("fail: " + str(exc), file=sys.stderr)
        return 1

    print("ok: zion 10m bake")
    print("region: " + config.region_id)
    print("tile_grid: " + str(config.tile_cols) + "x" + str(config.tile_rows))
    print("heightmap_tiles: " + str(result["tile_count"]))
    print("edge_fill_samples: " + str(result["edge_fill_samples"]))
    print("manifest: " + str(OUTPUT_MANIFEST_PATH.relative_to(ROOT)))
    return 0


def _assert_python_deps() -> None:
    import numpy as np
    import rasterio

    if np.__version__ != EXPECTED_NUMPY_VERSION:
        raise RuntimeError("numpy " + np.__version__ + " != " + EXPECTED_NUMPY_VERSION)
    if rasterio.__version__ != EXPECTED_RASTERIO_VERSION:
        raise RuntimeError("rasterio " + rasterio.__version__ + " != " + EXPECTED_RASTERIO_VERSION)


def _load_bake_config(region_id: str) -> ZionBakeConfig:
    text = GAME_CONFIG_PATH.read_text(encoding="utf-8")
    return ZionBakeConfig(
        region_id=region_id,
        origin_easting=_const_float(text, "ZION_CORRIDOR_UTM_ORIGIN_E"),
        origin_northing=_const_float(text, "ZION_CORRIDOR_UTM_ORIGIN_N"),
        max_easting=_const_float(text, "ZION_CORRIDOR_UTM_MAX_E"),
        max_northing=_const_float(text, "ZION_CORRIDOR_UTM_MAX_N"),
        tile_cols=_const_int(text, "ZION_CORRIDOR_TILE_COLS"),
        tile_rows=_const_int(text, "ZION_CORRIDOR_TILE_ROWS"),
        tile_size_m=_const_float(text, "STREAM_TILE_SIZE_M"),
    )


def _bake_10m(config: ZionBakeConfig, godot_bin: str) -> dict[str, Any]:
    import numpy as np

    input_manifest = _load_json(INPUT_MANIFEST_PATH)
    _verify_input_manifest(input_manifest)
    dem, edge_fill_samples = _load_reprojected_dem(config)
    detail = _build_erosion_detail(config, dem.shape[1], dem.shape[0])
    composited = (dem + detail * EROSION_ALPHA).astype(np.float32)
    _assert_tile_seams(composited, config)

    region_dir = REGION_BASE_DIR / config.region_id
    _clear_previous_outputs(region_dir)
    region_dir.mkdir(parents=True, exist_ok=True)
    COLLISION_OUT_DIR.mkdir(parents=True, exist_ok=True)

    tile_entries = _write_heightmap_tiles(composited, config, region_dir)
    collision_project_paths = [entry["collision_path"] for entry in tile_entries]
    _write_terrain_def(config, collision_project_paths)
    _write_collision_resources(tile_entries, godot_bin)

    files = _collect_output_files(tile_entries)
    files.append(_artifact_entry(TERRAIN_DEF_PATH, "terrain_def"))
    output_manifest = {
        "schema_version": 1,
        "source": "10m",
        "region_id": config.region_id,
        "crs": EXPECTED_CRS,
        "tile_grid": [config.tile_cols, config.tile_rows],
        "tile_size_m": config.tile_size_m,
        "cell_spacing_m": CELL_SPACING_M,
        "collision_grid": [COLLISION_GRID_SAMPLES, COLLISION_GRID_SAMPLES],
        "source_bounds_utm": [
            config.origin_easting,
            config.origin_northing,
            config.max_easting,
            config.max_northing,
        ],
        "padded_tile_bounds_utm": [
            config.origin_easting,
            config.origin_northing,
            config.tile_max_easting,
            config.tile_max_northing,
        ],
        "input_manifest_sha256": _sha256(INPUT_MANIFEST_PATH),
        "input_dem_sha256": _sha256(INPUT_DEM_PATH),
        "edge_fill_samples": edge_fill_samples,
        "erosion": {
            "alpha": EROSION_ALPHA,
            "seed": EROSION_SEED,
            "work_grid_max": EROSION_WORK_GRID_MAX,
            "work_grid_min": EROSION_WORK_GRID_MIN,
            "strategy": "single corridor work grid resampled before tile slicing",
        },
        "files": sorted(files, key=lambda item: str(item["path"])),
    }
    OUTPUT_MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    _write_json(OUTPUT_MANIFEST_PATH, output_manifest)
    return {"tile_count": len(tile_entries), "edge_fill_samples": edge_fill_samples}


def _verify_input_manifest(input_manifest: dict[str, Any]) -> None:
    clip = input_manifest.get("clip", {})
    if not isinstance(clip, dict):
        raise ValueError("input manifest clip must be an object")
    clip_path = ROOT / str(clip.get("path", ""))
    if clip_path != INPUT_DEM_PATH:
        raise ValueError("input manifest clip path must be " + str(INPUT_DEM_PATH.relative_to(ROOT)))
    expected_sha = str(clip.get("sha256", ""))
    actual_sha = _sha256(INPUT_DEM_PATH)
    if actual_sha != expected_sha:
        raise ValueError("input DEM sha256 mismatch: " + actual_sha + " != " + expected_sha)


def _load_reprojected_dem(config: ZionBakeConfig):
    import numpy as np
    import rasterio
    from rasterio.transform import from_origin
    from rasterio.warp import Resampling, reproject

    if not INPUT_DEM_PATH.exists():
        raise FileNotFoundError("missing input DEM: " + str(INPUT_DEM_PATH.relative_to(ROOT)))
    width = config.grid_width_samples
    height = config.grid_height_samples
    destination = np.full((height, width), np.nan, dtype=np.float32)
    transform = from_origin(
        config.origin_easting,
        config.tile_max_northing,
        CELL_SPACING_M,
        CELL_SPACING_M,
    )
    with rasterio.open(INPUT_DEM_PATH) as src:
        reproject(
            source=rasterio.band(src, 1),
            destination=destination,
            src_transform=src.transform,
            src_crs=src.crs,
            src_nodata=src.nodata,
            dst_transform=transform,
            dst_crs=EXPECTED_CRS,
            dst_nodata=np.nan,
            resampling=Resampling.bilinear,
            num_threads=2,
        )
    z_increasing = np.flipud(destination).astype(np.float32, copy=False)
    edge_fill_samples = _fill_missing_edge_samples(z_increasing)
    if not np.isfinite(z_increasing).all():
        raise ValueError("reprojected DEM still contains nodata after deterministic edge fill")
    return z_increasing, edge_fill_samples


def _fill_missing_edge_samples(heightfield) -> int:
    import numpy as np

    missing = ~np.isfinite(heightfield)
    missing_count = int(missing.sum())
    if missing_count == 0:
        return 0
    if not _missing_mask_is_edge_connected(missing):
        raise ValueError("reprojected DEM contains internal nodata; refusing edge-fill policy")
    for row in range(heightfield.shape[0]):
        finite_cols = np.flatnonzero(np.isfinite(heightfield[row]))
        if finite_cols.size == 0:
            continue
        first = int(finite_cols[0])
        last = int(finite_cols[-1])
        if first > 0:
            heightfield[row, :first] = heightfield[row, first]
        if last < heightfield.shape[1] - 1:
            heightfield[row, last + 1 :] = heightfield[row, last]
    for col in range(heightfield.shape[1]):
        finite_rows = np.flatnonzero(np.isfinite(heightfield[:, col]))
        if finite_rows.size == 0:
            continue
        first = int(finite_rows[0])
        last = int(finite_rows[-1])
        if first > 0:
            heightfield[:first, col] = heightfield[first, col]
        if last < heightfield.shape[0] - 1:
            heightfield[last + 1 :, col] = heightfield[last, col]
    return missing_count


def _missing_mask_is_edge_connected(missing) -> bool:
    height, width = missing.shape
    visited: set[tuple[int, int]] = set()
    queue: deque[tuple[int, int]] = deque()
    for col in range(width):
        if bool(missing[0, col]):
            queue.append((0, col))
        if bool(missing[height - 1, col]):
            queue.append((height - 1, col))
    for row in range(height):
        if bool(missing[row, 0]):
            queue.append((row, 0))
        if bool(missing[row, width - 1]):
            queue.append((row, width - 1))
    while queue:
        row, col = queue.popleft()
        if row < 0 or row >= height or col < 0 or col >= width:
            continue
        key = (row, col)
        if key in visited or not bool(missing[row, col]):
            continue
        visited.add(key)
        queue.append((row - 1, col))
        queue.append((row + 1, col))
        queue.append((row, col - 1))
        queue.append((row, col + 1))
    return len(visited) == int(missing.sum())


def _build_erosion_detail(config: ZionBakeConfig, target_width: int, target_height: int):
    import numpy as np

    sys.path.insert(0, str((ROOT / "tools").resolve()))
    from erosion import ErosionConfig, build_eroded_heightfield, resample_heightfield

    work_width, work_height = _erosion_work_grid(target_width, target_height)
    bounds = (
        (config.origin_easting, config.origin_northing),
        (config.tile_max_easting, config.tile_max_northing),
    )
    work = build_eroded_heightfield(
        work_width,
        work_height,
        bounds,
        seed=EROSION_SEED,
        config=ErosionConfig(),
    )
    work = work.astype(np.float32, copy=False)
    work -= np.float32(np.mean(work, dtype=np.float64))
    return resample_heightfield(work, bounds, target_width, target_height).astype(np.float32)


def _erosion_work_grid(target_width: int, target_height: int) -> tuple[int, int]:
    if target_width >= target_height:
        width = EROSION_WORK_GRID_MAX
        height = int(round(float(width) * float(target_height) / float(target_width)))
    else:
        height = EROSION_WORK_GRID_MAX
        width = int(round(float(height) * float(target_width) / float(target_height)))
    return max(EROSION_WORK_GRID_MIN, width), max(EROSION_WORK_GRID_MIN, height)


def _assert_tile_seams(composited, config: ZionBakeConfig) -> None:
    import numpy as np

    stride = COLLISION_GRID_SAMPLES - 1
    for row in range(config.tile_rows):
        row_start = row * stride
        row_end = row_start + COLLISION_GRID_SAMPLES
        for col in range(config.tile_cols - 1):
            col_start = col * stride
            next_col_start = (col + 1) * stride
            left_tile = composited[row_start:row_end, col_start : col_start + COLLISION_GRID_SAMPLES]
            right_tile = composited[row_start:row_end, next_col_start : next_col_start + COLLISION_GRID_SAMPLES]
            left_edge = left_tile[:, -1]
            right_edge = right_tile[:, 0]
            if not np.array_equal(left_edge, right_edge):
                raise ValueError("horizontal seam mismatch at col " + str(col) + ", row " + str(row))
    for row in range(config.tile_rows - 1):
        row_start = row * stride
        next_row_start = (row + 1) * stride
        for col in range(config.tile_cols):
            col_start = col * stride
            col_end = col_start + COLLISION_GRID_SAMPLES
            lower_tile = composited[row_start : row_start + COLLISION_GRID_SAMPLES, col_start:col_end]
            upper_tile = composited[next_row_start : next_row_start + COLLISION_GRID_SAMPLES, col_start:col_end]
            lower_edge = lower_tile[-1, :]
            upper_edge = upper_tile[0, :]
            if not np.array_equal(lower_edge, upper_edge):
                raise ValueError("vertical seam mismatch at col " + str(col) + ", row " + str(row))


def _clear_previous_outputs(region_dir: Path) -> None:
    if region_dir.exists():
        shutil.rmtree(region_dir)
    for path in COLLISION_OUT_DIR.glob("cedar_hollow_zion_tile_CX*_CZ*.res"):
        path.unlink()


def _write_heightmap_tiles(composited, config: ZionBakeConfig, region_dir: Path) -> list[dict[str, Any]]:
    import numpy as np

    tiles_dir = region_dir / "tiles"
    tiles_dir.mkdir(parents=True, exist_ok=True)
    stride = COLLISION_GRID_SAMPLES - 1
    entries: list[dict[str, Any]] = []
    for row in range(config.tile_rows):
        for col in range(config.tile_cols):
            row_start = row * stride
            col_start = col * stride
            tile = composited[
                row_start : row_start + COLLISION_GRID_SAMPLES,
                col_start : col_start + COLLISION_GRID_SAMPLES,
            ]
            tile_dir = tiles_dir / (str(col) + "_" + str(row))
            tile_dir.mkdir(parents=True, exist_ok=True)
            heightmap_path = tile_dir / "heightmap.bin"
            tile_bytes = np.ascontiguousarray(tile, dtype="<f4").tobytes(order="C")
            heightmap_path.write_bytes(tile_bytes)
            heightmap_sha = hashlib.sha256(tile_bytes).hexdigest()
            collision_project_path = _collision_project_path(col, row)
            tile_json_path = tile_dir / "tile.json"
            bounds = _tile_bounds(config, col, row)
            sidecar = {
                "schema_version": 1,
                "region_id": config.region_id,
                "source": "10m",
                "tile": [col, row],
                "crs": EXPECTED_CRS,
                "bounds_utm": list(bounds),
                "cell_spacing_m": CELL_SPACING_M,
                "map_width": COLLISION_GRID_SAMPLES,
                "map_depth": COLLISION_GRID_SAMPLES,
                "dtype": "float32_le",
                "height_min": float(tile.min()),
                "height_max": float(tile.max()),
                "heightmap_sha256": heightmap_sha,
                "heightmap_path": _project_path(heightmap_path),
                "collision_path": collision_project_path,
            }
            _write_json(tile_json_path, sidecar)
            entries.append(
                {
                    "tile": [col, row],
                    "heightmap_path": _project_path(heightmap_path),
                    "tile_json_path": _project_path(tile_json_path),
                    "collision_path": collision_project_path,
                    "heightmap_abs_path": str(heightmap_path),
                    "tile_json_abs_path": str(tile_json_path),
                    "collision_abs_path": str(ROOT / collision_project_path.removeprefix("res://")),
                    "heightmap_sha256": heightmap_sha,
                    "bounds_utm": list(bounds),
                }
            )
    return entries


def _write_collision_resources(tile_entries: list[dict[str, Any]], godot_bin: str) -> None:
    if not COLLISION_RESOURCE_WRITER.exists():
        raise FileNotFoundError("missing collision resource writer: " + str(COLLISION_RESOURCE_WRITER.relative_to(ROOT)))
    if not Path(godot_bin).exists():
        raise FileNotFoundError("missing Godot binary: " + godot_bin)
    manifest = {
        "schema_version": 1,
        "map_width": COLLISION_GRID_SAMPLES,
        "map_depth": COLLISION_GRID_SAMPLES,
        "tiles": [
            {
                "tile": entry["tile"],
                "heightmap_path": entry["heightmap_path"],
                "collision_path": entry["collision_path"],
            }
            for entry in tile_entries
        ],
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json", prefix="trailhead_zion_collision_", delete=False) as handle:
        json.dump(manifest, handle, sort_keys=True)
        manifest_path = Path(handle.name)
    try:
        command = [
            godot_bin,
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            str(COLLISION_RESOURCE_WRITER),
            "--",
            "--manifest",
            str(manifest_path),
        ]
        completed = subprocess.run(command, cwd=ROOT, check=False, text=True, capture_output=True)
        if completed.returncode != 0:
            output = (completed.stdout + completed.stderr).strip()
            raise RuntimeError("Godot collision resource write failed: " + output)
    finally:
        manifest_path.unlink(missing_ok=True)


def _write_terrain_def(config: ZionBakeConfig, collision_project_paths: list[str]) -> None:
    TERRAIN_DEF_PATH.parent.mkdir(parents=True, exist_ok=True)
    collision_paths = ", ".join('"' + path + '"' for path in collision_project_paths)
    text = (
        '[gd_resource type="Resource" script_class="TerrainDef" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://systems/world/terrain_def.gd" id="1_script"]\n\n'
        "[resource]\n"
        'script = ExtResource("1_script")\n'
        'id = &"cedar_hollow_zion"\n'
        'scene_id = &"cedar_hollow_zion"\n'
        "bounds_min_xz = Vector2(" + _format_float(config.origin_easting) + ", " + _format_float(config.origin_northing) + ")\n"
        "bounds_max_xz = Vector2(" + _format_float(config.tile_max_easting) + ", " + _format_float(config.tile_max_northing) + ")\n"
        "tile_grid = Vector2i(" + str(config.tile_cols) + ", " + str(config.tile_rows) + ")\n"
        "tile_grid_origin = Vector2i(0, 0)\n"
        "tile_size = Vector2(" + _format_float(config.tile_size_m) + ", " + _format_float(config.tile_size_m) + ")\n"
        "tile_indices = Array[Vector2i]([])\n"
        "collision_grid = Vector2i(" + str(COLLISION_GRID_SAMPLES) + ", " + str(COLLISION_GRID_SAMPLES) + ")\n"
        "visual_grid = Vector2i(" + str(COLLISION_GRID_SAMPLES) + ", " + str(COLLISION_GRID_SAMPLES) + ")\n"
        "surface_map_size = Vector2i(" + str(config.grid_width_samples) + ", " + str(config.grid_height_samples) + ")\n"
        'surface_palette_path = ""\n'
        'surface_id_map_path = ""\n'
        "collision_tile_paths = Array[String]([" + collision_paths + "])\n"
        "visual_tile_paths = Array[String]([])\n"
        "feature_override_surface_ids = Array[StringName]([])\n"
        "feature_override_centers = Array[Vector2]([])\n"
        "feature_override_axes_x = Array[Vector2]([])\n"
        "feature_override_axes_z = Array[Vector2]([])\n"
        "feature_override_half_extents = Array[Vector2]([])\n"
        'route_section_ids = Array[StringName]([&"cedar_hollow_zion_main"])\n'
    )
    TERRAIN_DEF_PATH.write_text(text, encoding="utf-8")


def _collect_output_files(tile_entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    files: list[dict[str, Any]] = []
    for entry in tile_entries:
        files.append(_artifact_entry(ROOT / entry["heightmap_path"].removeprefix("res://"), "heightmap_bin"))
        files.append(_artifact_entry(ROOT / entry["tile_json_path"].removeprefix("res://"), "tile_sidecar"))
        files.append(_artifact_entry(ROOT / entry["collision_path"].removeprefix("res://"), "collision_resource"))
    return files


def _artifact_entry(path: Path, role: str) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError("missing output artifact: " + str(path.relative_to(ROOT)))
    return {
        "path": str(path.relative_to(ROOT)),
        "role": role,
        "bytes": path.stat().st_size,
        "sha256": _sha256(path),
    }


def _tile_bounds(config: ZionBakeConfig, col: int, row: int) -> tuple[float, float, float, float]:
    min_x = config.origin_easting + float(col) * config.tile_size_m
    min_z = config.origin_northing + float(row) * config.tile_size_m
    return min_x, min_z, min_x + config.tile_size_m, min_z + config.tile_size_m


def _collision_project_path(col: int, row: int) -> str:
    return "res://data/collision/cedar_hollow_zion_tile_CX" + f"{col:02d}" + "_CZ" + f"{row:02d}" + ".res"


def _project_path(path: Path) -> str:
    return "res://" + str(path.relative_to(ROOT))


def _load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(str(path.relative_to(ROOT)) + " must contain a JSON object")
    return data


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _format_float(value: float) -> str:
    return format(float(value), ".6f")


def _const_float(text: str, name: str) -> float:
    return float(_const_value(text, name))


def _const_int(text: str, name: str) -> int:
    return int(_const_value(text, name))


def _const_value(text: str, name: str) -> str:
    match = re.search(r"^const\s+" + re.escape(name) + r"\s*:\s*\w+\s*=\s*([^\n]+)$", text, flags=re.MULTILINE)
    if match is None:
        raise ValueError("missing GameConfig constant: " + name)
    return match.group(1).strip().strip('"')


if __name__ == "__main__":
    raise SystemExit(main())
