#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Any

import numpy as np


ROOT = Path(__file__).resolve().parents[3]
SPIKE_DIR = Path(__file__).resolve().parent
EROSION_MODULE_PATH = ROOT / "tools" / "erosion.py"

REGION_SEED = 20260615
TILE_COUNT_X = 2
TILE_COUNT_Z = 2
TILE_WORLD_SIZE = 8.0
TILE_INTERVALS = 32
TILE_SAMPLES = TILE_INTERVALS + 1
HALO_STEPS = 8
EXCHANGE_STEPS = 4
SAMPLE_SPACING = TILE_WORLD_SIZE / float(TILE_INTERVALS)
EXPANDED_INTERVALS = TILE_INTERVALS + HALO_STEPS * 2
EXPANDED_SAMPLES = EXPANDED_INTERVALS + 1
SEAM_THRESHOLD = 1.0e-7

BEFORE_ARRAY_PATH = "regional_bake_seams_before_exchange.npy"
AFTER_ARRAY_PATH = "regional_bake_seams_after_exchange.npy"
RESULTS_PATH = "regional_bake_seams_results.json"

MASK_64 = (1 << 64) - 1
UINT53_SCALE = 1.0 / float(1 << 53)


@dataclass(frozen=True)
class TileBake:
    tile_x: int
    tile_z: int
    expanded_field: np.ndarray


@dataclass(frozen=True)
class BakeRun:
    before_tiles: dict[tuple[int, int], np.ndarray]
    after_tiles: dict[tuple[int, int], np.ndarray]
    before_stats: dict[str, Any]
    after_stats: dict[str, Any]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Spike regional 2x2 terrain bakes with halo/ghost-cell seam exchange.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=SPIKE_DIR,
        help="Directory for small deterministic spike artifacts.",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=SEAM_THRESHOLD,
        help="Maximum accepted post-exchange seam height delta.",
    )
    return parser.parse_args()


def load_erosion_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("trailhead_erosion_reference", EROSION_MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load erosion module: {EROSION_MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def spike_erosion_config(erosion_module: ModuleType) -> Any:
    return erosion_module.ErosionConfig(
        base_height=-0.035,
        fbm_amplitude=0.18,
        fbm_base_feature_size=6.0,
        fbm_octaves=4,
        fbm_lacunarity=2.05,
        fbm_persistence=0.48,
        fbm_ridge_mix=0.25,
        hydraulic_droplets=256,
        hydraulic_max_steps=18,
        hydraulic_brush_radius=2,
        thermal_iterations=4,
    )


def splitmix64(value: int) -> int:
    value = (value + 0x9E3779B97F4A7C15) & MASK_64
    value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & MASK_64
    value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & MASK_64
    return (value ^ (value >> 31)) & MASK_64


def lattice_value(seed: int, x_index: int, z_index: int, octave: int) -> float:
    value = int(seed) & MASK_64
    value ^= (int(x_index) * 0x9E3779B185EBCA87) & MASK_64
    value ^= (int(z_index) * 0xC2B2AE3D27D4EB4F) & MASK_64
    value ^= (int(octave) * 0x165667B19E3779F9) & MASK_64
    hashed = splitmix64(value)
    return float((hashed >> 11) * UINT53_SCALE) * 2.0 - 1.0


def fade(value: float) -> float:
    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)


def lerp(a: float, b: float, weight: float) -> float:
    return a * (1.0 - weight) + b * weight


def world_value_noise(x_grid: np.ndarray, z_grid: np.ndarray, feature_size: float, seed: int, octave: int) -> np.ndarray:
    noise = np.empty_like(x_grid, dtype=np.float64)
    scaled_x = x_grid / feature_size
    scaled_z = z_grid / feature_size
    rows, columns = x_grid.shape
    for row in range(rows):
        for column in range(columns):
            sx = float(scaled_x[row, column])
            sz = float(scaled_z[row, column])
            x0 = int(np.floor(sx))
            z0 = int(np.floor(sz))
            tx = fade(sx - float(x0))
            tz = fade(sz - float(z0))
            n00 = lattice_value(seed, x0, z0, octave)
            n10 = lattice_value(seed, x0 + 1, z0, octave)
            n01 = lattice_value(seed, x0, z0 + 1, octave)
            n11 = lattice_value(seed, x0 + 1, z0 + 1, octave)
            nx0 = lerp(n00, n10, tx)
            nx1 = lerp(n01, n11, tx)
            noise[row, column] = lerp(nx0, nx1, tz)
    return noise


def build_world_fbm(bounds: tuple[float, float, float, float], seed: int, config: Any) -> np.ndarray:
    x_min, z_min, x_max, z_max = bounds
    xs = np.linspace(x_min, x_max, EXPANDED_SAMPLES, dtype=np.float64)
    zs = np.linspace(z_min, z_max, EXPANDED_SAMPLES, dtype=np.float64)
    x_grid, z_grid = np.meshgrid(xs, zs)
    feature_size = float(config.fbm_base_feature_size)
    amplitude = 1.0
    amplitude_sum = 0.0
    field = np.zeros((EXPANDED_SAMPLES, EXPANDED_SAMPLES), dtype=np.float64)

    for octave in range(max(1, int(config.fbm_octaves))):
        octave_noise = world_value_noise(x_grid, z_grid, feature_size, seed, octave)
        ridged = (1.0 - np.abs(octave_noise)) * 2.0 - 1.0
        octave_noise = octave_noise * (1.0 - config.fbm_ridge_mix) + ridged * config.fbm_ridge_mix
        field += octave_noise * amplitude
        amplitude_sum += amplitude
        amplitude *= config.fbm_persistence
        feature_size /= config.fbm_lacunarity

    if amplitude_sum > 0.0:
        field /= amplitude_sum
    return config.base_height + field * config.fbm_amplitude


def expanded_bounds(tile_x: int, tile_z: int) -> tuple[float, float, float, float]:
    tile_min_x = float(tile_x) * TILE_WORLD_SIZE
    tile_min_z = float(tile_z) * TILE_WORLD_SIZE
    halo_world = float(HALO_STEPS) * SAMPLE_SPACING
    return (
        tile_min_x - halo_world,
        tile_min_z - halo_world,
        tile_min_x + TILE_WORLD_SIZE + halo_world,
        tile_min_z + TILE_WORLD_SIZE + halo_world,
    )


def erosion_seed_for_tile(tile_x: int, tile_z: int) -> int:
    return REGION_SEED + tile_x * 1009 + tile_z * 9176 + 1


def bake_tile(tile_x: int, tile_z: int, erosion_module: ModuleType, config: Any) -> TileBake:
    base = build_world_fbm(expanded_bounds(tile_x, tile_z), REGION_SEED, config)
    eroded = erosion_module.hydraulic_erode(
        base,
        seed=erosion_seed_for_tile(tile_x, tile_z),
        config=config,
        inplace=False,
    )
    eroded = erosion_module.thermal_erode(eroded, config=config, inplace=True)
    return TileBake(tile_x, tile_z, eroded.astype(np.float32, copy=False))


def crop_final_tile(bake: TileBake) -> np.ndarray:
    row_start = HALO_STEPS
    column_start = HALO_STEPS
    return np.array(
        bake.expanded_field[row_start : row_start + TILE_SAMPLES, column_start : column_start + TILE_SAMPLES],
        dtype=np.float32,
        copy=True,
    )


def expanded_field_value_at(bake: TileBake, global_x_index: int, global_z_index: int) -> float | None:
    expanded_min_x_index = bake.tile_x * TILE_INTERVALS - HALO_STEPS
    expanded_min_z_index = bake.tile_z * TILE_INTERVALS - HALO_STEPS
    column = global_x_index - expanded_min_x_index
    row = global_z_index - expanded_min_z_index
    if column < 0 or column >= EXPANDED_SAMPLES or row < 0 or row >= EXPANDED_SAMPLES:
        return None
    return float(bake.expanded_field[row, column])


def internal_seam_indices(tile_count: int) -> list[int]:
    return [tile_index * TILE_INTERVALS for tile_index in range(1, tile_count)]


def in_exchange_band(global_x_index: int, global_z_index: int) -> bool:
    for seam_x in internal_seam_indices(TILE_COUNT_X):
        if abs(global_x_index - seam_x) <= EXCHANGE_STEPS:
            return True
    for seam_z in internal_seam_indices(TILE_COUNT_Z):
        if abs(global_z_index - seam_z) <= EXCHANGE_STEPS:
            return True
    return False


def apply_ghost_exchange(
    bakes: dict[tuple[int, int], TileBake],
    final_tiles: dict[tuple[int, int], np.ndarray],
) -> dict[tuple[int, int], np.ndarray]:
    exchanged = {key: np.array(value, dtype=np.float32, copy=True) for key, value in final_tiles.items()}
    ordered_bakes = [bakes[key] for key in sorted(bakes)]
    for tile_z in range(TILE_COUNT_Z):
        for tile_x in range(TILE_COUNT_X):
            tile_key = (tile_x, tile_z)
            tile = exchanged[tile_key]
            for row in range(TILE_SAMPLES):
                global_z_index = tile_z * TILE_INTERVALS + row
                for column in range(TILE_SAMPLES):
                    global_x_index = tile_x * TILE_INTERVALS + column
                    if not in_exchange_band(global_x_index, global_z_index):
                        continue
                    samples = [
                        value
                        for bake in ordered_bakes
                        if (value := expanded_field_value_at(bake, global_x_index, global_z_index)) is not None
                    ]
                    if len(samples) <= 1:
                        continue
                    tile[row, column] = np.float32(np.mean(samples, dtype=np.float64))
    return exchanged


def seam_stat(name: str, first: np.ndarray, second: np.ndarray) -> dict[str, Any]:
    diff = first.astype(np.float64) - second.astype(np.float64)
    abs_diff = np.abs(diff)
    return {
        "name": name,
        "samples": int(abs_diff.size),
        "max_abs": float(np.max(abs_diff)),
        "mean_abs": float(np.mean(abs_diff)),
        "rms": float(np.sqrt(np.mean(diff * diff))),
    }


def measure_seams(tiles: dict[tuple[int, int], np.ndarray]) -> dict[str, Any]:
    seams: list[dict[str, Any]] = []
    for tile_z in range(TILE_COUNT_Z):
        left = tiles[(0, tile_z)][:, -1]
        right = tiles[(1, tile_z)][:, 0]
        seams.append(seam_stat(f"vertical_x1_z{tile_z}", left, right))
    for tile_x in range(TILE_COUNT_X):
        top = tiles[(tile_x, 0)][-1, :]
        bottom = tiles[(tile_x, 1)][0, :]
        seams.append(seam_stat(f"horizontal_z1_x{tile_x}", top, bottom))

    max_abs = max(stat["max_abs"] for stat in seams)
    mean_abs = float(np.mean([stat["mean_abs"] for stat in seams]))
    rms = float(np.sqrt(np.mean([stat["rms"] * stat["rms"] for stat in seams])))
    return {
        "max_abs": float(max_abs),
        "mean_abs": mean_abs,
        "rms": rms,
        "seams": seams,
    }


def build_run() -> BakeRun:
    erosion_module = load_erosion_module()
    config = spike_erosion_config(erosion_module)
    bakes: dict[tuple[int, int], TileBake] = {}
    for tile_z in range(TILE_COUNT_Z):
        for tile_x in range(TILE_COUNT_X):
            bakes[(tile_x, tile_z)] = bake_tile(tile_x, tile_z, erosion_module, config)

    before_tiles = {key: crop_final_tile(value) for key, value in bakes.items()}
    after_tiles = apply_ghost_exchange(bakes, before_tiles)
    return BakeRun(
        before_tiles=before_tiles,
        after_tiles=after_tiles,
        before_stats=measure_seams(before_tiles),
        after_stats=measure_seams(after_tiles),
    )


def ordered_tile_stack(tiles: dict[tuple[int, int], np.ndarray]) -> np.ndarray:
    ordered = [tiles[(tile_x, tile_z)] for tile_z in range(TILE_COUNT_Z) for tile_x in range(TILE_COUNT_X)]
    return np.ascontiguousarray(np.stack(ordered, axis=0).astype(np.float32, copy=False))


def stats_bytes(run: BakeRun) -> bytes:
    return json.dumps(
        {
            "after_stats": run.after_stats,
            "before_stats": run.before_stats,
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def array_bytes(run: BakeRun) -> bytes:
    return (
        ordered_tile_stack(run.before_tiles).tobytes(order="C")
        + ordered_tile_stack(run.after_tiles).tobytes(order="C")
    )


def hash_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def result_payload(first: BakeRun, second: BakeRun, threshold: float) -> dict[str, Any]:
    first_array_bytes = array_bytes(first)
    second_array_bytes = array_bytes(second)
    first_stats_bytes = stats_bytes(first)
    second_stats_bytes = stats_bytes(second)
    byte_equal = first_array_bytes == second_array_bytes
    stats_equal = first_stats_bytes == second_stats_bytes
    post_exchange_pass = first.after_stats["max_abs"] <= threshold
    return {
        "hypothesis": "Regional offline bakes can produce deterministic, seam-continuous tiles using seeded erosion with halo/ghost-cell exchange.",
        "config": {
            "numpy_version": np.__version__,
            "region_seed": REGION_SEED,
            "tile_count": [TILE_COUNT_X, TILE_COUNT_Z],
            "tile_world_size": TILE_WORLD_SIZE,
            "tile_samples": TILE_SAMPLES,
            "halo_steps": HALO_STEPS,
            "exchange_steps": EXCHANGE_STEPS,
            "sample_spacing": SAMPLE_SPACING,
            "seam_threshold": threshold,
        },
        "baseline_without_exchange": first.before_stats,
        "after_ghost_exchange": first.after_stats,
        "determinism": {
            "array_bytes_equal": byte_equal,
            "stats_equal": stats_equal,
            "array_sha256": hash_bytes(first_array_bytes),
            "stats_sha256": hash_bytes(first_stats_bytes),
        },
        "pass": bool(post_exchange_pass and byte_equal and stats_equal),
    }


def write_artifacts(output_dir: Path, run: BakeRun, payload: dict[str, Any]) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    before_path = output_dir / BEFORE_ARRAY_PATH
    after_path = output_dir / AFTER_ARRAY_PATH
    results_path = output_dir / RESULTS_PATH
    np.save(before_path, ordered_tile_stack(run.before_tiles))
    np.save(after_path, ordered_tile_stack(run.after_tiles))
    results_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return [before_path, after_path, results_path]


def print_summary(payload: dict[str, Any], artifacts: list[Path]) -> None:
    print("regional bake seam spike")
    print(
        "grid: "
        f"{TILE_COUNT_X}x{TILE_COUNT_Z} tiles, "
        f"{TILE_SAMPLES}x{TILE_SAMPLES} samples/tile, "
        f"halo={HALO_STEPS}, exchange={EXCHANGE_STEPS}"
    )
    print(f"baseline max seam delta: {payload['baseline_without_exchange']['max_abs']:.9g}")
    print(f"after exchange max seam delta: {payload['after_ghost_exchange']['max_abs']:.9g}")
    print(f"threshold: {payload['config']['seam_threshold']:.9g}")
    print(
        "determinism: "
        f"array_bytes_equal={payload['determinism']['array_bytes_equal']} "
        f"stats_equal={payload['determinism']['stats_equal']}"
    )
    print(f"pass: {payload['pass']}")
    for path in artifacts:
        print(f"wrote: {path}")


def main() -> int:
    args = parse_args()
    first = build_run()
    second = build_run()
    payload = result_payload(first, second, args.threshold)
    artifacts = write_artifacts(args.output_dir, first, payload)
    print_summary(payload, artifacts)
    return 0 if payload["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
