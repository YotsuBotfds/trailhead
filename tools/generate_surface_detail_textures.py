#!/usr/bin/env python3
"""Generate deterministic render-only terrain detail textures."""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover - local tooling guard.
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from exc


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = ROOT / "assets" / "textures" / "surface_visuals" / "generated"
SIZE = 256
DETAIL_SEED = 8201
WAVE_COUNT = 24
NORMAL_STRENGTH = 1.65


def main() -> int:
    args = parse_args()
    output_dir = args.out_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    waves = _detail_waves(DETAIL_SEED)
    height_values = _height_values(SIZE, waves)
    _write_albedo(output_dir / "terrain_detail_albedo.png", height_values)
    _write_normal(output_dir / "terrain_detail_normal.png", height_values)
    _write_mask(output_dir / "terrain_detail_mask.png", height_values)
    _write_sources(output_dir)
    print("Wrote surface detail textures to", output_dir)
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def _detail_waves(seed: int) -> list[tuple[int, int, float, float]]:
    rng = random.Random(seed)
    waves: list[tuple[int, int, float, float]] = []
    for index in range(WAVE_COUNT):
        frequency_x = rng.randint(1, 13)
        frequency_y = rng.randint(1, 13)
        if frequency_x == frequency_y:
            frequency_y += 1
        phase = rng.uniform(0.0, math.tau)
        amplitude = rng.uniform(0.12, 1.0) / math.sqrt(float(index + 1))
        waves.append((frequency_x, frequency_y, phase, amplitude))
    return waves


def _height_values(size: int, waves: list[tuple[int, int, float, float]]) -> list[list[float]]:
    values: list[list[float]] = []
    min_value = 9999.0
    max_value = -9999.0
    denominator = float(size - 1)
    for y in range(size):
        row: list[float] = []
        v = float(y) / denominator
        for x in range(size):
            u = float(x) / denominator
            value = _sample_detail(u, v, waves)
            min_value = min(min_value, value)
            max_value = max(max_value, value)
            row.append(value)
        values.append(row)
    span = max_value - min_value
    for y in range(size):
        for x in range(size):
            values[y][x] = (values[y][x] - min_value) / span
    return values


def _sample_detail(u: float, v: float, waves: list[tuple[int, int, float, float]]) -> float:
    value = 0.0
    for frequency_x, frequency_y, phase, amplitude in waves:
        angle = math.tau * (float(frequency_x) * u + float(frequency_y) * v) + phase
        value += math.sin(angle) * amplitude
        value += math.cos(angle * 0.5 + phase * 0.37) * amplitude * 0.35
    ridges = math.sin(math.tau * (u * 17.0 + v * 11.0)) * math.sin(math.tau * (u * 5.0 - v * 7.0))
    return value + ridges * 0.18


def _write_albedo(path: Path, height_values: list[list[float]]) -> None:
    size = len(height_values)
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            value = height_values[y][x]
            grit = round((value - 0.5) * 28.0)
            pixels[x, y] = (
                _byte(232 + grit),
                _byte(230 + round(grit * 0.85)),
                _byte(224 + round(grit * 0.65)),
            )
    image.save(path, optimize=True)


def _write_normal(path: Path, height_values: list[list[float]]) -> None:
    size = len(height_values)
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    last = size - 1
    for y in range(size):
        y0 = y - 1 if y > 0 else last - 1
        y1 = y + 1 if y < last else 1
        for x in range(size):
            x0 = x - 1 if x > 0 else last - 1
            x1 = x + 1 if x < last else 1
            dx = (height_values[y][x1] - height_values[y][x0]) * NORMAL_STRENGTH
            dy = (height_values[y1][x] - height_values[y0][x]) * NORMAL_STRENGTH
            nx = -dx
            ny = -dy
            nz = 1.0
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            pixels[x, y] = (
                _byte(128.0 + 127.0 * nx / length),
                _byte(128.0 + 127.0 * ny / length),
                _byte(128.0 + 127.0 * nz / length),
            )
    image.save(path, optimize=True)


def _write_mask(path: Path, height_values: list[list[float]]) -> None:
    size = len(height_values)
    image = Image.new("L", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            value = height_values[y][x]
            pixels[x, y] = _byte(122.0 + 118.0 * value)
    image.save(path, optimize=True)


def _byte(value: float) -> int:
    return round(min(255.0, max(0.0, value)))


def _write_sources(output_dir: Path) -> None:
    (output_dir / "SOURCES.md").write_text(
        "\n".join([
            "# Surface Detail Texture Sources",
            "",
            "Generated by `tools/generate_surface_detail_textures.py`.",
            "",
            "- Source: deterministic procedural tileable textures authored for Trailhead.",
            "- License: project-owned generated output.",
            "- Purpose: render-only terrain material detail layers.",
            "- These textures must not affect vehicle physics or surface selection.",
            "",
        ]),
        encoding="utf-8",
    )


if __name__ == "__main__":
    raise SystemExit(main())
