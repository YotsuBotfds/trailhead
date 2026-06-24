#!/usr/bin/env python3
"""Generate deterministic Zion ground material textures.

The outputs are render-only source textures for SurfaceVisualDef resources. The
generator avoids wall-clock data and Python hash state: each material has an
explicit seed and all texture features are periodic in UV space so the result
wraps cleanly.
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = ROOT / "assets" / "textures" / "surface_visuals" / "zion"
DEFAULT_SIZE = 1024
DEFAULT_DETAIL_SIZE = 512
NORMAL_Z = 1.0


@dataclass(frozen=True)
class SurfaceSpec:
    name: str
    label: str
    kind: str
    seed: int
    normal_strength: float
    detail_strength: float
    palette: tuple[tuple[int, int, int], ...]


SURFACES: tuple[SurfaceSpec, ...] = (
    SurfaceSpec(
        "packed_gravel_default",
        "rounded Virgin River cobble and packed gravel",
        "cobbles",
        1101,
        7.2,
        3.2,
        ((194, 171, 130), (167, 144, 111), (134, 126, 108), (211, 190, 151), (155, 102, 71)),
    ),
    SurfaceSpec(
        "paved_road_default",
        "dark asphalt with pale aggregate and hairline cracks",
        "asphalt",
        1102,
        2.2,
        1.8,
        ((48, 47, 44), (64, 62, 57), (84, 80, 72), (37, 36, 34), (118, 112, 98)),
    ),
    SurfaceSpec(
        "packed_dirt_default",
        "red-tan compacted trail dirt with small grit",
        "packed_dirt",
        1103,
        4.0,
        2.5,
        ((178, 117, 76), (151, 92, 58), (202, 150, 103), (126, 83, 59), (218, 185, 136)),
    ),
    SurfaceSpec(
        "pine_floor_dirt",
        "dry pine-floor dirt with needles and dusty tan soil",
        "pine_floor",
        1104,
        3.5,
        2.3,
        ((145, 113, 78), (184, 151, 103), (98, 80, 55), (198, 176, 128), (92, 62, 40)),
    ),
    SurfaceSpec(
        "sand_wash_default",
        "fine pink-tan rippled sand wash",
        "sand_ripple",
        1105,
        3.2,
        2.1,
        ((218, 176, 129), (230, 195, 150), (198, 133, 93), (238, 212, 172), (174, 98, 72)),
    ),
    SurfaceSpec(
        "tall_grass_default",
        "riparian grass mat with straw and green blade detail",
        "grass_mat",
        1106,
        3.1,
        2.8,
        ((105, 128, 61), (143, 154, 82), (184, 172, 102), (78, 103, 55), (210, 190, 123)),
    ),
    SurfaceSpec(
        "mud_default",
        "wet silty bank mud with shallow ruts",
        "wet_mud",
        1107,
        3.8,
        2.4,
        ((102, 82, 63), (76, 62, 51), (127, 102, 75), (67, 57, 48), (146, 120, 87)),
    ),
    SurfaceSpec(
        "dried_mud",
        "pale dried mud plates over silty wash sediment",
        "dried_mud",
        1108,
        4.4,
        2.9,
        ((198, 154, 104), (224, 190, 139), (156, 104, 74), (237, 210, 166), (178, 126, 85)),
    ),
    SurfaceSpec(
        "loose_rock_default",
        "angular sandstone talus and scree",
        "talus",
        1109,
        8.4,
        3.6,
        ((193, 144, 98), (150, 92, 66), (217, 177, 125), (117, 86, 70), (230, 203, 161)),
    ),
    SurfaceSpec(
        "wet_stone_default",
        "dark wet river-bank stone and cobbles",
        "wet_cobbles",
        1110,
        6.5,
        2.8,
        ((77, 83, 76), (93, 91, 79), (50, 57, 54), (124, 111, 88), (42, 47, 43)),
    ),
    SurfaceSpec(
        "slickrock_dry_default",
        "smooth dry Navajo sandstone slickrock",
        "slickrock",
        1111,
        2.7,
        2.0,
        ((214, 160, 105), (231, 194, 145), (186, 113, 80), (238, 218, 179), (151, 75, 57)),
    ),
    SurfaceSpec(
        "mossy_wet_stone",
        "mossy seep stone with dark rock and emerald patches",
        "mossy_stone",
        1112,
        5.3,
        3.0,
        ((61, 78, 58), (42, 52, 47), (80, 107, 60), (114, 111, 86), (38, 68, 42)),
    ),
    SurfaceSpec(
        "wood_plank_default",
        "aged trail boardwalk planks with sandy dust in seams",
        "wood_plank",
        1113,
        4.2,
        2.2,
        ((143, 102, 67), (184, 144, 98), (94, 66, 47), (211, 180, 128), (121, 86, 59)),
    ),
)


def main() -> int:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    for spec in SURFACES:
        albedo, height, detail_albedo, detail_height = render_surface(spec, args.size, args.detail_size)
        write_rgb(args.out_dir / f"{spec.name}_albedo.png", albedo)
        write_rgb(args.out_dir / f"{spec.name}_normal.png", normal_from_height(height, spec.normal_strength))
        write_l(args.out_dir / f"{spec.name}_height.png", height)
        write_rgb(args.out_dir / f"{spec.name}_detail_albedo.png", detail_albedo)
        write_rgb(args.out_dir / f"{spec.name}_detail_normal.png", normal_from_height(detail_height, spec.detail_strength))
    write_sources(args.out_dir, args.size, args.detail_size)
    print(f"Wrote {len(SURFACES)} Zion surface texture sets to {args.out_dir}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--detail-size", type=int, default=DEFAULT_DETAIL_SIZE)
    return parser.parse_args()


def render_surface(spec: SurfaceSpec, size: int, detail_size: int) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    rng = np.random.default_rng(spec.seed)
    x, y = uv_grid(size)
    detail_x, detail_y = uv_grid(detail_size)
    if spec.kind == "sand_ripple":
        albedo, height = sand_ripple(spec, rng, x, y)
    elif spec.kind == "packed_dirt":
        albedo, height = packed_dirt(spec, rng, x, y)
    elif spec.kind == "pine_floor":
        albedo, height = pine_floor(spec, rng, x, y)
    elif spec.kind == "cobbles":
        albedo, height = cobbles(spec, rng, x, y, count=125, small_count=180, wet=False)
    elif spec.kind == "wet_cobbles":
        albedo, height = cobbles(spec, rng, x, y, count=115, small_count=150, wet=True)
    elif spec.kind == "talus":
        albedo, height = talus(spec, rng, x, y)
    elif spec.kind == "slickrock":
        albedo, height = slickrock(spec, rng, x, y)
    elif spec.kind == "asphalt":
        albedo, height = asphalt(spec, rng, x, y)
    elif spec.kind == "grass_mat":
        albedo, height = grass_mat(spec, rng, x, y)
    elif spec.kind == "wet_mud":
        albedo, height = wet_mud(spec, rng, x, y)
    elif spec.kind == "dried_mud":
        albedo, height = dried_mud(spec, rng, x, y)
    elif spec.kind == "mossy_stone":
        albedo, height = mossy_stone(spec, rng, x, y)
    elif spec.kind == "wood_plank":
        albedo, height = wood_plank(spec, rng, x, y)
    else:
        albedo, height = generic_ground(spec, rng, x, y)
    detail_albedo, detail_height = render_detail(spec, rng, detail_x, detail_y)
    return albedo, height, detail_albedo, detail_height


def uv_grid(size: int) -> tuple[np.ndarray, np.ndarray]:
    axis = np.arange(size, dtype=np.float32) / np.float32(size)
    return np.meshgrid(axis, axis)


def periodic_noise(x: np.ndarray, y: np.ndarray, rng: np.random.Generator, count: int, min_frequency: int, max_frequency: int) -> np.ndarray:
    value = np.zeros_like(x, dtype=np.float32)
    weight = 0.0
    for index in range(count):
        kx = int(rng.integers(min_frequency, max_frequency + 1))
        ky = int(rng.integers(min_frequency, max_frequency + 1))
        if kx == 0 and ky == 0:
            kx = 1
        phase = np.float32(rng.uniform(0.0, math.tau))
        frequency_weight = 1.0 / math.sqrt(float(kx * kx + ky * ky + index + 1))
        amplitude = np.float32(rng.uniform(0.55, 1.0) * frequency_weight)
        value += np.sin(np.float32(math.tau) * (np.float32(kx) * x + np.float32(ky) * y) + phase) * amplitude
        value += np.cos(np.float32(math.tau) * (np.float32(ky) * x - np.float32(kx) * y) + phase * np.float32(0.73)) * amplitude * np.float32(0.35)
        weight += float(amplitude) * 1.35
    if weight <= 0.0:
        return value
    return value / np.float32(weight)


def normalize01(value: np.ndarray) -> np.ndarray:
    min_value = float(np.min(value))
    max_value = float(np.max(value))
    span = max(max_value - min_value, 1e-6)
    return np.clip((value - np.float32(min_value)) / np.float32(span), 0.0, 1.0)


def palette_array(spec: SurfaceSpec) -> np.ndarray:
    return np.asarray(spec.palette, dtype=np.float32)


def base_color(spec: SurfaceSpec, noise: np.ndarray) -> np.ndarray:
    palette = palette_array(spec)
    scaled = normalize01(noise) * np.float32(len(spec.palette) - 1)
    low = np.floor(scaled).astype(np.int32)
    high = np.minimum(low + 1, len(spec.palette) - 1)
    t = (scaled - low.astype(np.float32))[..., None]
    return palette[low] * (1.0 - t) + palette[high] * t


def wrap_delta(value: np.ndarray) -> np.ndarray:
    return ((value + np.float32(0.5)) % np.float32(1.0)) - np.float32(0.5)


def add_wrapped_stones(
    albedo: np.ndarray,
    height: np.ndarray,
    spec: SurfaceSpec,
    rng: np.random.Generator,
    count: int,
    radius_range: tuple[float, float],
    relief: float,
    angular: bool,
    dark_edges: bool,
) -> tuple[np.ndarray, np.ndarray]:
    x, y = uv_grid(height.shape[0])
    palette = palette_array(spec)
    stone_layer = np.zeros_like(height, dtype=np.float32)
    for _ in range(count):
        cx = np.float32(rng.uniform(0.0, 1.0))
        cy = np.float32(rng.uniform(0.0, 1.0))
        rx = np.float32(rng.uniform(radius_range[0], radius_range[1]))
        ry = np.float32(rx * rng.uniform(0.62, 1.45))
        angle = np.float32(rng.uniform(0.0, math.tau))
        ca = np.cos(angle)
        sa = np.sin(angle)
        dx = wrap_delta(x - cx)
        dy = wrap_delta(y - cy)
        lx = (dx * ca + dy * sa) / rx
        ly = (-dx * sa + dy * ca) / ry
        distance = np.sqrt(lx * lx + ly * ly)
        if angular:
            facet = np.maximum(np.abs(lx) * np.float32(0.82), np.abs(ly))
            distance = np.maximum(distance * np.float32(0.72), facet)
        mask = distance < np.float32(1.0)
        if not np.any(mask):
            continue
        dome = np.clip(1.0 - distance, 0.0, 1.0) ** np.float32(1.45 if angular else 1.85)
        facet_axis = np.float32(rng.uniform(-1.0, 1.0)) * lx + np.float32(rng.uniform(-1.0, 1.0)) * ly
        facet_ridge = np.clip(1.0 - np.abs(facet_axis), 0.0, 1.0) * np.float32(0.10 if angular else 0.035)
        stone_height = (dome + facet_ridge) * np.float32(relief)
        stone_layer = np.maximum(stone_layer, np.where(mask, stone_height, 0.0))
        color = palette[int(rng.integers(0, len(spec.palette)))].copy()
        color += rng.normal(0.0, 9.0, size=3).astype(np.float32)
        edge = smoothstep(0.74, 0.99, distance)[..., None]
        body = np.clip(dome[..., None] * np.float32(0.72) + np.float32(0.18), 0.0, 1.0)
        albedo = np.where(mask[..., None], albedo * (1.0 - body) + color * body, albedo)
        if dark_edges:
            albedo = np.where(mask[..., None], albedo * (1.0 - edge * np.float32(0.20)), albedo)
    height = normalize01(height * np.float32(0.48) + stone_layer)
    return np.clip(albedo, 0.0, 255.0), height


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - np.float32(edge0)) / np.float32(edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def sand_ripple(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    warp = periodic_noise(x, y, rng, 18, 1, 6) * np.float32(0.055)
    ripple_a = np.sin(np.float32(math.tau) * (np.float32(18.0) * x + np.float32(4.0) * y + warp))
    ripple_b = np.sin(np.float32(math.tau) * (np.float32(31.0) * x - np.float32(5.0) * y + warp * np.float32(0.7)))
    fine = periodic_noise(x, y, rng, 28, 8, 32)
    height = normalize01(ripple_a * np.float32(0.42) + ripple_b * np.float32(0.16) + fine * np.float32(0.25))
    albedo = base_color(spec, fine + ripple_a * np.float32(0.20))
    albedo += (height[..., None] - np.float32(0.5)) * np.float32(34.0)
    return np.clip(albedo, 0.0, 255.0), height


def packed_dirt(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    broad = periodic_noise(x, y, rng, 24, 1, 9)
    grit = periodic_noise(x, y, rng, 40, 12, 48)
    height = normalize01(broad * np.float32(0.42) + grit * np.float32(0.32))
    albedo = base_color(spec, broad * np.float32(0.85) + grit * np.float32(0.35))
    albedo, height = add_wrapped_stones(albedo, height, spec, rng, 90, (0.004, 0.014), 0.18, False, True)
    rut = smoothstep(0.88, 0.98, np.sin(np.float32(math.tau) * (y * np.float32(2.0) + periodic_noise(x, y, rng, 8, 1, 4) * np.float32(0.05))))
    height = normalize01(height - rut * np.float32(0.10))
    albedo *= (1.0 - rut[..., None] * np.float32(0.05))
    return np.clip(albedo, 0.0, 255.0), height


def pine_floor(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    soil = periodic_noise(x, y, rng, 22, 1, 12)
    height = normalize01(soil * np.float32(0.60) + periodic_noise(x, y, rng, 32, 10, 42) * np.float32(0.25))
    albedo = base_color(spec, soil)
    for _ in range(100):
        cx = np.float32(rng.uniform(0.0, 1.0))
        cy = np.float32(rng.uniform(0.0, 1.0))
        angle = np.float32(rng.uniform(0.0, math.tau))
        length = np.float32(rng.uniform(0.035, 0.090))
        width = np.float32(rng.uniform(0.0018, 0.0045))
        ca = np.cos(angle)
        sa = np.sin(angle)
        dx = wrap_delta(x - cx)
        dy = wrap_delta(y - cy)
        lx = (dx * ca + dy * sa) / length
        ly = (-dx * sa + dy * ca) / width
        needle = (np.abs(lx) < 1.0) & (np.abs(ly) < 1.0)
        color = np.asarray((88, 61, 36), dtype=np.float32) + rng.normal(0.0, 8.0, size=3).astype(np.float32)
        albedo = np.where(needle[..., None], albedo * np.float32(0.35) + color * np.float32(0.65), albedo)
        height = np.where(needle, np.maximum(height, np.float32(0.65)), height)
    return np.clip(albedo, 0.0, 255.0), normalize01(height)


def cobbles(
    spec: SurfaceSpec,
    rng: np.random.Generator,
    x: np.ndarray,
    y: np.ndarray,
    count: int,
    small_count: int,
    wet: bool,
) -> tuple[np.ndarray, np.ndarray]:
    base = periodic_noise(x, y, rng, 24, 1, 12)
    height = normalize01(base * np.float32(0.35))
    albedo = base_color(spec, base)
    albedo, height = add_wrapped_stones(albedo, height, spec, rng, count, (0.018, 0.052), 0.52, False, True)
    albedo, height = add_wrapped_stones(albedo, height, spec, rng, small_count, (0.004, 0.013), 0.16, False, False)
    if wet:
        dark = np.asarray((32, 37, 35), dtype=np.float32)
        wet_mask = normalize01(periodic_noise(x, y, rng, 16, 1, 9))
        albedo = albedo * np.float32(0.72) + dark * np.float32(0.18) + wet_mask[..., None] * np.float32(14.0)
    return np.clip(albedo, 0.0, 255.0), height


def talus(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    dust = periodic_noise(x, y, rng, 18, 1, 9)
    height = normalize01(dust * np.float32(0.30))
    albedo = base_color(spec, dust)
    albedo, height = add_wrapped_stones(albedo, height, spec, rng, 105, (0.018, 0.070), 0.78, True, True)
    albedo, height = add_wrapped_stones(albedo, height, spec, rng, 100, (0.004, 0.015), 0.20, True, False)
    shadow = normalize01(periodic_noise(x, y, rng, 12, 2, 8))
    albedo *= np.float32(0.86) + shadow[..., None] * np.float32(0.18)
    return np.clip(albedo, 0.0, 255.0), height


def slickrock(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    broad = periodic_noise(x, y, rng, 18, 1, 5)
    lamina = np.sin(np.float32(math.tau) * (x * np.float32(6.0) + y * np.float32(2.0) + broad * np.float32(0.18)))
    fine_lamina = np.sin(np.float32(math.tau) * (x * np.float32(26.0) + y * np.float32(9.0) + broad * np.float32(0.08)))
    height = normalize01(broad * np.float32(0.38) + lamina * np.float32(0.30) + fine_lamina * np.float32(0.08))
    albedo = base_color(spec, broad + lamina * np.float32(0.35))
    iron = smoothstep(0.58, 0.92, normalize01(fine_lamina + periodic_noise(x, y, rng, 8, 1, 5) * np.float32(0.4)))
    albedo = albedo * (1.0 - iron[..., None] * np.float32(0.16)) + np.asarray((153, 77, 57), dtype=np.float32) * iron[..., None] * np.float32(0.16)
    return np.clip(albedo, 0.0, 255.0), height


def asphalt(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    fine = periodic_noise(x, y, rng, 58, 12, 72)
    broad = periodic_noise(x, y, rng, 12, 1, 8)
    crack_noise = periodic_noise(x, y, rng, 10, 1, 5)
    crack_a = smoothstep(0.975, 0.995, np.sin(np.float32(math.tau) * (x * np.float32(2.0) + y * np.float32(1.0) + crack_noise * np.float32(0.16))))
    crack_b = smoothstep(0.982, 0.997, np.sin(np.float32(math.tau) * (x * np.float32(3.0) - y * np.float32(2.0) + crack_noise * np.float32(0.12))))
    cracks = np.maximum(crack_a, crack_b)
    height = normalize01(fine * np.float32(0.52) + broad * np.float32(0.15) - cracks * np.float32(0.52))
    albedo = base_color(spec, fine * np.float32(0.85) + broad * np.float32(0.25))
    aggregate = smoothstep(0.84, 0.98, normalize01(periodic_noise(x, y, rng, 48, 24, 96)))
    albedo += aggregate[..., None] * np.float32(42.0)
    albedo *= 1.0 - cracks[..., None] * np.float32(0.55)
    return np.clip(albedo, 0.0, 255.0), height


def grass_mat(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    clumps = periodic_noise(x, y, rng, 22, 1, 10)
    fine = periodic_noise(x, y, rng, 36, 8, 40)
    blade_flow = periodic_noise(x, y, rng, 8, 1, 4) * np.float32(0.085)
    blade_wave = np.sin(np.float32(math.tau) * (x * np.float32(28.0) + y * np.float32(5.0) + blade_flow))
    blades = smoothstep(0.48, 0.92, blade_wave) * smoothstep(0.32, 0.78, normalize01(clumps))
    straw = smoothstep(0.70, 0.94, normalize01(periodic_noise(x, y, rng, 20, 5, 28)))
    height = normalize01(clumps * np.float32(0.42) + blades * np.float32(0.42) + fine * np.float32(0.20))
    albedo = base_color(spec, clumps + fine * np.float32(0.35))
    albedo += blades[..., None] * np.asarray((6, 22, 0), dtype=np.float32)
    albedo += straw[..., None] * np.asarray((28, 18, -14), dtype=np.float32)
    return np.clip(albedo, 0.0, 255.0), height


def wet_mud(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    silt = periodic_noise(x, y, rng, 24, 1, 12)
    fine = periodic_noise(x, y, rng, 30, 10, 38)
    rut_warp = periodic_noise(x, y, rng, 8, 1, 5) * np.float32(0.08)
    ruts = smoothstep(0.70, 0.98, np.cos(np.float32(math.tau) * (x * np.float32(5.0) + rut_warp)))
    height = normalize01(silt * np.float32(0.42) + fine * np.float32(0.16) - ruts * np.float32(0.22))
    albedo = base_color(spec, silt)
    albedo = albedo * np.float32(0.72) + np.asarray((35, 31, 28), dtype=np.float32) * np.float32(0.18)
    albedo += fine[..., None] * np.float32(13.0)
    return np.clip(albedo, 0.0, 255.0), height


def dried_mud(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    silt = periodic_noise(x, y, rng, 18, 1, 9)
    plate = periodic_noise(x, y, rng, 26, 3, 16)
    cracks = smoothstep(0.62, 0.82, np.abs(plate))
    height = normalize01(silt * np.float32(0.30) + cracks * np.float32(0.22))
    albedo = base_color(spec, silt + plate * np.float32(0.22))
    albedo *= 1.0 - cracks[..., None] * np.float32(0.24)
    albedo += smoothstep(0.55, 0.85, silt)[..., None] * np.float32(18.0)
    return np.clip(albedo, 0.0, 255.0), height


def mossy_stone(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    albedo, height = cobbles(spec, rng, x, y, count=95, small_count=90, wet=True)
    moss_noise = normalize01(periodic_noise(x, y, rng, 18, 1, 10) + periodic_noise(x, y, rng, 14, 5, 18) * np.float32(0.45))
    moss = smoothstep(0.62, 0.90, moss_noise)
    moss_color = np.asarray((47, 91, 36), dtype=np.float32)
    albedo = albedo * (1.0 - moss[..., None] * np.float32(0.45)) + moss_color * moss[..., None] * np.float32(0.45)
    height = normalize01(height + moss * np.float32(0.18))
    return np.clip(albedo, 0.0, 255.0), height


def wood_plank(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    grain = periodic_noise(x, y, rng, 26, 2, 22)
    board_count = 5
    board_position = (x * np.float32(board_count)) % np.float32(1.0)
    seams = smoothstep(0.035, 0.0, board_position) + smoothstep(0.965, 1.0, board_position)
    long_grain = np.sin(np.float32(math.tau) * (y * np.float32(18.0) + grain * np.float32(0.18)))
    height = normalize01(grain * np.float32(0.28) + long_grain * np.float32(0.16) - seams * np.float32(0.52))
    albedo = base_color(spec, grain + long_grain * np.float32(0.25))
    albedo *= 1.0 - seams[..., None] * np.float32(0.46)
    dust = smoothstep(0.70, 0.94, normalize01(periodic_noise(x, y, rng, 18, 6, 26)))
    albedo += dust[..., None] * np.asarray((28, 20, 7), dtype=np.float32)
    return np.clip(albedo, 0.0, 255.0), height


def generic_ground(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    noise = periodic_noise(x, y, rng, 28, 1, 24)
    height = normalize01(noise)
    return np.clip(base_color(spec, noise), 0.0, 255.0), height


def render_detail(spec: SurfaceSpec, rng: np.random.Generator, x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    fine = periodic_noise(x, y, rng, 42, 12, 58)
    grain = periodic_noise(x, y, rng, 26, 4, 24)
    height = normalize01(fine * np.float32(0.62) + grain * np.float32(0.28))
    albedo = base_color(spec, fine * np.float32(0.5) + grain * np.float32(0.5))
    neutral = np.mean(palette_array(spec), axis=0)
    albedo = neutral * np.float32(0.62) + albedo * np.float32(0.38)
    albedo += (height[..., None] - np.float32(0.5)) * np.float32(28.0)
    return np.clip(albedo, 0.0, 255.0), height


def normal_from_height(height: np.ndarray, strength: float) -> np.ndarray:
    dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -dx * np.float32(strength)
    ny = -dy * np.float32(strength)
    nz = np.full_like(height, np.float32(NORMAL_Z))
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.empty((height.shape[0], height.shape[1], 3), dtype=np.float32)
    normal[..., 0] = np.float32(127.5) + np.float32(127.5) * nx / length
    normal[..., 1] = np.float32(127.5) + np.float32(127.5) * ny / length
    normal[..., 2] = np.float32(127.5) + np.float32(127.5) * nz / length
    return np.clip(normal, 0.0, 255.0)


def write_rgb(path: Path, image: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.rint(image).astype(np.uint8), mode="RGB").save(path, compress_level=6)


def write_l(path: Path, image: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.rint(np.clip(image, 0.0, 1.0) * 255.0).astype(np.uint8), mode="L").save(path, compress_level=6)


def write_sources(output_dir: Path, size: int, detail_size: int) -> None:
    rows = [
        "# Zion Surface Texture Sources",
        "",
        "Generated by `tools/gen_zion_surface_textures.py`.",
        "",
        "- Source: deterministic procedural tileable textures authored for Trailhead.",
        "- License: project-owned generated output.",
        "- Purpose: render-only Zion ground material source maps.",
        "- Determinism: explicit per-material seeds, periodic UV-space functions, no wall-clock or Python hash state.",
        f"- Base maps: {size}x{size} PNG albedo, normal, and height.",
        f"- Detail maps: {detail_size}x{detail_size} PNG albedo and normal.",
        "- These textures must not affect vehicle physics or surface selection.",
        "",
        "| Visual id | Target read | Seed |",
        "|---|---|---:|",
    ]
    for spec in SURFACES:
        rows.append(f"| `{spec.name}` | {spec.label} | {spec.seed} |")
    rows.append("")
    (output_dir / "SOURCES.md").write_text("\n".join(rows), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
