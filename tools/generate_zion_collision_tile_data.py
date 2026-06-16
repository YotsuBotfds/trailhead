#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import struct
from typing import Any
import zlib


ROOT = Path(__file__).resolve().parents[1]
REGION_ID = "cedar_hollow_zion"
REGION_DIR = ROOT / "data/regions" / REGION_ID
TERRAIN_DEF_PATH = ROOT / "data/terrain/cedar_hollow_zion_terrain_def.tres"
GAME_CONFIG_PATH = ROOT / "autoload/game_config.gd"
SOURCE_SURFACE_ID_PATH = ROOT / "data/terrain/cedar_hollow_zion_surface_id.png"
MANIFEST_PATH = REGION_DIR / "collision_tiles_manifest.json"
BAKE_OUTPUT_MANIFEST_PATH = ROOT / "data/bake_inputs/zion_bake_output_manifest.json"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
EXPECTED_SURFACE_IDS = [1, 2, 3, 4, 5, 6]
EXPECTED_CRS = "EPSG:32612"
HEIGHTMAP_FORMAT = "float32_le"
SURFACE_ID_FORMAT = "png_l8"
TILE_SIZE_M = 100.0
SAMPLES_PER_EDGE = 101
SURFACE_ID_PIXELS_PER_TILE = 100
EROSION_SEED = 20260615
EROSION_STRATEGY = "unified-array erosion before tile slicing"
TOOL_VERSION = "c1-nw1-data.2026-06-15"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate Zion Phase-V collision tile surface slices, sidecars, and integrity manifest."
    )
    parser.add_argument("--region-dir", type=Path, default=REGION_DIR)
    parser.add_argument("--surface-id-png", type=Path, default=SOURCE_SURFACE_ID_PATH)
    parser.add_argument("--terrain-def", type=Path, default=TERRAIN_DEF_PATH)
    parser.add_argument("--game-config", type=Path, default=GAME_CONFIG_PATH)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    terrain = _load_terrain_contract(_resolve(args.terrain_def))
    game_config = _load_game_config(_resolve(args.game_config))
    region_dir = _resolve(args.region_dir)
    source_surface_path = _resolve(args.surface_id_png)
    source_surface = _read_l8_png(source_surface_path)
    _validate_contract(terrain, source_surface)

    tiles = [(cx, cy) for cx in range(terrain["tile_grid"][0]) for cy in range(terrain["tile_grid"][1])]
    heightmap_sha256: dict[str, str] = {}
    surface_id_sha256: dict[str, str] = {}
    tile_sidecar_sha256: dict[str, str] = {}
    height_ranges: dict[str, list[float]] = {}
    surface_id_counts: dict[str, dict[str, int]] = {}

    for cx, cy in tiles:
        key = _tile_key(cx, cy)
        tile_dir = region_dir / "tiles" / key
        if not tile_dir.is_dir():
            raise FileNotFoundError("missing tile directory: " + _display(tile_dir))
        old_sidecar = _load_json(tile_dir / "tile.json")
        heightmap_path = tile_dir / "heightmap.bin"
        heightmap_sha = _sha256(heightmap_path)
        heightmap_min, heightmap_max = _height_range(heightmap_path, old_sidecar)
        surface_bytes, counts = _surface_tile_bytes(source_surface, terrain, cx, cy)
        surface_path = tile_dir / "surface_id.png"
        _write_l8_png(surface_path, SURFACE_ID_PIXELS_PER_TILE, SURFACE_ID_PIXELS_PER_TILE, surface_bytes)
        surface_sha = _sha256(surface_path)

        sidecar = _build_sidecar(
            old_sidecar=old_sidecar,
            terrain=terrain,
            game_config=game_config,
            cx=cx,
            cy=cy,
            heightmap_sha=heightmap_sha,
            heightmap_min=heightmap_min,
            heightmap_max=heightmap_max,
            surface_sha=surface_sha,
            surface_counts=counts,
        )
        _write_json(tile_dir / "tile.json", sidecar)
        sidecar_sha = _sha256(tile_dir / "tile.json")

        heightmap_sha256[key] = heightmap_sha
        surface_id_sha256[key] = surface_sha
        tile_sidecar_sha256[key] = sidecar_sha
        height_ranges[key] = [_round_float(heightmap_min), _round_float(heightmap_max)]
        surface_id_counts[key] = {str(value): counts[value] for value in sorted(counts)}

    manifest = _build_manifest(
        terrain=terrain,
        game_config=game_config,
        source_surface_path=source_surface_path,
        source_surface=source_surface,
        tiles=tiles,
        height_ranges=height_ranges,
        surface_id_counts=surface_id_counts,
        heightmap_sha256=heightmap_sha256,
        surface_id_sha256=surface_id_sha256,
        tile_sidecar_sha256=tile_sidecar_sha256,
    )
    _write_json(region_dir / "collision_tiles_manifest.json", manifest)
    _refresh_bake_output_manifest_sidecars(BAKE_OUTPUT_MANIFEST_PATH)
    print("ok: generated Zion collision tile manifest (" + str(len(tiles)) + " tiles)")
    return 0


def _load_terrain_contract(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    tile_grid = _vector2i_field(text, "tile_grid")
    collision_grid = _vector2i_field(text, "collision_grid")
    surface_map_size = _vector2i_field(text, "surface_map_size")
    tile_size = _vector2_field(text, "tile_size")
    bounds_min = _vector2_field(text, "bounds_min_xz")
    bounds_max = _vector2_field(text, "bounds_max_xz")
    if _string_name_field(text, "id") != REGION_ID:
        raise ValueError("terrain id mismatch in " + _display(path))
    return {
        "path": path,
        "tile_grid": tile_grid,
        "collision_grid": collision_grid,
        "surface_map_size": surface_map_size,
        "tile_size": tile_size,
        "bounds_min_xz": bounds_min,
        "bounds_max_xz": bounds_max,
    }


def _load_game_config(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    return {
        "zion_bake_spec_version": _const_string(text, "ZION_BAKE_SPEC_VERSION"),
        "tile_cols": _const_int(text, "ZION_CORRIDOR_TILE_COLS"),
        "tile_rows": _const_int(text, "ZION_CORRIDOR_TILE_ROWS"),
        "stream_tile_size_m": _const_float(text, "STREAM_TILE_SIZE_M"),
    }


def _validate_contract(terrain: dict[str, Any], source_surface: dict[str, Any]) -> None:
    tile_grid = terrain["tile_grid"]
    if tile_grid != [55, 57]:
        raise ValueError("Zion tile_grid expected [55, 57], got " + repr(tile_grid))
    if terrain["collision_grid"] != [SAMPLES_PER_EDGE, SAMPLES_PER_EDGE]:
        raise ValueError("Zion collision_grid expected 101x101")
    if terrain["surface_map_size"] != [source_surface["width"], source_surface["height"]]:
        raise ValueError("terrain surface_map_size does not match source PNG dimensions")
    if terrain["tile_size"] != [TILE_SIZE_M, TILE_SIZE_M]:
        raise ValueError("Zion tile_size expected 100m")
    expected_surface_size = [
        tile_grid[0] * SURFACE_ID_PIXELS_PER_TILE + 1,
        tile_grid[1] * SURFACE_ID_PIXELS_PER_TILE + 1,
    ]
    if [source_surface["width"], source_surface["height"]] != expected_surface_size:
        raise ValueError("source surface-ID dimensions expected " + repr(expected_surface_size))
    if source_surface["unique_samples"] != EXPECTED_SURFACE_IDS:
        raise ValueError("source surface-ID ids expected " + repr(EXPECTED_SURFACE_IDS))


def _build_sidecar(
    *,
    old_sidecar: dict[str, Any],
    terrain: dict[str, Any],
    game_config: dict[str, Any],
    cx: int,
    cy: int,
    heightmap_sha: str,
    heightmap_min: float,
    heightmap_max: float,
    surface_sha: str,
    surface_counts: Counter[int],
) -> dict[str, Any]:
    key = _tile_key(cx, cy)
    source_value = old_sidecar.get("source", "1m")
    collision_path = _string_or_empty(old_sidecar.get("collision_path"))
    if not collision_path and isinstance(old_sidecar.get("collision"), dict):
        collision_path = _string_or_empty(old_sidecar["collision"].get("path"))
    return {
        "schema_version": 1,
        "region_id": REGION_ID,
        "tile": {
            "cx": cx,
            "cy": cy,
            "key": key,
        },
        "tile_size_m": TILE_SIZE_M,
        "heightmap": {
            "path": "heightmap.bin",
            "format": HEIGHTMAP_FORMAT,
            "shape": [SAMPLES_PER_EDGE, SAMPLES_PER_EDGE],
            "sha256": heightmap_sha,
            "min_y": _round_float(heightmap_min),
            "max_y": _round_float(heightmap_max),
            "row_axis": "z_increasing",
            "column_axis": "x_increasing",
        },
        "surface_id": {
            "path": "surface_id.png",
            "format": SURFACE_ID_FORMAT,
            "shape": [SURFACE_ID_PIXELS_PER_TILE, SURFACE_ID_PIXELS_PER_TILE],
            "sha256": surface_sha,
            "counts": {str(value): surface_counts[value] for value in sorted(surface_counts)},
        },
        "bake": {
            "seed": EROSION_SEED,
            "seed_derivation": "explicit integer EROSION_SEED=20260615; no Python str hash",
            "erosion_strategy": EROSION_STRATEGY,
            "bake_spec_version": game_config["zion_bake_spec_version"],
            "tool": "tools/bake_zion_terrain.py",
            "tool_version": "zion-terrain.2026-06-15",
        },
        "source": source_value,
        "crs": _string_or_default(old_sidecar.get("crs"), EXPECTED_CRS),
        "bounds_utm": _bounds_for_tile(old_sidecar, terrain, cx, cy),
        "cell_spacing_m": float(old_sidecar.get("cell_spacing_m", 1.0)),
        "collision": {
            "path": collision_path,
        },
    }


def _build_manifest(
    *,
    terrain: dict[str, Any],
    game_config: dict[str, Any],
    source_surface_path: Path,
    source_surface: dict[str, Any],
    tiles: list[tuple[int, int]],
    height_ranges: dict[str, list[float]],
    surface_id_counts: dict[str, dict[str, int]],
    heightmap_sha256: dict[str, str],
    surface_id_sha256: dict[str, str],
    tile_sidecar_sha256: dict[str, str],
) -> dict[str, Any]:
    tile_grid = terrain["tile_grid"]
    bounds_min = terrain["bounds_min_xz"]
    bounds_max = terrain["bounds_max_xz"]
    return {
        "schema_version": 1,
        "region_id": REGION_ID,
        "bake_seed": EROSION_SEED,
        "bake_seed_derivation": "explicit integer EROSION_SEED=20260615; no Python str hash",
        "bake_spec_version": game_config["zion_bake_spec_version"],
        "corridor_version": game_config["zion_bake_spec_version"],
        "erosion_strategy": EROSION_STRATEGY,
        "grid_size_tiles": tile_grid,
        "origin_cell": [0, 0],
        "pythonhashseed_safe": True,
        "tile_size_m": TILE_SIZE_M,
        "samples_per_edge": SAMPLES_PER_EDGE,
        "surface_id_pixels_per_tile": SURFACE_ID_PIXELS_PER_TILE,
        "heightmap_format": HEIGHTMAP_FORMAT,
        "surface_id_format": SURFACE_ID_FORMAT,
        "crs": EXPECTED_CRS,
        "bounds_utm": [bounds_min[0], bounds_min[1], bounds_max[0], bounds_max[1]],
        "surface_id_source": {
            "path": _repo_path(source_surface_path),
            "format": "png_l8",
            "shape": [source_surface["width"], source_surface["height"]],
            "sha256": _sha256(source_surface_path),
            "counts": {str(value): source_surface["sample_counts"][value] for value in sorted(source_surface["sample_counts"])},
        },
        "surface_id_tile_crop": {
            "left": "cx * surface_id_pixels_per_tile",
            "top": "(tile_grid_y - 1 - cy) * surface_id_pixels_per_tile",
            "orientation": "TerrainDef.world_to_surface_uv maps north to PNG row 0; cy=0 is the south row.",
        },
        "height_ranges": height_ranges,
        "surface_id_counts": surface_id_counts,
        "heightmap_sha256": heightmap_sha256,
        "surface_id_sha256": surface_id_sha256,
        "tile_sidecar_sha256": tile_sidecar_sha256,
        "tiles": [[cx, cy] for cx, cy in tiles],
        "tool": "tools/generate_zion_collision_tile_data.py",
        "tool_version": TOOL_VERSION,
    }


def _refresh_bake_output_manifest_sidecars(path: Path) -> None:
    if not path.is_file():
        return
    manifest = _load_json(path)
    files = manifest.get("files", [])
    if not isinstance(files, list):
        raise ValueError("bake output manifest files must be a list: " + _display(path))
    updated_count = 0
    for entry in files:
        if not isinstance(entry, dict) or entry.get("role") != "tile_sidecar":
            continue
        raw_path = entry.get("path")
        if not isinstance(raw_path, str):
            raise ValueError("tile_sidecar entry path must be a string")
        sidecar_path = ROOT / raw_path
        if not sidecar_path.is_file():
            raise FileNotFoundError("missing tile sidecar in bake output manifest: " + _display(sidecar_path))
        entry["bytes"] = sidecar_path.stat().st_size
        entry["sha256"] = _sha256(sidecar_path)
        updated_count += 1
    if updated_count:
        _write_json(path, manifest)


def _surface_tile_bytes(source_surface: dict[str, Any], terrain: dict[str, Any], cx: int, cy: int) -> tuple[bytes, Counter[int]]:
    source_width = int(source_surface["width"])
    samples = source_surface["samples"]
    tile_rows = int(terrain["tile_grid"][1])
    left = cx * SURFACE_ID_PIXELS_PER_TILE
    top = (tile_rows - 1 - cy) * SURFACE_ID_PIXELS_PER_TILE
    out = bytearray()
    for row in range(SURFACE_ID_PIXELS_PER_TILE):
        start = (top + row) * source_width + left
        out.extend(samples[start : start + SURFACE_ID_PIXELS_PER_TILE])
    data = bytes(out)
    return data, Counter(data)


def _read_l8_png(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("invalid PNG signature: " + _display(path))
    offset = 8
    width = 0
    height = 0
    bit_depth = 0
    color_type = 0
    idat = bytearray()
    saw_iend = False
    while offset + 8 <= len(data):
        chunk_length = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        chunk_type = data[offset : offset + 4]
        offset += 4
        if offset + chunk_length + 4 > len(data):
            raise ValueError("truncated PNG chunk: " + _display(path))
        chunk_data = data[offset : offset + chunk_length]
        offset += chunk_length
        expected_crc = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ValueError("invalid PNG CRC for " + chunk_type.decode("latin1"))
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack_from(">IIBBBBB", chunk_data, 0)
            if compression != 0 or filter_method != 0 or interlace != 0:
                raise ValueError("unsupported PNG header values: " + _display(path))
        elif chunk_type == b"IDAT":
            idat.extend(chunk_data)
        elif chunk_type == b"IEND":
            saw_iend = True
            break
    if not saw_iend:
        raise ValueError("PNG missing IEND: " + _display(path))
    if width <= 0 or height <= 0:
        raise ValueError("PNG has invalid dimensions: " + _display(path))
    if bit_depth != 8 or color_type != 0:
        raise ValueError("source surface-ID PNG must be 8-bit grayscale L mode")
    samples = _decode_l8_samples(width, height, bytes(idat))
    counts = Counter(samples)
    return {
        "width": width,
        "height": height,
        "samples": samples,
        "unique_samples": sorted(counts),
        "sample_counts": dict(sorted(counts.items())),
    }


def _decode_l8_samples(width: int, height: int, compressed_data: bytes) -> bytes:
    stride = width
    raw = zlib.decompress(compressed_data)
    expected_size = (stride + 1) * height
    if len(raw) != expected_size:
        raise ValueError("PNG payload size mismatch")
    previous = bytearray(stride)
    samples = bytearray(width * height)
    raw_offset = 0
    sample_offset = 0
    for _row_index in range(height):
        filter_type = raw[raw_offset]
        raw_offset += 1
        row = bytearray(raw[raw_offset : raw_offset + stride])
        raw_offset += stride
        _unfilter_l8_row(row, previous, filter_type)
        samples[sample_offset : sample_offset + stride] = row
        sample_offset += stride
        previous = row
    return bytes(samples)


def _unfilter_l8_row(row: bytearray, previous: bytearray, filter_type: int) -> None:
    if filter_type == 0:
        return
    if filter_type == 1:
        for index in range(len(row)):
            left = row[index - 1] if index >= 1 else 0
            row[index] = (row[index] + left) & 0xFF
        return
    if filter_type == 2:
        for index in range(len(row)):
            row[index] = (row[index] + previous[index]) & 0xFF
        return
    if filter_type == 3:
        for index in range(len(row)):
            left = row[index - 1] if index >= 1 else 0
            up = previous[index]
            row[index] = (row[index] + ((left + up) // 2)) & 0xFF
        return
    if filter_type == 4:
        for index in range(len(row)):
            left = row[index - 1] if index >= 1 else 0
            up = previous[index]
            up_left = previous[index - 1] if index >= 1 else 0
            row[index] = (row[index] + _paeth(left, up, up_left)) & 0xFF
        return
    raise ValueError("unsupported PNG filter type " + str(filter_type))


def _write_l8_png(path: Path, width: int, height: int, samples: bytes) -> None:
    if len(samples) != width * height:
        raise ValueError("sample byte count does not match PNG dimensions")
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        start = y * width
        raw.extend(samples[start : start + width])
    png = bytearray(PNG_SIGNATURE)
    png.extend(_png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)))
    png.extend(_png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    png.extend(_png_chunk(b"IEND", b""))
    path.write_bytes(bytes(png))


def _png_chunk(chunk_type: bytes, chunk_data: bytes) -> bytes:
    return (
        struct.pack(">I", len(chunk_data))
        + chunk_type
        + chunk_data
        + struct.pack(">I", zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF)
    )


def _height_range(path: Path, old_sidecar: dict[str, Any]) -> tuple[float, float]:
    old_min = old_sidecar.get("height_min")
    old_max = old_sidecar.get("height_max")
    if isinstance(old_min, (int, float)) and isinstance(old_max, (int, float)):
        return float(old_min), float(old_max)
    heightmap = old_sidecar.get("heightmap")
    if isinstance(heightmap, dict):
        min_y = heightmap.get("min_y")
        max_y = heightmap.get("max_y")
        if isinstance(min_y, (int, float)) and isinstance(max_y, (int, float)):
            return float(min_y), float(max_y)
    values = struct.iter_unpack("<f", path.read_bytes())
    min_value = math.inf
    max_value = -math.inf
    for (value,) in values:
        min_value = min(min_value, value)
        max_value = max(max_value, value)
    if not math.isfinite(min_value) or not math.isfinite(max_value):
        raise ValueError("heightmap has no finite float values: " + _display(path))
    return min_value, max_value


def _bounds_for_tile(old_sidecar: dict[str, Any], terrain: dict[str, Any], cx: int, cy: int) -> list[float]:
    old_bounds = old_sidecar.get("bounds_utm")
    if isinstance(old_bounds, list) and len(old_bounds) == 4:
        return [float(value) for value in old_bounds]
    bounds_min = terrain["bounds_min_xz"]
    min_x = float(bounds_min[0]) + float(cx) * TILE_SIZE_M
    min_z = float(bounds_min[1]) + float(cy) * TILE_SIZE_M
    return [min_x, min_z, min_x + TILE_SIZE_M, min_z + TILE_SIZE_M]


def _vector2i_field(text: str, name: str) -> list[int]:
    match = re.search(r"^" + re.escape(name) + r"\s*=\s*Vector2i\(([-0-9]+),\s*([-0-9]+)\)", text, re.MULTILINE)
    if match is None:
        raise ValueError("missing Vector2i field " + name)
    return [int(match.group(1)), int(match.group(2))]


def _vector2_field(text: str, name: str) -> list[float]:
    match = re.search(
        r"^" + re.escape(name) + r"\s*=\s*Vector2\(([-0-9.]+),\s*([-0-9.]+)\)",
        text,
        re.MULTILINE,
    )
    if match is None:
        raise ValueError("missing Vector2 field " + name)
    return [float(match.group(1)), float(match.group(2))]


def _string_name_field(text: str, name: str) -> str:
    match = re.search(r'^' + re.escape(name) + r'\s*=\s*&"([^"]+)"', text, re.MULTILINE)
    if match is None:
        raise ValueError("missing StringName field " + name)
    return match.group(1)


def _const_int(text: str, name: str) -> int:
    match = re.search(r"^const\s+" + re.escape(name) + r"\s*:\s*int\s*=\s*([-0-9]+)", text, re.MULTILINE)
    if match is None:
        raise ValueError("missing int const " + name)
    return int(match.group(1))


def _const_float(text: str, name: str) -> float:
    match = re.search(r"^const\s+" + re.escape(name) + r"\s*:\s*float\s*=\s*([-0-9.]+)", text, re.MULTILINE)
    if match is None:
        raise ValueError("missing float const " + name)
    return float(match.group(1))


def _const_string(text: str, name: str) -> str:
    match = re.search(r'^const\s+' + re.escape(name) + r'\s*:\s*String\s*=\s*"([^"]+)"', text, re.MULTILINE)
    if match is None:
        raise ValueError("missing string const " + name)
    return match.group(1)


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("JSON root must be an object: " + _display(path))
    return data


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def _resolve(path: Path) -> Path:
    if path.is_absolute():
        return path
    return ROOT / path


def _repo_path(path: Path) -> str:
    return str(path.relative_to(ROOT))


def _display(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def _tile_key(cx: int, cy: int) -> str:
    return str(cx) + "_" + str(cy)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _paeth(left: int, up: int, up_left: int) -> int:
    estimate = left + up - up_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    up_left_distance = abs(estimate - up_left)
    if left_distance <= up_distance and left_distance <= up_left_distance:
        return left
    if up_distance <= up_left_distance:
        return up
    return up_left


def _round_float(value: float) -> float:
    return round(float(value), 8)


def _string_or_empty(value: Any) -> str:
    if isinstance(value, str):
        return value
    return ""


def _string_or_default(value: Any, default: str) -> str:
    if isinstance(value, str) and value:
        return value
    return default


if __name__ == "__main__":
    raise SystemExit(main())
