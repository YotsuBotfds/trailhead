#!/usr/bin/env python3
"""Bake deterministic regional collision tiles for Phase V streaming.

B1-BAKE intentionally uses an explicit integer corridor_version as the only
seed source. It never calls Python's hash(), so output does not depend on
PYTHONHASHSEED. Per the forward reserve correction, erosion is applied once to
the unified corridor array before tiles are sliced; there are no per-tile seeds.

The initial --dry-run mode is the committed spike_1km fixture path: it uses a
synthetic source corridor so CI can bake and hash-gate the canonical tile
format without external DEM inputs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from erosion import ErosionConfig, build_eroded_heightfield


ROOT = Path(__file__).resolve().parents[1]
GAME_CONFIG_PATH = ROOT / "autoload/game_config.gd"
OUTPUT_BASE = ROOT / "data/regions"
TOOL_VERSION = "b1-bake.2026-06-15"
SCHEMA_VERSION = 1
EXPECTED_TILE_SIZE_M = 100.0
HEIGHTMAP_FORMAT = "float32_le"
SURFACE_ID_FORMAT = "png_l8"


@dataclass(frozen=True)
class RegionConfig:
    region_id: str
    corridor_version: int
    tile_cols: int
    tile_rows: int
    origin_cx: int
    origin_cy: int
    samples_per_edge: int
    surface_pixels_per_tile: int

    @property
    def tile_intervals(self) -> int:
        return self.samples_per_edge - 1

    @property
    def unified_width(self) -> int:
        return self.tile_cols * self.tile_intervals + 1

    @property
    def unified_height(self) -> int:
        return self.tile_rows * self.tile_intervals + 1


REGIONS: dict[str, RegionConfig] = {
    "spike_1km": RegionConfig(
        region_id="spike_1km",
        corridor_version=2026061501,
        tile_cols=10,
        tile_rows=10,
        origin_cx=0,
        origin_cy=0,
        samples_per_edge=101,
        surface_pixels_per_tile=100,
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bake a deterministic Phase V regional tile fixture.")
    parser.add_argument("--region", default="spike_1km", choices=sorted(REGIONS), help="Region fixture to bake.")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Use the synthetic CI fixture source and write deterministic spike artifacts.",
    )
    parser.add_argument("--output-base", type=Path, default=OUTPUT_BASE, help="Base output directory for regions.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = REGIONS[args.region]
    try:
        tile_size_m = _read_stream_tile_size()
        if abs(tile_size_m - EXPECTED_TILE_SIZE_M) > 1.0e-6:
            raise ValueError(f"STREAM_TILE_SIZE_M {tile_size_m} != expected {EXPECTED_TILE_SIZE_M}")
        if not args.dry_run:
            raise ValueError("only --dry-run synthetic fixture baking is implemented for B1-BAKE")
        manifest = bake_region(config, args.output_base, tile_size_m)
    except Exception as exc:
        print("fail: " + str(exc), file=sys.stderr)
        return 1

    print(
        "ok: baked "
        + config.region_id
        + " ("
        + str(len(manifest["tiles"]))
        + " tiles, corridor_version "
        + str(config.corridor_version)
        + ")"
    )
    print("manifest: " + _display_path(args.output_base / config.region_id / "collision_tiles_manifest.json"))
    return 0


def bake_region(config: RegionConfig, output_base: Path, tile_size_m: float) -> dict[str, Any]:
    region_dir = output_base / config.region_id
    tiles_dir = region_dir / "tiles"
    tiles_dir.mkdir(parents=True, exist_ok=True)

    unified = _build_unified_heightfield(config, tile_size_m)
    tile_arrays = _slice_tiles(config, unified)
    _assert_tile_seams(config, tile_arrays)

    region_surface = _classify_surface_ids(unified, config)
    tiles: list[list[int]] = []
    heightmap_sha256: dict[str, str] = {}
    surface_id_sha256: dict[str, str] = {}
    tile_sidecar_sha256: dict[str, str] = {}
    height_ranges: dict[str, list[float]] = {}
    surface_id_counts: dict[str, dict[str, int]] = {}

    for local_cx, local_cy in _iter_local_cells(config):
        cx = config.origin_cx + local_cx
        cy = config.origin_cy + local_cy
        key = _tile_key(cx, cy)
        tile_dir = tiles_dir / key
        tile_dir.mkdir(parents=True, exist_ok=True)

        heightmap_path = tile_dir / "heightmap.bin"
        surface_path = tile_dir / "surface_id.png"
        sidecar_path = tile_dir / "tile.json"

        tile_height = tile_arrays[(local_cx, local_cy)]
        height_bytes = np.ascontiguousarray(tile_height.astype("<f4", copy=False)).tobytes(order="C")
        heightmap_path.write_bytes(height_bytes)
        height_sha = _sha256(heightmap_path)

        surface_tile = _slice_surface_tile(config, region_surface, local_cx, local_cy)
        surface_path.write_bytes(_encode_grayscale_png(surface_tile))
        surface_sha = _sha256(surface_path)

        sidecar = _tile_sidecar(
            config=config,
            tile_size_m=tile_size_m,
            cx=cx,
            cy=cy,
            heightmap_sha=height_sha,
            surface_sha=surface_sha,
            height_min=float(np.min(tile_height)),
            height_max=float(np.max(tile_height)),
            surface_counts=_surface_counts(surface_tile),
        )
        _write_json(sidecar_path, sidecar)
        sidecar_sha = _sha256(sidecar_path)

        tiles.append([cx, cy])
        heightmap_sha256[key] = height_sha
        surface_id_sha256[key] = surface_sha
        tile_sidecar_sha256[key] = sidecar_sha
        height_ranges[key] = [sidecar["heightmap"]["min_y"], sidecar["heightmap"]["max_y"]]
        surface_id_counts[key] = sidecar["surface_id"]["counts"]

    manifest = _manifest(
        config=config,
        tile_size_m=tile_size_m,
        tiles=tiles,
        heightmap_sha256=heightmap_sha256,
        surface_id_sha256=surface_id_sha256,
        tile_sidecar_sha256=tile_sidecar_sha256,
        height_ranges=height_ranges,
        surface_id_counts=surface_id_counts,
    )
    _write_json(region_dir / "collision_tiles_manifest.json", manifest)
    return manifest


def _build_unified_heightfield(config: RegionConfig, tile_size_m: float) -> np.ndarray:
    width_m = config.tile_cols * tile_size_m
    height_m = config.tile_rows * tile_size_m
    bounds = ((0.0, 0.0), (width_m, height_m))
    erosion_config = ErosionConfig(
        base_height=0.0,
        fbm_amplitude=0.72,
        fbm_base_feature_size=45.0,
        fbm_octaves=5,
        fbm_lacunarity=2.0,
        fbm_persistence=0.5,
        fbm_ridge_mix=0.34,
        hydraulic_droplets=2048,
        hydraulic_max_steps=24,
        hydraulic_brush_radius=3,
        thermal_iterations=4,
        thermal_talus=0.03,
        thermal_rate=0.14,
    )
    unified = build_eroded_heightfield(
        config.unified_width,
        config.unified_height,
        bounds,
        seed=config.corridor_version,
        config=erosion_config,
    )
    return np.ascontiguousarray(unified.astype(np.float32, copy=False))


def _slice_tiles(config: RegionConfig, unified: np.ndarray) -> dict[tuple[int, int], np.ndarray]:
    tile_arrays: dict[tuple[int, int], np.ndarray] = {}
    for local_cx, local_cy in _iter_local_cells(config):
        x0 = local_cx * config.tile_intervals
        z0 = local_cy * config.tile_intervals
        x1 = x0 + config.samples_per_edge
        z1 = z0 + config.samples_per_edge
        tile_arrays[(local_cx, local_cy)] = np.ascontiguousarray(unified[z0:z1, x0:x1])
    return tile_arrays


def _assert_tile_seams(config: RegionConfig, tile_arrays: dict[tuple[int, int], np.ndarray]) -> None:
    for local_cx, local_cy in _iter_local_cells(config):
        tile = tile_arrays[(local_cx, local_cy)]
        if local_cx + 1 < config.tile_cols:
            right = tile_arrays[(local_cx + 1, local_cy)]
            if not np.array_equal(tile[:, -1], right[:, 0]):
                raise ValueError("height seam mismatch at " + _local_pair(local_cx, local_cy, local_cx + 1, local_cy))
        if local_cy + 1 < config.tile_rows:
            down = tile_arrays[(local_cx, local_cy + 1)]
            if not np.array_equal(tile[-1, :], down[0, :]):
                raise ValueError("height seam mismatch at " + _local_pair(local_cx, local_cy, local_cx, local_cy + 1))


def _classify_surface_ids(unified: np.ndarray, config: RegionConfig) -> np.ndarray:
    interior = unified[:-1, :-1]
    normalized = interior - float(np.mean(interior))
    surface = np.full(interior.shape, 4, dtype=np.uint8)
    surface[normalized > 0.12] = 2
    surface[normalized < -0.18] = 5

    rows, cols = surface.shape
    z_indices = np.arange(rows, dtype=np.float32)[:, None]
    x_indices = np.arange(cols, dtype=np.float32)[None, :]
    centerline = rows * 0.5 + np.sin(x_indices / 73.0) * rows * 0.08
    river_mask = np.abs(z_indices - centerline) <= 4.0
    trail_mask = np.abs(z_indices - (centerline + 14.0)) <= 2.0
    surface[river_mask] = 1
    surface[trail_mask] = 6
    return surface


def _slice_surface_tile(config: RegionConfig, region_surface: np.ndarray, local_cx: int, local_cy: int) -> np.ndarray:
    pixels = config.surface_pixels_per_tile
    x0 = local_cx * pixels
    z0 = local_cy * pixels
    tile = region_surface[z0 : z0 + pixels, x0 : x0 + pixels]
    if tile.shape != (pixels, pixels):
        raise ValueError("surface tile shape mismatch for " + _tile_key(local_cx, local_cy))
    return np.ascontiguousarray(tile.astype(np.uint8, copy=False))


def _tile_sidecar(
    *,
    config: RegionConfig,
    tile_size_m: float,
    cx: int,
    cy: int,
    heightmap_sha: str,
    surface_sha: str,
    height_min: float,
    height_max: float,
    surface_counts: dict[str, int],
) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "region_id": config.region_id,
        "tile": {
            "cx": cx,
            "cy": cy,
            "key": _tile_key(cx, cy),
        },
        "tile_size_m": tile_size_m,
        "heightmap": {
            "path": "heightmap.bin",
            "format": HEIGHTMAP_FORMAT,
            "shape": [config.samples_per_edge, config.samples_per_edge],
            "row_axis": "z_increasing",
            "column_axis": "x_increasing",
            "min_y": round(height_min, 8),
            "max_y": round(height_max, 8),
            "sha256": heightmap_sha,
        },
        "surface_id": {
            "path": "surface_id.png",
            "format": SURFACE_ID_FORMAT,
            "shape": [config.surface_pixels_per_tile, config.surface_pixels_per_tile],
            "counts": surface_counts,
            "sha256": surface_sha,
        },
        "bake": _bake_metadata(config),
    }


def _manifest(
    *,
    config: RegionConfig,
    tile_size_m: float,
    tiles: list[list[int]],
    heightmap_sha256: dict[str, str],
    surface_id_sha256: dict[str, str],
    tile_sidecar_sha256: dict[str, str],
    height_ranges: dict[str, list[float]],
    surface_id_counts: dict[str, dict[str, int]],
) -> dict[str, Any]:
    sorted_tiles = sorted(tiles, key=lambda cell: (cell[0], cell[1]))
    return {
        "schema_version": SCHEMA_VERSION,
        "region_id": config.region_id,
        "tool": "tools/bake_region.py",
        "tool_version": TOOL_VERSION,
        "tile_size_m": tile_size_m,
        "grid_size_tiles": [config.tile_cols, config.tile_rows],
        "origin_cell": [config.origin_cx, config.origin_cy],
        "samples_per_edge": config.samples_per_edge,
        "heightmap_format": HEIGHTMAP_FORMAT,
        "surface_id_format": SURFACE_ID_FORMAT,
        "surface_id_pixels_per_tile": config.surface_pixels_per_tile,
        "tiles": sorted_tiles,
        "corridor_version": config.corridor_version,
        "bake_seed": config.corridor_version,
        "bake_seed_derivation": "numpy.random.default_rng(corridor_version); no Python str hash",
        "erosion_strategy": "unified-array erosion before tile slicing",
        "pythonhashseed_safe": True,
        "heightmap_sha256": _sorted_mapping(heightmap_sha256),
        "surface_id_sha256": _sorted_mapping(surface_id_sha256),
        "tile_sidecar_sha256": _sorted_mapping(tile_sidecar_sha256),
        "height_ranges": _sorted_mapping(height_ranges),
        "surface_id_counts": _sorted_mapping(surface_id_counts),
    }


def _bake_metadata(config: RegionConfig) -> dict[str, Any]:
    return {
        "tool": "tools/bake_region.py",
        "tool_version": TOOL_VERSION,
        "corridor_version": config.corridor_version,
        "seed": config.corridor_version,
        "seed_derivation": "explicit integer corridor_version; no Python str hash",
        "erosion_strategy": "unified-array erosion before tile slicing",
    }


def _encode_grayscale_png(samples: np.ndarray) -> bytes:
    if samples.dtype != np.uint8:
        raise ValueError("surface-ID PNG samples must be uint8")
    if samples.ndim != 2:
        raise ValueError("surface-ID PNG samples must be 2D")
    height, width = samples.shape
    raw_rows = bytearray()
    for row in samples:
        raw_rows.append(0)
        raw_rows.extend(bytes(row))
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
        + _png_chunk(b"IDAT", zlib.compress(bytes(raw_rows), level=9))
        + _png_chunk(b"IEND", b"")
    )


def _png_chunk(chunk_type: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + chunk_type
        + payload
        + struct.pack(">I", zlib.crc32(chunk_type + payload) & 0xFFFFFFFF)
    )


def _surface_counts(surface_tile: np.ndarray) -> dict[str, int]:
    values, counts = np.unique(surface_tile, return_counts=True)
    result: dict[str, int] = {}
    for value, count in zip(values.tolist(), counts.tolist(), strict=True):
        result[str(int(value))] = int(count)
    return result


def _read_stream_tile_size() -> float:
    text = GAME_CONFIG_PATH.read_text(encoding="utf-8")
    match = re.search(r"^const\s+STREAM_TILE_SIZE_M\s*:\s*float\s*=\s*([0-9.]+)\s*$", text, flags=re.MULTILINE)
    if match is None:
        raise ValueError("missing GameConfig constant: STREAM_TILE_SIZE_M")
    return float(match.group(1))


def _iter_local_cells(config: RegionConfig):
    for local_cx in range(config.tile_cols):
        for local_cy in range(config.tile_rows):
            yield local_cx, local_cy


def _tile_key(cx: int, cy: int) -> str:
    return str(cx) + "_" + str(cy)


def _local_pair(ax: int, ay: int, bx: int, by: int) -> str:
    return _tile_key(ax, ay) + " -> " + _tile_key(bx, by)


def _sorted_mapping(data: dict[str, Any]) -> dict[str, Any]:
    return {key: data[key] for key in sorted(data)}


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


if __name__ == "__main__":
    raise SystemExit(main())
