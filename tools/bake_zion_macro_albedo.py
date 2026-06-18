#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
GAME_CONFIG_PATH = ROOT / "autoload/game_config.gd"
TERRAIN_DEF_PATH = ROOT / "data/terrain/cedar_hollow_zion_terrain_def.tres"
SURFACE_ID_MANIFEST_PATH = ROOT / "data/bake_inputs/zion_naip_2021/zion_naip_surface_id_manifest.json"
NAIP_INPUT_PATH = ROOT / "data/bake_inputs/zion_naip_2021/zion_naip_2021_corridor_rgbn_1m.tif"
MACRO_ALBEDO_PNG_PATH = ROOT / "data/terrain/cedar_hollow_zion_macro_albedo.png"
MACRO_ALBEDO_MANIFEST_PATH = ROOT / "data/terrain/cedar_hollow_zion_macro_albedo_manifest.json"
NAIP_SERVICE_URL = "https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer"
EXPECTED_CRS = "EPSG:32612"
CELL_SPACING_M = 1.0

TARGET_WIDTH = 256
GAUSSIAN_SIGMA = 1.5
GAUSSIAN_TRUNCATE = 3.0
DESATURATE_KEEP = 0.6
BRIGHTNESS_TARGET = 128.0
BRIGHTNESS_SCALE_MIN = 0.85
BRIGHTNESS_SCALE_MAX = 1.18
LUMA_COEF_REC709 = (0.2126, 0.7152, 0.0722)


@dataclass(frozen=True)
class MacroAlbedoConfig:
    origin_easting: float
    origin_northing: float
    tile_cols: int
    tile_rows: int
    tile_size_m: float
    surface_width: int
    surface_height: int

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
    def tile_bounds(self) -> tuple[float, float, float, float]:
        return (
            self.origin_easting,
            self.origin_northing,
            self.tile_max_easting,
            self.tile_max_northing,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bake the Cedar Hollow Zion de-lit macro-albedo PNG from the real NAIP aerial RGB."
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    try:
        _assert_python_deps()
        config = _load_config()
        args = parse_args()
        target_height = _proportional_height(config)
        gaussian_radius = _gaussian_radius()
        if args.dry_run:
            print("ok: zion macro-albedo dry-run")
            print("naip_input: " + str(NAIP_INPUT_PATH.relative_to(ROOT)))
            print("macro_albedo_png: " + str(MACRO_ALBEDO_PNG_PATH.relative_to(ROOT)))
            print("macro_albedo_size: " + str(TARGET_WIDTH) + "x" + str(target_height))
            print("gaussian_sigma: " + str(GAUSSIAN_SIGMA))
            print("gaussian_radius: " + str(gaussian_radius))
            print("desaturate_keep: " + str(DESATURATE_KEEP))
            print("brightness_target: " + str(BRIGHTNESS_TARGET))
            return 0
        rgb, input_stats, naip_year = _read_naip_rgb(config)
        downsampled, downsample_stats = _downsample_box_mean(rgb, TARGET_WIDTH, target_height)
        blurred = _gaussian_blur(downsampled, GAUSSIAN_SIGMA, GAUSSIAN_TRUNCATE)
        final, output_stats = _delit_adjust(blurred)
        _write_png_rgb8(MACRO_ALBEDO_PNG_PATH, final)
        manifest = _write_manifest(
            config, naip_year, target_height, gaussian_radius, input_stats, downsample_stats, output_stats
        )
    except Exception as exc:
        print("fail: " + str(exc), file=sys.stderr)
        return 1
    print("ok: zion macro-albedo PNG")
    print("naip_input: " + str(NAIP_INPUT_PATH.relative_to(ROOT)))
    print("macro_albedo_png: " + str(MACRO_ALBEDO_PNG_PATH.relative_to(ROOT)))
    print("manifest: " + str(MACRO_ALBEDO_MANIFEST_PATH.relative_to(ROOT)))
    print("macro_albedo_size: " + str(TARGET_WIDTH) + "x" + str(target_height))
    print("brightness_scale_applied: " + str(output_stats["brightness_scale_applied"]))
    return 0


def _assert_python_deps() -> None:
    import numpy as np
    from PIL import Image

    if np.dtype("float32").itemsize != 4:
        raise RuntimeError("numpy float32 is not 32-bit")
    if not Image.__version__:
        raise RuntimeError("Pillow version is empty")


def _load_config() -> MacroAlbedoConfig:
    game_config = GAME_CONFIG_PATH.read_text(encoding="utf-8")
    terrain_def = TERRAIN_DEF_PATH.read_text(encoding="utf-8")
    surface_width, surface_height = _parse_vector2i(_field(terrain_def, "surface_map_size"))
    return MacroAlbedoConfig(
        origin_easting=_const_float(game_config, "ZION_CORRIDOR_UTM_ORIGIN_E"),
        origin_northing=_const_float(game_config, "ZION_CORRIDOR_UTM_ORIGIN_N"),
        tile_cols=_const_int(game_config, "ZION_CORRIDOR_TILE_COLS"),
        tile_rows=_const_int(game_config, "ZION_CORRIDOR_TILE_ROWS"),
        tile_size_m=_const_float(game_config, "STREAM_TILE_SIZE_M"),
        surface_width=surface_width,
        surface_height=surface_height,
    )


def _proportional_height(config: MacroAlbedoConfig) -> int:
    ratio = float(config.surface_height) / float(config.surface_width)
    return int(round(float(TARGET_WIDTH) * ratio))


def _gaussian_radius() -> int:
    return int(math.ceil(GAUSSIAN_TRUNCATE * GAUSSIAN_SIGMA))


def _read_naip_rgb(config: MacroAlbedoConfig):
    import numpy as np
    from PIL import Image

    if not NAIP_INPUT_PATH.is_file():
        raise FileNotFoundError(
            "NAIP corridor mosaic is missing: "
            + str(NAIP_INPUT_PATH.relative_to(ROOT))
            + " — run tools/bake_zion_surface_id_png.py first to download + align it."
        )
    Image.MAX_IMAGE_PIXELS = None
    with Image.open(NAIP_INPUT_PATH) as img:
        if img.size != (config.surface_width, config.surface_height):
            raise ValueError(
                "NAIP input dimensions "
                + str(img.size)
                + " do not match surface map size "
                + str((config.surface_width, config.surface_height))
            )
        rgba = np.asarray(img)
    if rgba.ndim != 3 or rgba.shape[2] != 4:
        raise ValueError("NAIP input must be a 4-band image, got shape " + str(rgba.shape))
    if rgba.dtype != np.uint8:
        raise ValueError("NAIP input must be uint8, got " + str(rgba.dtype))
    rgb = rgba[:, :, :3].astype(np.float32)
    stats = {
        "input_rgb_min": [int(v) for v in rgb.min(axis=(0, 1))],
        "input_rgb_max": [int(v) for v in rgb.max(axis=(0, 1))],
        "input_rgb_mean": [float(v) for v in rgb.mean(axis=(0, 1))],
    }
    naip_year = _resolve_naip_year()
    return rgb, stats, naip_year


def _resolve_naip_year() -> int:
    if SURFACE_ID_MANIFEST_PATH.is_file():
        data = json.loads(SURFACE_ID_MANIFEST_PATH.read_text(encoding="utf-8"))
        year = data.get("selected_year")
        if isinstance(year, int):
            return year
    return 2021


def _bin_bounds(n_in: int, n_out: int) -> list[tuple[int, int]]:
    bounds: list[tuple[int, int]] = []
    prev = 0
    for k in range(1, n_out + 1):
        stop = (k * n_in) // n_out
        if stop <= prev:
            stop = prev + 1
        bounds.append((prev, stop))
        prev = stop
    if prev < n_in:
        lo, _ = bounds[-1]
        bounds[-1] = (lo, n_in)
    elif prev > n_in:
        raise ValueError("bin bounds overshot input extent")
    return bounds


def _downsample_box_mean(rgb, out_w: int, out_h: int):
    import numpy as np

    in_h, in_w = rgb.shape[:2]
    sat = np.zeros((in_h + 1, in_w + 1, 3), dtype=np.float64)
    sat[1:, 1:] = rgb.cumsum(axis=0).cumsum(axis=1)
    row_bounds = _bin_bounds(in_h, out_h)
    col_bounds = _bin_bounds(in_w, out_w)
    out = np.empty((out_h, out_w, 3), dtype=np.float32)
    for oy, (r0, r1) in enumerate(row_bounds):
        for ox, (c0, c1) in enumerate(col_bounds):
            block_sum = sat[r1, c1] - sat[r0, c1] - sat[r1, c0] + sat[r0, c0]
            count = float((r1 - r0) * (c1 - c0))
            out[oy, ox] = (block_sum / count).astype(np.float32)
    stats = {
        "row_bin_widths": sorted({hi - lo for lo, hi in row_bounds}),
        "col_bin_widths": sorted({hi - lo for lo, hi in col_bounds}),
    }
    return out, stats


def _gaussian_kernel_1d(sigma: float, radius: int):
    import numpy as np

    xs = np.arange(-radius, radius + 1, dtype=np.float64)
    kernel = np.exp(-(xs * xs) / (2.0 * sigma * sigma))
    kernel /= kernel.sum()
    return kernel.astype(np.float32)


def _gaussian_blur(arr, sigma: float, truncate: float):
    import numpy as np

    radius = int(math.ceil(truncate * sigma))
    kernel = _gaussian_kernel_1d(sigma, radius)
    h, w = arr.shape[:2]
    pad = radius
    padded_h = np.pad(arr, ((0, 0), (pad, pad), (0, 0)), mode="reflect")
    tmp = np.zeros_like(arr)
    for offset, weight in enumerate(kernel):
        tmp = tmp + weight * padded_h[:, offset:offset + w, :]
    padded_v = np.pad(tmp, ((pad, pad), (0, 0), (0, 0)), mode="reflect")
    out = np.zeros_like(arr)
    for offset, weight in enumerate(kernel):
        out = out + weight * padded_v[offset:offset + h, :, :]
    return out


def _delit_adjust(arr):
    import numpy as np

    luma_coef = np.asarray(LUMA_COEF_REC709, dtype=np.float32)
    gray = (arr * luma_coef).sum(axis=2, keepdims=True)
    desaturated = gray + DESATURATE_KEEP * (arr - gray)
    mean_luma = float((desaturated * luma_coef).sum(axis=2).mean(dtype=np.float64))
    if mean_luma <= 0.0:
        raise ValueError("post-desaturation mean luminance must be positive")
    scale = BRIGHTNESS_TARGET / mean_luma
    scale = min(max(scale, BRIGHTNESS_SCALE_MIN), BRIGHTNESS_SCALE_MAX)
    adjusted = desaturated * scale
    clipped = np.clip(np.rint(adjusted), 0.0, 255.0).astype(np.uint8)
    stats = {
        "brightness_scale_applied": float(scale),
        "brightness_scale_raw": float(BRIGHTNESS_TARGET / mean_luma),
        "post_desat_mean_luma": mean_luma,
        "output_rgb_min": [int(v) for v in clipped.min(axis=(0, 1))],
        "output_rgb_max": [int(v) for v in clipped.max(axis=(0, 1))],
        "output_rgb_mean": [float(v) for v in clipped.mean(axis=(0, 1))],
    }
    return clipped, stats


def _write_png_rgb8(path: Path, arr_uint8) -> None:
    import struct

    height, width = arr_uint8.shape[:2]
    if arr_uint8.shape[2] != 3:
        raise ValueError("RGB PNG expects 3 channels, got " + str(arr_uint8.shape))
    raw = b"".join(b"\x00" + arr_uint8[row].astype("<u1").tobytes() for row in range(height))
    chunks = [
        _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)),
        _png_chunk(b"IDAT", zlib.compress(raw, level=9)),
        _png_chunk(b"IEND", b""),
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + b"".join(chunks))


def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
    return len(data).to_bytes(4, "big") + chunk_type + data + crc.to_bytes(4, "big")


def _write_manifest(
    config: MacroAlbedoConfig,
    naip_year: int,
    target_height: int,
    gaussian_radius: int,
    input_stats: dict[str, Any],
    downsample_stats: dict[str, Any],
    output_stats: dict[str, Any],
) -> dict[str, Any]:
    from PIL import Image

    data = {
        "schema_version": 1,
        "source": "USGS The National Map USGSNAIPImagery ImageServer",
        "source_service_url": NAIP_SERVICE_URL,
        "source_year": naip_year,
        "crs": EXPECTED_CRS,
        "bounds_utm": list(config.tile_bounds),
        "surface_map_size": [config.surface_width, config.surface_height],
        "cell_spacing_m": CELL_SPACING_M,
        "naip_input_path": str(NAIP_INPUT_PATH.relative_to(ROOT)),
        "naip_input_sha256": _sha256(NAIP_INPUT_PATH),
        "naip_band_order": "R, G, B, NIR (USGS 4-band convention; NIR band dropped)",
        "naip_band_read_note": (
            "Pillow reads the 4-band GeoTIFF as mode RGBA; channels 0..2 are taken as "
            "R, G, B and channel 3 (NIR) is dropped. Spot-checked against the surface-ID "
            "NDVI convention (band1=Red, band4=NIR) used by bake_zion_surface_id_png.py."
        ),
        "reprojection_note": (
            "No reprojection in this bake: the NAIP mosaic at naip_input_path is already "
            "aligned to the surface-ID grid (5501x5701 @ 1 m, EPSG:32612) by "
            "bake_zion_surface_id_png.py. Dimensions are asserted at read time."
        ),
        "nodata_policy": (
            "Source NAIP mosaic covers the full terrain box with no nodata samples "
            "observed; no nodata fill is performed. Input bytes are hash-gated via "
            "naip_input_sha256."
        ),
        "macro_albedo_png_path": str(MACRO_ALBEDO_PNG_PATH.relative_to(ROOT)),
        "macro_albedo_png_sha256": _sha256(MACRO_ALBEDO_PNG_PATH),
        "macro_albedo_size": [TARGET_WIDTH, target_height],
        "macro_albedo_m_per_px": [
            float(config.tile_width_m) / float(TARGET_WIDTH),
            float(config.tile_height_m) / float(target_height),
        ],
        "params": {
            "downsample": "box-average via summed-area table (every source pixel contributes once)",
            "target_width": TARGET_WIDTH,
            "target_height": target_height,
            "gaussian_sigma": GAUSSIAN_SIGMA,
            "gaussian_truncate": GAUSSIAN_TRUNCATE,
            "gaussian_radius": gaussian_radius,
            "gaussian_padding": "reflect",
            "desaturate_keep": DESATURATE_KEEP,
            "luma_coef_rec709": list(LUMA_COEF_REC709),
            "brightness_target": BRIGHTNESS_TARGET,
            "brightness_scale_clamp": [BRIGHTNESS_SCALE_MIN, BRIGHTNESS_SCALE_MAX],
            "round_mode": "numpy.rint (round-half-to-even) then clip to [0,255]",
            "png_color_type": 2,
            "png_filter": 0,
            "png_zlib_level": 9,
        },
        "stats": {
            "input": input_stats,
            "downsample": downsample_stats,
            "output": output_stats,
        },
        "shader_sampling_note": (
            "Intended consumer: the unified terrain shader (visual-phase-research-dossier.md "
            "P2 'NAIP macro albedo + distance fade'). Sample at world UV = "
            "((world_pos.x - bounds_utm[0]) / (bounds_utm[2] - bounds_utm[0]), "
            "(world_pos.y - bounds_utm[1]) / (bounds_utm[3] - bounds_utm[1])); the texture "
            "spans the full bounds_utm extent. Use as a gentle MULTIPLICATIVE albedo "
            "modulator blended over the surface-ID base palette, NOT as the primary albedo: "
            "residual mid-day directional lighting is only partially removed by the "
            "desaturation + global brightness normalization, so a strong blend would "
            "re-introduce baked shading."
        ),
        "dependencies_recorded": {
            "numpy": _python_dep_version("numpy"),
            "pillow": Image.__version__,
        },
    }
    _write_json(MACRO_ALBEDO_MANIFEST_PATH, data)
    return data


def _python_dep_version(name: str) -> str:
    try:
        import importlib.metadata as md
    except ImportError:
        return ""
    try:
        return md.version(name)
    except Exception:
        return ""


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _const_float(text: str, name: str) -> float:
    return float(_const_value(text, name))


def _const_int(text: str, name: str) -> int:
    return int(_const_value(text, name))


def _const_value(text: str, name: str) -> str:
    match = re.search(r"^const\s+" + re.escape(name) + r"\s*:\s*\w+\s*=\s*([^\n]+)$", text, flags=re.MULTILINE)
    if match is None:
        raise ValueError("missing GameConfig constant: " + name)
    return match.group(1).strip().strip('"')


def _field(text: str, name: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"\s*=\s*([^\n]+)$", text, flags=re.MULTILINE)
    if match is None:
        raise ValueError("missing TerrainDef field: " + name)
    return match.group(1).strip()


def _parse_vector2i(value: str) -> tuple[int, int]:
    match = re.fullmatch(r"Vector2i\(([-0-9]+),\s*([-0-9]+)\)", value)
    if match is None:
        raise ValueError("expected Vector2i(...), got " + value)
    return int(match.group(1)), int(match.group(2))


if __name__ == "__main__":
    raise SystemExit(main())
