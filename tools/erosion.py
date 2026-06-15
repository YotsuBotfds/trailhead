#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from math import cos, floor, pi, sin, sqrt
from typing import Sequence

import numpy as np

# Integration contract:
# - heightfield rows are world Z, columns are world X, both increasing.
# - bounds are either (x_min, z_min, x_max, z_max) or ((x_min, z_min), (x_max, z_max)).
# - hand-authored landmark/route shaping should be composited after this natural base pass.


BoundsLike = Sequence[float] | Sequence[Sequence[float]]


@dataclass(frozen=True)
class ErosionConfig:
    base_height: float = 0.0
    fbm_amplitude: float = 0.18
    fbm_base_feature_size: float = 5.0
    fbm_octaves: int = 5
    fbm_lacunarity: float = 2.05
    fbm_persistence: float = 0.48
    fbm_ridge_mix: float = 0.28
    hydraulic_droplets: int = 9000
    hydraulic_max_steps: int = 32
    hydraulic_inertia: float = 0.05
    hydraulic_capacity: float = 3.4
    hydraulic_min_capacity: float = 0.01
    hydraulic_deposit_rate: float = 0.22
    hydraulic_erode_rate: float = 0.18
    hydraulic_evaporation: float = 0.02
    hydraulic_gravity: float = 4.0
    hydraulic_initial_water: float = 1.0
    hydraulic_initial_speed: float = 1.0
    hydraulic_brush_radius: int = 3
    thermal_iterations: int = 8
    thermal_talus: float = 0.035
    thermal_rate: float = 0.18


def build_eroded_heightfield(
    width: int,
    height: int,
    bounds: BoundsLike,
    seed: int = 1,
    config: ErosionConfig | None = None,
) -> np.ndarray:
    """Build a deterministic eroded base terrain, returned as float32 [height, width]."""
    cfg = config or ErosionConfig()
    field = build_fbm_heightfield(width, height, bounds, seed=seed, config=cfg)
    field = hydraulic_erode(field, seed=seed + 1, config=cfg, inplace=True)
    field = thermal_erode(field, config=cfg, inplace=True)
    return field.astype(np.float32, copy=False)


def build_fbm_heightfield(
    width: int,
    height: int,
    bounds: BoundsLike,
    seed: int = 1,
    config: ErosionConfig | None = None,
) -> np.ndarray:
    """Build the seeded FBM/noise field used as the input to erosion."""
    _validate_grid_size(width, height)
    cfg = config or ErosionConfig()
    x_min, z_min, x_max, z_max = _normalize_bounds(bounds)
    rng = np.random.default_rng(seed)
    xs = np.linspace(x_min, x_max, width, dtype=np.float64)
    zs = np.linspace(z_min, z_max, height, dtype=np.float64)
    x_grid, z_grid = np.meshgrid(xs, zs)
    span = max(x_max - x_min, z_max - z_min)
    feature_size = max(cfg.fbm_base_feature_size, span / max(width, height))
    amplitude = 1.0
    amplitude_sum = 0.0
    noise = np.zeros((height, width), dtype=np.float64)

    for _octave in range(max(1, cfg.fbm_octaves)):
        octave = _value_noise_2d(x_grid, z_grid, x_min, z_min, x_max, z_max, feature_size, rng)
        ridged = 1.0 - np.abs(octave)
        ridged = ridged * 2.0 - 1.0
        octave = octave * (1.0 - cfg.fbm_ridge_mix) + ridged * cfg.fbm_ridge_mix
        noise += octave * amplitude
        amplitude_sum += amplitude
        amplitude *= cfg.fbm_persistence
        feature_size /= cfg.fbm_lacunarity

    if amplitude_sum > 0.0:
        noise /= amplitude_sum
    return cfg.base_height + noise * cfg.fbm_amplitude


def hydraulic_erode(
    heightfield: np.ndarray,
    seed: int = 2,
    config: ErosionConfig | None = None,
    inplace: bool = False,
) -> np.ndarray:
    """Apply deterministic row-major hydraulic droplet erosion."""
    cfg = config or ErosionConfig()
    field = _working_copy(heightfield, inplace)
    height, width = field.shape
    _validate_grid_size(width, height)
    rng = np.random.default_rng(seed)
    offsets, offset_weights = _erosion_brush_offsets(cfg.hydraulic_brush_radius)
    launch_width = max(1, width - 1)
    launch_height = max(1, height - 1)
    launch_count = launch_width * launch_height

    for droplet_index in range(max(0, cfg.hydraulic_droplets)):
        cell_index = droplet_index % launch_count
        z_cell = cell_index // launch_width
        x_cell = cell_index - z_cell * launch_width
        x = float(x_cell) + float(rng.random())
        z = float(z_cell) + float(rng.random())
        dir_x = 0.0
        dir_z = 0.0
        speed = cfg.hydraulic_initial_speed
        water = cfg.hydraulic_initial_water
        sediment = 0.0

        for _step in range(max(0, cfg.hydraulic_max_steps)):
            old_x = x
            old_z = z
            current_height, grad_x, grad_z = _height_and_gradient(field, x, z)
            dir_x = dir_x * cfg.hydraulic_inertia - grad_x * (1.0 - cfg.hydraulic_inertia)
            dir_z = dir_z * cfg.hydraulic_inertia - grad_z * (1.0 - cfg.hydraulic_inertia)
            length = sqrt(dir_x * dir_x + dir_z * dir_z)
            if length <= 1.0e-12:
                angle = float(rng.random()) * pi * 2.0
                dir_x = cos(angle)
                dir_z = sin(angle)
            else:
                dir_x /= length
                dir_z /= length

            x += dir_x
            z += dir_z
            if x < 0.0 or x >= float(width - 1) or z < 0.0 or z >= float(height - 1):
                break

            new_height, _new_grad_x, _new_grad_z = _height_and_gradient(field, x, z)
            delta_height = new_height - current_height
            capacity = max(-delta_height * speed * water * cfg.hydraulic_capacity, cfg.hydraulic_min_capacity)

            if sediment > capacity or delta_height > 0.0:
                deposit = delta_height if delta_height > 0.0 else (sediment - capacity) * cfg.hydraulic_deposit_rate
                deposit = min(max(deposit, 0.0), sediment)
                _deposit_bilinear(field, old_x, old_z, deposit)
                sediment -= deposit
            else:
                erosion = min((capacity - sediment) * cfg.hydraulic_erode_rate, max(-delta_height, 0.0))
                if erosion > 0.0:
                    eroded = _erode_brush(field, old_x, old_z, erosion, offsets, offset_weights)
                    sediment += eroded

            speed = sqrt(max(0.0, speed * speed - delta_height * cfg.hydraulic_gravity))
            water *= 1.0 - cfg.hydraulic_evaporation
            if water <= 1.0e-6:
                break

    return field


def thermal_erode(
    heightfield: np.ndarray,
    config: ErosionConfig | None = None,
    inplace: bool = False,
) -> np.ndarray:
    """Apply vectorized talus erosion using simultaneous four-neighbor transfers."""
    cfg = config or ErosionConfig()
    field = _working_copy(heightfield, inplace)
    _validate_grid_size(field.shape[1], field.shape[0])
    talus = max(0.0, cfg.thermal_talus)
    rate = min(max(cfg.thermal_rate, 0.0), 0.25)
    if rate <= 0.0:
        return field

    for _iteration in range(max(0, cfg.thermal_iterations)):
        delta = np.zeros_like(field)
        horizontal = _talus_transfer(field[:, :-1], field[:, 1:], talus, rate)
        delta[:, :-1] -= horizontal
        delta[:, 1:] += horizontal
        vertical = _talus_transfer(field[:-1, :], field[1:, :], talus, rate)
        delta[:-1, :] -= vertical
        delta[1:, :] += vertical
        field += delta
    return field


def sample_heightfield(heightfield: np.ndarray, bounds: BoundsLike, x, z):
    """Sample a heightfield at world X/Z by deterministic bilinear interpolation."""
    field = np.asarray(heightfield)
    if field.ndim != 2:
        raise ValueError("heightfield must be a 2D array")
    height, width = field.shape
    _validate_grid_size(width, height)
    x_min, z_min, x_max, z_max = _normalize_bounds(bounds)
    x_values = np.asarray(x, dtype=np.float64)
    z_values = np.asarray(z, dtype=np.float64)
    scalar = x_values.ndim == 0 and z_values.ndim == 0
    x_values, z_values = np.broadcast_arrays(x_values, z_values)
    x_index = (x_values - x_min) / (x_max - x_min) * float(width - 1)
    z_index = (z_values - z_min) / (z_max - z_min) * float(height - 1)
    samples = _sample_index_space(field.astype(np.float64, copy=False), x_index, z_index)
    if scalar:
        return float(samples)
    return samples


def resample_heightfield(
    heightfield: np.ndarray,
    source_bounds: BoundsLike,
    width: int,
    height: int,
    target_bounds: BoundsLike | None = None,
) -> np.ndarray:
    """Resample a source heightfield into a generator bake grid."""
    _validate_grid_size(width, height)
    bounds = target_bounds if target_bounds is not None else source_bounds
    x_min, z_min, x_max, z_max = _normalize_bounds(bounds)
    xs = np.linspace(x_min, x_max, width, dtype=np.float64)
    zs = np.linspace(z_min, z_max, height, dtype=np.float64)
    x_grid, z_grid = np.meshgrid(xs, zs)
    return sample_heightfield(heightfield, source_bounds, x_grid, z_grid).astype(np.float32)


def downsample_heightfield(heightfield: np.ndarray, width: int, height: int) -> np.ndarray:
    """Downsample by endpoint-aligned bilinear sampling in source index space."""
    field = np.asarray(heightfield, dtype=np.float64)
    if field.ndim != 2:
        raise ValueError("heightfield must be a 2D array")
    _validate_grid_size(width, height)
    source_height, source_width = field.shape
    _validate_grid_size(source_width, source_height)
    xs = np.linspace(0.0, float(source_width - 1), width, dtype=np.float64)
    zs = np.linspace(0.0, float(source_height - 1), height, dtype=np.float64)
    x_grid, z_grid = np.meshgrid(xs, zs)
    return _sample_index_space(field, x_grid, z_grid).astype(np.float32)


def _value_noise_2d(x_grid, z_grid, x_min, z_min, x_max, z_max, feature_size, rng):
    span_x = x_max - x_min
    span_z = z_max - z_min
    columns = max(2, int(np.ceil(span_x / feature_size)) + 2)
    rows = max(2, int(np.ceil(span_z / feature_size)) + 2)
    lattice = rng.uniform(-1.0, 1.0, size=(rows, columns))
    sx = np.clip((x_grid - x_min) / feature_size, 0.0, float(columns - 2))
    sz = np.clip((z_grid - z_min) / feature_size, 0.0, float(rows - 2))
    x0 = np.floor(sx).astype(np.int64)
    z0 = np.floor(sz).astype(np.int64)
    tx = _fade(sx - x0)
    tz = _fade(sz - z0)
    n00 = lattice[z0, x0]
    n10 = lattice[z0, x0 + 1]
    n01 = lattice[z0 + 1, x0]
    n11 = lattice[z0 + 1, x0 + 1]
    nx0 = n00 * (1.0 - tx) + n10 * tx
    nx1 = n01 * (1.0 - tx) + n11 * tx
    return nx0 * (1.0 - tz) + nx1 * tz


def _fade(value):
    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)


def _height_and_gradient(field: np.ndarray, x: float, z: float) -> tuple[float, float, float]:
    height, width = field.shape
    x0 = min(max(int(floor(x)), 0), width - 2)
    z0 = min(max(int(floor(z)), 0), height - 2)
    tx = x - float(x0)
    tz = z - float(z0)
    h00 = float(field[z0, x0])
    h10 = float(field[z0, x0 + 1])
    h01 = float(field[z0 + 1, x0])
    h11 = float(field[z0 + 1, x0 + 1])
    height_value = (h00 * (1.0 - tx) + h10 * tx) * (1.0 - tz) + (h01 * (1.0 - tx) + h11 * tx) * tz
    grad_x = (h10 - h00) * (1.0 - tz) + (h11 - h01) * tz
    grad_z = (h01 - h00) * (1.0 - tx) + (h11 - h10) * tx
    return height_value, grad_x, grad_z


def _deposit_bilinear(field: np.ndarray, x: float, z: float, amount: float) -> None:
    if amount <= 0.0:
        return
    height, width = field.shape
    x0 = min(max(int(floor(x)), 0), width - 2)
    z0 = min(max(int(floor(z)), 0), height - 2)
    tx = x - float(x0)
    tz = z - float(z0)
    field[z0, x0] += amount * (1.0 - tx) * (1.0 - tz)
    field[z0, x0 + 1] += amount * tx * (1.0 - tz)
    field[z0 + 1, x0] += amount * (1.0 - tx) * tz
    field[z0 + 1, x0 + 1] += amount * tx * tz


def _erode_brush(field, x, z, amount, offsets, offset_weights):
    center_x = min(max(int(floor(x)), 0), field.shape[1] - 1)
    center_z = min(max(int(floor(z)), 0), field.shape[0] - 1)
    weight_sum = 0.0
    for offset_index, (dx, dz) in enumerate(offsets):
        sample_x = center_x + dx
        sample_z = center_z + dz
        if sample_x < 0 or sample_x >= field.shape[1] or sample_z < 0 or sample_z >= field.shape[0]:
            continue
        weight_sum += float(offset_weights[offset_index])
    if weight_sum <= 0.0:
        return 0.0

    remaining = amount
    removed = 0.0
    for offset_index, (dx, dz) in enumerate(offsets):
        sample_x = center_x + dx
        sample_z = center_z + dz
        if sample_x < 0 or sample_x >= field.shape[1] or sample_z < 0 or sample_z >= field.shape[0]:
            continue
        weight = float(offset_weights[offset_index])
        target = amount * weight / weight_sum
        take = min(target, remaining)
        if take <= 0.0:
            continue
        field[sample_z, sample_x] -= take
        remaining -= take
        removed += take
        if remaining <= 0.0:
            break
    return removed


def _erosion_brush_offsets(radius: int):
    radius = max(0, int(radius))
    offsets = []
    weights = []
    if radius == 0:
        return [(0, 0)], np.array([1.0], dtype=np.float64)
    for dz in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            distance = sqrt(float(dx * dx + dz * dz))
            if distance <= float(radius):
                offsets.append((dx, dz))
                weights.append(max(0.0, float(radius) - distance))
    weight_array = np.asarray(weights, dtype=np.float64)
    if float(weight_array.sum()) <= 0.0:
        return [(0, 0)], np.array([1.0], dtype=np.float64)
    return offsets, weight_array


def _talus_transfer(a: np.ndarray, b: np.ndarray, talus: float, rate: float) -> np.ndarray:
    diff = a - b
    return np.where(diff > talus, (diff - talus) * rate, np.where(diff < -talus, (diff + talus) * rate, 0.0))


def _sample_index_space(field: np.ndarray, x_index, z_index):
    height, width = field.shape
    x = np.clip(x_index, 0.0, float(width - 1))
    z = np.clip(z_index, 0.0, float(height - 1))
    x0 = np.floor(x).astype(np.int64)
    z0 = np.floor(z).astype(np.int64)
    x0 = np.clip(x0, 0, width - 2)
    z0 = np.clip(z0, 0, height - 2)
    x1 = x0 + 1
    z1 = z0 + 1
    tx = x - x0
    tz = z - z0
    h00 = field[z0, x0]
    h10 = field[z0, x1]
    h01 = field[z1, x0]
    h11 = field[z1, x1]
    return (h00 * (1.0 - tx) + h10 * tx) * (1.0 - tz) + (h01 * (1.0 - tx) + h11 * tx) * tz


def _working_copy(heightfield: np.ndarray, inplace: bool) -> np.ndarray:
    field = np.asarray(heightfield, dtype=np.float64)
    if field.ndim != 2:
        raise ValueError("heightfield must be a 2D array")
    if inplace and field.flags.writeable:
        return field
    return np.array(field, dtype=np.float64, copy=True)


def _normalize_bounds(bounds: BoundsLike) -> tuple[float, float, float, float]:
    if len(bounds) == 4 and not isinstance(bounds[0], (tuple, list)):
        x_min, z_min, x_max, z_max = bounds
    elif len(bounds) == 2:
        first, second = bounds
        x_min, z_min = first
        x_max, z_max = second
    else:
        raise ValueError("bounds must be (x_min, z_min, x_max, z_max) or ((x_min, z_min), (x_max, z_max))")
    values = (float(x_min), float(z_min), float(x_max), float(z_max))
    if values[2] <= values[0] or values[3] <= values[1]:
        raise ValueError("bounds max values must be greater than min values")
    return values


def _validate_grid_size(width: int, height: int) -> None:
    if width < 2 or height < 2:
        raise ValueError("heightfields need at least 2x2 samples")


__all__ = [
    "ErosionConfig",
    "build_eroded_heightfield",
    "build_fbm_heightfield",
    "downsample_heightfield",
    "hydraulic_erode",
    "resample_heightfield",
    "sample_heightfield",
    "thermal_erode",
]
