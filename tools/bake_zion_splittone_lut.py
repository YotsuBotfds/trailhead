#!/usr/bin/env python3
"""Bake Trailhead's subtle Zion split-tone 3D LUT.

Godot's Texture3D importer reconstructs this PNG as a 16x16x16 cube by
splitting it into 16 horizontal slices. Each slice is 16x16 pixels; slices
advance left-to-right along blue, columns are red, and rows are green.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "assets" / "textures" / "grade" / "zion_splittone_lut.png"

LUT_SIZE = 16
LUMA_WEIGHTS = np.array([0.2126, 0.7152, 0.0722], dtype=np.float64)
SHADOW_COOL_TARGET = np.array([0.42, 0.50, 0.62], dtype=np.float64)
HIGHLIGHT_WARM_TARGET = np.array([1.00, 0.86, 0.62], dtype=np.float64)
SHADOW_MAX_SHIFT = 0.075
HIGHLIGHT_MAX_SHIFT = 0.065
MAX_CHROMA_EXTRA = 0.012


def _smoothstep(edge0: float, edge1: float, value: float) -> float:
    t = np.clip((value - edge0) / (edge1 - edge0), 0.0, 1.0)
    return float(t * t * (3.0 - 2.0 * t))


def _luma(color: np.ndarray) -> float:
    return float(np.dot(color, LUMA_WEIGHTS))


def _luma_matched_target(target: np.ndarray, source_luma: float) -> np.ndarray:
    target_luma = _luma(target)
    if target_luma <= 0.0:
        return target.copy()
    return target * (source_luma / target_luma)


def _fit_in_gamut(source: np.ndarray, graded: np.ndarray) -> np.ndarray:
    delta = graded - source
    scale = 1.0
    for channel in range(3):
        if delta[channel] > 0.0:
            scale = min(scale, (1.0 - source[channel]) / delta[channel])
        elif delta[channel] < 0.0:
            scale = min(scale, -source[channel] / delta[channel])
    return source + delta * max(0.0, scale)


def _cap_chroma(source: np.ndarray, graded: np.ndarray, tint_weight: float) -> np.ndarray:
    source_luma = _luma(source)
    source_chroma = source - source_luma
    graded_chroma = graded - source_luma
    source_chroma_length = float(np.linalg.norm(source_chroma))
    graded_chroma_length = float(np.linalg.norm(graded_chroma))
    allowed_chroma = source_chroma_length * 1.005 + MAX_CHROMA_EXTRA * tint_weight
    if graded_chroma_length <= allowed_chroma or graded_chroma_length <= 0.0:
        return graded
    return source_luma + graded_chroma * (allowed_chroma / graded_chroma_length)


def grade_color(source: np.ndarray) -> np.ndarray:
    source_luma = _luma(source)
    shadow_weight = 1.0 - _smoothstep(0.14, 0.52, source_luma)
    highlight_weight = _smoothstep(0.50, 0.92, source_luma)
    shadow_amount = shadow_weight * SHADOW_MAX_SHIFT
    highlight_amount = highlight_weight * HIGHLIGHT_MAX_SHIFT

    graded = source.copy()
    if shadow_amount > 0.0:
        cool_target = _luma_matched_target(SHADOW_COOL_TARGET, source_luma)
        graded = graded * (1.0 - shadow_amount) + cool_target * shadow_amount
    if highlight_amount > 0.0:
        warm_target = _luma_matched_target(HIGHLIGHT_WARM_TARGET, source_luma)
        graded = graded * (1.0 - highlight_amount) + warm_target * highlight_amount

    graded += source_luma - _luma(graded)
    graded = _cap_chroma(source, graded, max(shadow_weight, highlight_weight))
    graded += source_luma - _luma(graded)
    return _fit_in_gamut(source, graded)


def bake_lut(size: int) -> np.ndarray:
    pixels = np.zeros((size, size * size, 3), dtype=np.uint8)
    scale = float(size - 1)
    for blue_index in range(size):
        b = blue_index / scale
        for green_index in range(size):
            g = green_index / scale
            for red_index in range(size):
                r = red_index / scale
                source = np.array([r, g, b], dtype=np.float64)
                graded = grade_color(source)
                x = blue_index * size + red_index
                y = green_index
                pixels[y, x] = np.rint(np.clip(graded, 0.0, 1.0) * 255.0).astype(np.uint8)
    return pixels


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT, help="PNG output path")
    args = parser.parse_args()

    output_path = args.out
    if not output_path.is_absolute():
        output_path = ROOT / output_path
    output_path.parent.mkdir(parents=True, exist_ok=True)

    image = Image.fromarray(bake_lut(LUT_SIZE), mode="RGB")
    image.save(output_path, format="PNG", compress_level=9, optimize=False)
    try:
        display_path = output_path.relative_to(ROOT)
    except ValueError:
        display_path = output_path
    print(f"wrote {display_path} ({LUT_SIZE} horizontal 16x16 slices)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
