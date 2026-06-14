#!/usr/bin/env python3
"""Generate deterministic render-only vehicle residue alpha masks."""

from __future__ import annotations

import math
import random
import argparse
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError as exc:  # pragma: no cover - local tooling guard.
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from exc


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = ROOT / "assets" / "textures" / "vehicle" / "residue"
SIZE = 256
WHEEL_SIZE = 160


def main() -> int:
    args = parse_args()
    output_dir = args.out_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    write_mask(output_dir, "mud_body_mask.png", body_mud_mask(SIZE, 4101))
    write_mask(output_dir, "dust_body_mask.png", body_dust_mask(SIZE, 4102))
    write_mask(output_dir, "wetness_body_mask.png", body_wetness_mask(SIZE, 4103))
    write_mask(output_dir, "mud_tire_mask.png", tire_mask(WHEEL_SIZE, 5101, 0.76, 34))
    write_mask(output_dir, "dust_tire_mask.png", tire_mask(WHEEL_SIZE, 5102, 0.55, 72))
    write_mask(output_dir, "wetness_tire_mask.png", tire_mask(WHEEL_SIZE, 5103, 0.48, 22))
    write_sources(output_dir)
    print("Wrote vehicle residue masks to", output_dir)
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def write_mask(output_dir: Path, name: str, alpha: Image.Image) -> None:
    image = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    image.putalpha(alpha)
    image.save(output_dir / name, optimize=True)


def body_mud_mask(size: int, seed: int) -> Image.Image:
    rng = random.Random(seed)
    alpha = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(alpha)
    for _index in range(56):
        x = rng.gauss(size * 0.48, size * 0.22)
        y = rng.gauss(size * 0.62, size * 0.24)
        radius_x = rng.uniform(size * 0.018, size * 0.095)
        radius_y = rng.uniform(size * 0.012, size * 0.07)
        opacity = round(rng.uniform(86.0, 225.0))
        draw.ellipse((x - radius_x, y - radius_y, x + radius_x, y + radius_y), fill=opacity)
    for _index in range(36):
        x = rng.uniform(size * 0.08, size * 0.92)
        y = rng.uniform(size * 0.18, size * 0.92)
        radius = rng.uniform(size * 0.004, size * 0.018)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=round(rng.uniform(96.0, 210.0)))
    alpha = alpha.filter(ImageFilter.GaussianBlur(size * 0.006))
    return add_edge_falloff(alpha, 0.88)


def body_dust_mask(size: int, seed: int) -> Image.Image:
    rng = random.Random(seed)
    alpha = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(alpha)
    for _index in range(210):
        x = rng.uniform(size * 0.04, size * 0.96)
        y = rng.uniform(size * 0.04, size * 0.96)
        radius = rng.uniform(size * 0.002, size * 0.014)
        opacity = round(rng.uniform(35.0, 175.0))
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=opacity)
    for _index in range(18):
        x = rng.uniform(size * 0.12, size * 0.88)
        y = rng.uniform(size * 0.08, size * 0.88)
        length = rng.uniform(size * 0.08, size * 0.28)
        width = rng.uniform(size * 0.005, size * 0.014)
        draw.rounded_rectangle((x, y, x + length, y + width), radius=width * 0.5, fill=round(rng.uniform(34.0, 92.0)))
    alpha = alpha.filter(ImageFilter.GaussianBlur(size * 0.004))
    return add_edge_falloff(alpha, 0.82)


def body_wetness_mask(size: int, seed: int) -> Image.Image:
    rng = random.Random(seed)
    alpha = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(alpha)
    for _index in range(22):
        x = rng.uniform(size * 0.12, size * 0.82)
        y = rng.uniform(size * 0.12, size * 0.82)
        width = rng.uniform(size * 0.09, size * 0.27)
        height = rng.uniform(size * 0.018, size * 0.06)
        opacity = round(rng.uniform(70.0, 170.0))
        draw.ellipse((x, y, x + width, y + height), fill=opacity)
    for _index in range(18):
        x = rng.uniform(size * 0.2, size * 0.82)
        y = rng.uniform(size * 0.08, size * 0.72)
        length = rng.uniform(size * 0.08, size * 0.22)
        width = rng.uniform(size * 0.004, size * 0.012)
        draw.rounded_rectangle((x, y, x + length, y + width), radius=width * 0.5, fill=round(rng.uniform(55.0, 130.0)))
    alpha = alpha.filter(ImageFilter.GaussianBlur(size * 0.008))
    return add_edge_falloff(alpha, 0.72)


def tire_mask(size: int, seed: int, ring_strength: float, speck_count: int) -> Image.Image:
    rng = random.Random(seed)
    center = (size - 1) * 0.5
    inner = size * 0.23
    outer = size * 0.47
    alpha = Image.new("L", (size, size), 0)
    pixels = alpha.load()
    for y in range(size):
        for x in range(size):
            dx = float(x) - center
            dy = float(y) - center
            radius = math.sqrt(dx * dx + dy * dy)
            if radius < inner or radius > outer:
                continue
            ring_t = (radius - inner) / (outer - inner)
            angular = math.atan2(dy, dx)
            tread = 0.5 + 0.5 * math.sin(angular * 14.0 + ring_t * 9.0)
            opacity = round((60.0 + 150.0 * tread * ring_strength) * (1.0 - abs(ring_t - 0.5) * 0.65))
            pixels[x, y] = max(pixels[x, y], opacity)
    draw = ImageDraw.Draw(alpha)
    for _index in range(speck_count):
        angle = rng.uniform(0.0, math.tau)
        radius = rng.uniform(inner, outer)
        x = center + math.cos(angle) * radius
        y = center + math.sin(angle) * radius
        dot = rng.uniform(size * 0.006, size * 0.025)
        draw.ellipse((x - dot, y - dot, x + dot, y + dot), fill=round(rng.uniform(90.0, 230.0)))
    return alpha.filter(ImageFilter.GaussianBlur(size * 0.003))


def add_edge_falloff(alpha: Image.Image, strength: float) -> Image.Image:
    size_x, size_y = alpha.size
    pixels = alpha.load()
    max_distance = min(size_x, size_y) * 0.5
    for y in range(size_y):
        for x in range(size_x):
            edge_distance = min(float(x), float(y), float(size_x - 1 - x), float(size_y - 1 - y))
            falloff = min(1.0, edge_distance / max_distance / (1.0 - strength * 0.45))
            pixels[x, y] = round(float(pixels[x, y]) * falloff)
    return alpha


def write_sources(output_dir: Path) -> None:
    (output_dir / "SOURCES.md").write_text(
        "\n".join([
            "# Vehicle Residue Texture Sources",
            "",
            "Generated by `tools/generate_vehicle_residue_textures.py`.",
            "",
            "- Source: deterministic procedural alpha masks authored for Trailhead.",
            "- License: project-owned generated output.",
            "- Purpose: render-only mud, dust, and wetness presentation driven by `VehicleState.contamination`.",
            "- These textures must not affect vehicle physics or surface selection.",
            "",
        ]),
        encoding="utf-8",
    )


if __name__ == "__main__":
    raise SystemExit(main())
