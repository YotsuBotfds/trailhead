#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

from check_surface_id_png import read_png_summary


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REGION_PATH = ROOT / "data/regions/spike_1km"
MANIFEST_NAME = "collision_tiles_manifest.json"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Phase V collision tile manifest hashes.")
    parser.add_argument("region_path", type=Path, nargs="?", default=DEFAULT_REGION_PATH)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        summary = check_region(args.region_path)
    except Exception as exc:
        print("fail: " + str(exc), file=sys.stderr)
        return 1
    print(
        "ok: collision tile integrity "
        + summary["region_id"]
        + " ("
        + str(summary["tile_count"])
        + " tiles)"
    )
    return 0


def check_region(region_path: Path) -> dict[str, Any]:
    region_dir = _resolve_path(region_path)
    manifest_path = region_dir / MANIFEST_NAME
    if not manifest_path.is_file():
        raise FileNotFoundError("missing collision tile manifest: " + _display_path(manifest_path))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    _require_equal(manifest.get("schema_version"), 1, "manifest schema_version")
    region_id = _require_string(manifest, "region_id")
    samples_per_edge = _require_positive_int(manifest, "samples_per_edge")
    surface_pixels_per_tile = _require_positive_int(manifest, "surface_id_pixels_per_tile")
    tile_size_m = _require_number(manifest, "tile_size_m")
    if tile_size_m <= 0.0:
        raise ValueError("manifest tile_size_m must be positive")

    tiles = _require_tiles(manifest)
    heightmap_hashes = _require_sha_mapping(manifest, "heightmap_sha256", tiles)
    surface_hashes = _require_sha_mapping(manifest, "surface_id_sha256", tiles)
    sidecar_hashes = _require_sha_mapping(manifest, "tile_sidecar_sha256", tiles)

    for cx, cy in tiles:
        key = _tile_key(cx, cy)
        tile_dir = region_dir / "tiles" / key
        heightmap_path = tile_dir / "heightmap.bin"
        surface_path = tile_dir / "surface_id.png"
        sidecar_path = tile_dir / "tile.json"
        if not tile_dir.is_dir():
            raise FileNotFoundError("missing tile directory: " + _display_path(tile_dir))
        _check_heightmap(heightmap_path, samples_per_edge, heightmap_hashes[key])
        _check_surface_png(surface_path, surface_pixels_per_tile, surface_hashes[key])
        _check_sidecar(
            sidecar_path=sidecar_path,
            expected_sha=sidecar_hashes[key],
            region_id=region_id,
            cx=cx,
            cy=cy,
            samples_per_edge=samples_per_edge,
            surface_pixels_per_tile=surface_pixels_per_tile,
            heightmap_sha=heightmap_hashes[key],
            surface_sha=surface_hashes[key],
        )

    return {"region_id": region_id, "tile_count": len(tiles)}


def _check_heightmap(path: Path, samples_per_edge: int, expected_sha: str) -> None:
    if not path.is_file():
        raise FileNotFoundError("missing heightmap: " + _display_path(path))
    expected_size = samples_per_edge * samples_per_edge * 4
    actual_size = path.stat().st_size
    if actual_size != expected_size:
        raise ValueError(_display_path(path) + " byte size " + str(actual_size) + " != " + str(expected_size))
    _check_sha(path, expected_sha)


def _check_surface_png(path: Path, pixels_per_tile: int, expected_sha: str) -> None:
    if not path.is_file():
        raise FileNotFoundError("missing surface-ID PNG: " + _display_path(path))
    summary = read_png_summary(path)
    if summary["width"] != pixels_per_tile or summary["height"] != pixels_per_tile:
        raise ValueError(
            _display_path(path)
            + " dimensions "
            + str(summary["width"])
            + "x"
            + str(summary["height"])
            + " != "
            + str(pixels_per_tile)
            + "x"
            + str(pixels_per_tile)
        )
    if summary["color_type"] != 0:
        raise ValueError(_display_path(path) + " must be grayscale PNG color type 0")
    _check_sha(path, expected_sha)


def _check_sidecar(
    *,
    sidecar_path: Path,
    expected_sha: str,
    region_id: str,
    cx: int,
    cy: int,
    samples_per_edge: int,
    surface_pixels_per_tile: int,
    heightmap_sha: str,
    surface_sha: str,
) -> None:
    if not sidecar_path.is_file():
        raise FileNotFoundError("missing tile sidecar: " + _display_path(sidecar_path))
    _check_sha(sidecar_path, expected_sha)
    sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
    _require_equal(sidecar.get("schema_version"), 1, _display_path(sidecar_path) + " schema_version")
    _require_equal(sidecar.get("region_id"), region_id, _display_path(sidecar_path) + " region_id")
    tile = sidecar.get("tile")
    if not isinstance(tile, dict):
        raise ValueError(_display_path(sidecar_path) + " tile must be an object")
    _require_equal(tile.get("cx"), cx, _display_path(sidecar_path) + " tile.cx")
    _require_equal(tile.get("cy"), cy, _display_path(sidecar_path) + " tile.cy")
    _require_equal(tile.get("key"), _tile_key(cx, cy), _display_path(sidecar_path) + " tile.key")

    heightmap = sidecar.get("heightmap")
    if not isinstance(heightmap, dict):
        raise ValueError(_display_path(sidecar_path) + " heightmap must be an object")
    _require_equal(heightmap.get("path"), "heightmap.bin", _display_path(sidecar_path) + " heightmap.path")
    _require_equal(heightmap.get("format"), "float32_le", _display_path(sidecar_path) + " heightmap.format")
    _require_equal(heightmap.get("shape"), [samples_per_edge, samples_per_edge], _display_path(sidecar_path) + " heightmap.shape")
    _require_equal(heightmap.get("sha256"), heightmap_sha, _display_path(sidecar_path) + " heightmap.sha256")

    surface_id = sidecar.get("surface_id")
    if not isinstance(surface_id, dict):
        raise ValueError(_display_path(sidecar_path) + " surface_id must be an object")
    _require_equal(surface_id.get("path"), "surface_id.png", _display_path(sidecar_path) + " surface_id.path")
    _require_equal(surface_id.get("format"), "png_l8", _display_path(sidecar_path) + " surface_id.format")
    _require_equal(surface_id.get("shape"), [surface_pixels_per_tile, surface_pixels_per_tile], _display_path(sidecar_path) + " surface_id.shape")
    _require_equal(surface_id.get("sha256"), surface_sha, _display_path(sidecar_path) + " surface_id.sha256")

    bake = sidecar.get("bake")
    if not isinstance(bake, dict):
        raise ValueError(_display_path(sidecar_path) + " bake must be an object")
    if "no Python str hash" not in str(bake.get("seed_derivation", "")):
        raise ValueError(_display_path(sidecar_path) + " bake.seed_derivation must document hash-free seed derivation")
    if str(bake.get("erosion_strategy", "")) != "unified-array erosion before tile slicing":
        raise ValueError(_display_path(sidecar_path) + " bake.erosion_strategy mismatch")


def _require_tiles(manifest: dict[str, Any]) -> list[tuple[int, int]]:
    raw_tiles = manifest.get("tiles")
    if not isinstance(raw_tiles, list) or not raw_tiles:
        raise ValueError("manifest tiles must be a non-empty array")
    tiles: list[tuple[int, int]] = []
    for raw_cell in raw_tiles:
        if not isinstance(raw_cell, list) or len(raw_cell) != 2:
            raise ValueError("manifest tile entry must be [cx, cy]: " + repr(raw_cell))
        cx = _as_int(raw_cell[0], "tile cx")
        cy = _as_int(raw_cell[1], "tile cy")
        tiles.append((cx, cy))
    sorted_tiles = sorted(tiles, key=lambda cell: (cell[0], cell[1]))
    if tiles != sorted_tiles:
        raise ValueError("manifest tiles must be sorted by (cx, cy)")
    if len(set(tiles)) != len(tiles):
        raise ValueError("manifest tiles contains duplicate cells")
    return tiles


def _require_sha_mapping(manifest: dict[str, Any], key: str, tiles: list[tuple[int, int]]) -> dict[str, str]:
    raw_mapping = manifest.get(key)
    if not isinstance(raw_mapping, dict):
        raise ValueError("manifest " + key + " must be an object")
    expected_keys = [_tile_key(cx, cy) for cx, cy in tiles]
    actual_keys = sorted((str(k) for k in raw_mapping.keys()), key=lambda k: tuple(int(p) for p in k.split('_')))
    if actual_keys != expected_keys:
        raise ValueError("manifest " + key + " keys do not match tiles")
    mapping: dict[str, str] = {}
    for tile_key in expected_keys:
        value = str(raw_mapping[tile_key])
        if SHA256_RE.fullmatch(value) is None:
            raise ValueError("manifest " + key + "." + tile_key + " must be a lowercase SHA-256")
        mapping[tile_key] = value
    return mapping


def _check_sha(path: Path, expected_sha: str) -> None:
    actual_sha = _sha256(path)
    if actual_sha != expected_sha:
        raise ValueError(_display_path(path) + " sha256 " + actual_sha + " != " + expected_sha)


def _require_string(data: dict[str, Any], key: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError("manifest " + key + " must be a non-empty string")
    return value


def _require_positive_int(data: dict[str, Any], key: str) -> int:
    value = _as_int(data.get(key), "manifest " + key)
    if value <= 0:
        raise ValueError("manifest " + key + " must be positive")
    return value


def _require_number(data: dict[str, Any], key: str) -> float:
    value = data.get(key)
    if not isinstance(value, (int, float)):
        raise ValueError("manifest " + key + " must be a number")
    return float(value)


def _require_equal(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise ValueError(label + " expected " + repr(expected) + ", got " + repr(actual))


def _as_int(value: Any, label: str) -> int:
    if not isinstance(value, int):
        raise ValueError(label + " must be an int")
    return value


def _resolve_path(path: Path) -> Path:
    if path.is_absolute():
        return path
    return ROOT / path


def _tile_key(cx: int, cy: int) -> str:
    return str(cx) + "_" + str(cy)


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
