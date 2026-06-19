#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import math
import re
import struct
import sys
import time
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
GAME_CONFIG_PATH = ROOT / "autoload/game_config.gd"
TERRAIN_DEF_PATH = ROOT / "data/terrain/cedar_hollow_zion_terrain_def.tres"
NLCD_REMAP_PATH = ROOT / "data/bake_inputs/zion_nlcd_remapped.tif"
SURFACE_ID_PNG_PATH = ROOT / "data/terrain/cedar_hollow_zion_surface_id.png"
NAIP_SERVICE_URL = "https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer"
CATALOG_URL_NOTE = (
    "Catalog download_url values point to earthexplorer.usgs.gov and are "
    "informational provenance only; they are NOT used for download (those "
    "pages require login). Actual imagery download uses the "
    "imagery.nationalmap.gov USGSNAIPImagery ImageServer exportImage API "
    "with no authentication."
)
EXPECTED_CRS = "EPSG:32612"
CELL_SPACING_M = 1.0
CHUNK_MAX_PIXELS = 1500
DOWNLOAD_ATTEMPTS = 3
SURFACE_ID_ROCK = 2
SURFACE_ID_LOOSE = 4
SURFACE_ID_GRASS = 5
SURFACE_ID_PAVED_ROAD = 6
FALLBACK_SURFACE_ID = SURFACE_ID_LOOSE
PAVED_ROAD_KEEP_COMPONENT_PIXELS = 2000
_BFS_NEIGHBORS_8: tuple[tuple[int, int], ...] = (
    (-1, -1),
    (-1, 0),
    (-1, 1),
    (0, -1),
    (0, 1),
    (1, -1),
    (1, 0),
    (1, 1),
)


@dataclass(frozen=True)
class SurfaceBakeConfig:
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
    parser = argparse.ArgumentParser(description="Bake the Cedar Hollow Zion surface-ID PNG from NLCD + NAIP NDVI.")
    parser.add_argument("--year", choices=("auto", "2024", "2021"), default="auto")
    parser.add_argument("--naip-interpolation", default="RSP_BilinearInterpolation")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--reclassify-only",
        action="store_true",
        help="Skip NLCD/NAIP/network work. Read the existing source PNG, apply the "
        "paved_road reclassification pass in place, rewrite it, and refresh the "
        "manifest. Deterministic offline path; no rasterio / network required.",
    )
    return parser.parse_args()


def main() -> int:
    try:
        args = parse_args()
        if args.reclassify_only:
            return _run_reclassify_only()
        _assert_python_deps()
        config = _load_config()
        selected_year, catalog_by_year = _select_naip_year(args.year, config)
        output_dir = ROOT / "data/bake_inputs" / ("zion_naip_" + str(selected_year))
        if args.dry_run:
            print("ok: zion surface-ID dry-run")
            print("selected_naip_year: " + str(selected_year))
            print("output_dir: " + str(output_dir.relative_to(ROOT)))
            print("surface_map_size: " + str(config.surface_width) + "x" + str(config.surface_height))
            return 0
        output_dir.mkdir(parents=True, exist_ok=True)
        _write_catalog_files(output_dir, catalog_by_year)
        naip_path, export_requests = _export_naip_corridor(output_dir, selected_year, catalog_by_year[selected_year], config, args.naip_interpolation)
        surface_ids, stats = _build_surface_id_array(naip_path, config)
        _write_png_l8(SURFACE_ID_PNG_PATH, surface_ids)
        manifest_path = _write_manifest(output_dir, selected_year, catalog_by_year, export_requests, naip_path, stats, config, args.naip_interpolation)
    except Exception as exc:
        print("fail: " + str(exc), file=sys.stderr)
        return 1
    print("ok: zion surface-ID PNG")
    print("selected_naip_year: " + str(selected_year))
    print("naip_input: " + str(naip_path.relative_to(ROOT)))
    print("surface_id_png: " + str(SURFACE_ID_PNG_PATH.relative_to(ROOT)))
    print("manifest: " + str(manifest_path.relative_to(ROOT)))
    print("surface_id_counts: " + _format_counts(stats["surface_id_counts"]))
    print("ndvi_refined_barren_pixels: " + str(stats["ndvi_refined_barren_pixels"]))
    return 0


def _run_reclassify_only() -> int:
    import numpy as np

    if not SURFACE_ID_PNG_PATH.is_file():
        raise RuntimeError("source surface-ID PNG is missing: " + str(SURFACE_ID_PNG_PATH))
    width, height, samples = _read_l8_png(SURFACE_ID_PNG_PATH)
    surface_ids = np.frombuffer(samples, dtype=np.uint8).reshape(height, width).copy()
    before_counts = _counts(surface_ids)
    surface_ids, reclassify_stats = _reclassify_overclassified_paved_road(surface_ids)
    after_counts = _counts(surface_ids)
    _write_png_l8(SURFACE_ID_PNG_PATH, surface_ids)
    manifest_path = _refresh_surface_id_manifest(after_counts, before_counts, reclassify_stats)
    print("ok: zion surface-ID PNG (reclassify-only)")
    print("surface_id_png: " + str(SURFACE_ID_PNG_PATH.relative_to(ROOT)))
    if manifest_path is not None:
        print("manifest: " + str(manifest_path.relative_to(ROOT)))
    print("surface_id_counts_before: " + _format_counts(before_counts))
    print("surface_id_counts_after: " + _format_counts(after_counts))
    print(
        "paved_road_reclassified: "
        + str(reclassify_stats["paved_road_pixels_reclassified"])
        + " (kept "
        + str(reclassify_stats["paved_road_pixels_after"])
        + " across "
        + str(reclassify_stats["paved_road_components_kept"])
        + " components)"
    )
    return 0


def _assert_python_deps() -> None:
    import numpy as np
    import rasterio

    if np.dtype("float32").itemsize != 4:
        raise RuntimeError("numpy float32 is not 32-bit")
    if not rasterio.__version__:
        raise RuntimeError("rasterio version is empty")


def _load_config() -> SurfaceBakeConfig:
    game_config = GAME_CONFIG_PATH.read_text(encoding="utf-8")
    terrain_def = TERRAIN_DEF_PATH.read_text(encoding="utf-8")
    surface_width, surface_height = _parse_vector2i(_field(terrain_def, "surface_map_size"))
    return SurfaceBakeConfig(
        origin_easting=_const_float(game_config, "ZION_CORRIDOR_UTM_ORIGIN_E"),
        origin_northing=_const_float(game_config, "ZION_CORRIDOR_UTM_ORIGIN_N"),
        tile_cols=_const_int(game_config, "ZION_CORRIDOR_TILE_COLS"),
        tile_rows=_const_int(game_config, "ZION_CORRIDOR_TILE_ROWS"),
        tile_size_m=_const_float(game_config, "STREAM_TILE_SIZE_M"),
        surface_width=surface_width,
        surface_height=surface_height,
    )


def _select_naip_year(requested_year: str, config: SurfaceBakeConfig) -> tuple[int, dict[int, dict[str, Any]]]:
    catalog_by_year: dict[int, dict[str, Any]] = {}
    for year in (2024, 2021):
        catalog_by_year[year] = _query_naip_catalog(year, config)
    if requested_year != "auto":
        year = int(requested_year)
        _require_source_features(year, catalog_by_year[year])
        return year, catalog_by_year
    if _source_features(catalog_by_year[2024]):
        return 2024, catalog_by_year
    _require_source_features(2021, catalog_by_year[2021])
    return 2021, catalog_by_year


def _query_naip_catalog(year: int, config: SurfaceBakeConfig) -> dict[str, Any]:
    min_x, min_y, max_x, max_y = config.tile_bounds
    params = {
        "f": "json",
        "where": "Year = " + str(year) + " AND State = 'UT'",
        "geometry": _join_numbers([min_x, min_y, max_x, max_y]),
        "geometryType": "esriGeometryEnvelope",
        "inSR": "32612",
        "spatialRel": "esriSpatialRelIntersects",
        "outFields": (
            "OBJECTID,Name,State,Year,raster_name,download_url,acquisition_date,"
            "resolution_value,resolution_units,band_count,projection_name,projection_zone,datum"
        ),
        "returnGeometry": "false",
        "returnCountOnly": "false",
        "orderByFields": "Name",
        "resultRecordCount": "50",
    }
    url = NAIP_SERVICE_URL + "/query?" + urlencode(params)
    data = _read_json_url(url)
    features = data.get("features", [])
    if not isinstance(features, list):
        raise ValueError("NAIP catalog response features must be a list")
    normalized_features = []
    for feature in features:
        if not isinstance(feature, dict):
            continue
        attributes = feature.get("attributes", {})
        if isinstance(attributes, dict):
            normalized_features.append(dict(sorted(attributes.items())))
    return {
        "query_url": url,
        "year": year,
        "source_features": _source_features({"features": normalized_features}),
        "features": normalized_features,
    }


def _source_features(catalog: dict[str, Any]) -> list[dict[str, Any]]:
    features = catalog.get("features", [])
    if not isinstance(features, list):
        return []
    source_features = []
    for attributes in features:
        if not isinstance(attributes, dict):
            continue
        if int(attributes.get("band_count") or 0) == 4 and str(attributes.get("projection_zone") or "") == "12N":
            source_features.append(attributes)
    return source_features


def _require_source_features(year: int, catalog: dict[str, Any]) -> None:
    if not _source_features(catalog):
        raise ValueError("no usable 4-band UTM Zone 12N NAIP source features for " + str(year))


def _write_catalog_files(output_dir: Path, catalog_by_year: dict[int, dict[str, Any]]) -> None:
    for year in sorted(catalog_by_year):
        _write_json(output_dir / ("naip_" + str(year) + "_catalog_query.json"), catalog_by_year[year])


def _export_naip_corridor(
    output_dir: Path,
    year: int,
    catalog: dict[str, Any],
    config: SurfaceBakeConfig,
    interpolation: str,
) -> tuple[Path, list[dict[str, Any]]]:
    import rasterio
    from rasterio.io import MemoryFile
    from rasterio.transform import from_origin
    from rasterio.windows import Window

    naip_path = output_dir / ("zion_naip_" + str(year) + "_corridor_rgbn_1m.tif")
    transform = from_origin(config.origin_easting, config.tile_max_northing, CELL_SPACING_M, CELL_SPACING_M)
    profile = {
        "driver": "GTiff",
        "width": config.surface_width,
        "height": config.surface_height,
        "count": 4,
        "dtype": "uint8",
        "crs": EXPECTED_CRS,
        "transform": transform,
        "compress": "deflate",
        "predictor": 2,
        "tiled": True,
        "blockxsize": 256,
        "blockysize": 256,
        "interleave": "pixel",
        "BIGTIFF": "IF_SAFER",
    }
    export_requests: list[dict[str, Any]] = []
    mosaic_rule = {
        "mosaicMethod": "esriMosaicAttribute",
        "where": "Year = " + str(year) + " AND State = 'UT'",
        "sortField": "Year",
        "sortValue": "3000",
        "ascending": True,
        "mosaicOperation": "MT_FIRST",
    }
    rendering_rule = {"rasterFunction": "None"}
    with rasterio.open(naip_path, "w", **profile) as dst:
        for row_start, row_stop in _chunk_ranges(config.surface_height):
            for col_start, col_stop in _chunk_ranges(config.surface_width):
                width = col_stop - col_start
                height = row_stop - row_start
                min_x = config.origin_easting + float(col_start) * CELL_SPACING_M
                max_x = config.origin_easting + float(col_stop) * CELL_SPACING_M
                max_y = config.tile_max_northing - float(row_start) * CELL_SPACING_M
                min_y = config.tile_max_northing - float(row_stop) * CELL_SPACING_M
                url = _export_image_url(min_x, min_y, max_x, max_y, width, height, mosaic_rule, rendering_rule, interpolation)
                data = _read_bytes_url(url)
                with MemoryFile(data) as memfile:
                    with memfile.open() as src:
                        if src.count != 4:
                            raise ValueError("NAIP export chunk returned " + str(src.count) + " bands, expected 4")
                        if src.dtypes != ("uint8", "uint8", "uint8", "uint8"):
                            raise ValueError("NAIP export chunk returned dtypes " + str(src.dtypes) + ", expected uint8")
                        chunk = src.read()
                window = Window(col_start, row_start, width, height)
                dst.write(chunk, window=window)
                export_requests.append(
                    {
                        "row_start": row_start,
                        "row_stop": row_stop,
                        "col_start": col_start,
                        "col_stop": col_stop,
                        "sha256": hashlib.sha256(data).hexdigest(),
                        "url": url,
                    }
                )
        dst.update_tags(
            AREA_OR_POINT="Area",
            source_service=NAIP_SERVICE_URL,
            source_year=str(year),
            source_feature_count=str(len(_source_features(catalog))),
        )
    return naip_path, export_requests


def _build_surface_id_array(naip_path: Path, config: SurfaceBakeConfig):
    import numpy as np
    import rasterio
    from rasterio.transform import from_origin
    from rasterio.warp import Resampling, reproject

    transform = from_origin(config.origin_easting, config.tile_max_northing, CELL_SPACING_M, CELL_SPACING_M)
    base_surface = np.full((config.surface_height, config.surface_width), FALLBACK_SURFACE_ID, dtype=np.uint8)
    with rasterio.open(NLCD_REMAP_PATH) as src:
        reproject(
            source=rasterio.band(src, 1),
            destination=base_surface,
            src_transform=src.transform,
            src_crs=src.crs,
            dst_transform=transform,
            dst_crs=EXPECTED_CRS,
            dst_nodata=FALLBACK_SURFACE_ID,
            resampling=Resampling.nearest,
            num_threads=2,
        )
    with rasterio.open(naip_path) as src:
        if src.width != config.surface_width or src.height != config.surface_height:
            raise ValueError("NAIP input dimensions do not match surface map size")
        red = src.read(1).astype(np.float32)
        nir = src.read(4).astype(np.float32)
    ndvi = (nir - red) / (nir + red + np.float32(1e-6))
    refined = base_surface.copy()
    barren = base_surface == SURFACE_ID_ROCK
    sparse = barren & (ndvi >= np.float32(0.05)) & (ndvi < np.float32(0.15))
    vegetated = barren & (ndvi >= np.float32(0.15))
    refined[sparse] = SURFACE_ID_LOOSE
    refined[vegetated] = SURFACE_ID_GRASS
    refined, reclassify_stats = _reclassify_overclassified_paved_road(refined)
    values, counts = np.unique(refined, return_counts=True)
    ndvi_values = ndvi[barren]
    stats = {
        "surface_id_counts": {str(int(value)): int(count) for value, count in zip(values, counts)},
        "base_surface_id_counts": _counts(base_surface),
        "ndvi_refined_barren_pixels": int(np.count_nonzero(barren)),
        "ndvi_to_rock_pixels": int(np.count_nonzero(barren & (ndvi < np.float32(0.05)))),
        "ndvi_to_loose_pixels": int(np.count_nonzero(sparse)),
        "ndvi_to_grass_pixels": int(np.count_nonzero(vegetated)),
        "ndvi_min": float(np.min(ndvi_values)) if ndvi_values.size else None,
        "ndvi_max": float(np.max(ndvi_values)) if ndvi_values.size else None,
        "ndvi_mean": float(np.mean(ndvi_values, dtype=np.float64)) if ndvi_values.size else None,
        "paved_road_reclassification": reclassify_stats,
    }
    return refined, stats


def _write_manifest(
    output_dir: Path,
    selected_year: int,
    catalog_by_year: dict[int, dict[str, Any]],
    export_requests: list[dict[str, Any]],
    naip_path: Path,
    stats: dict[str, Any],
    config: SurfaceBakeConfig,
    interpolation: str,
) -> Path:
    manifest_path = output_dir / "zion_naip_surface_id_manifest.json"
    data = {
        "schema_version": 1,
        "source": "USGS The National Map USGSNAIPImagery ImageServer",
        "source_service_url": NAIP_SERVICE_URL,
        "selected_year": selected_year,
        "fallback_reason": "NAIP 2024 catalog query returned no usable 4-band UTM Zone 12N UT source features"
        if selected_year == 2021
        else "",
        "crs": EXPECTED_CRS,
        "cell_spacing_m": CELL_SPACING_M,
        "bounds_utm": list(config.tile_bounds),
        "surface_map_size": [config.surface_width, config.surface_height],
        "nlcd_remapped_path": str(NLCD_REMAP_PATH.relative_to(ROOT)),
        "nlcd_resampling": "nearest",
        "naip_interpolation": interpolation,
        "naip_input_path": str(naip_path.relative_to(ROOT)),
        "naip_input_sha256": _sha256(naip_path),
        "surface_id_png_path": str(SURFACE_ID_PNG_PATH.relative_to(ROOT)),
        "surface_id_png_sha256": _sha256(SURFACE_ID_PNG_PATH),
        "ndvi_formula": "(band4 - band1) / (band4 + band1 + 1e-6)",
        "ndvi_thresholds": {
            "rock": "ndvi < 0.05",
            "loose": "0.05 <= ndvi < 0.15",
            "grass": "ndvi >= 0.15",
        },
        "catalog": catalog_by_year,
        "catalog_url_note": CATALOG_URL_NOTE,
        "export_requests": export_requests,
        "stats": stats,
    }
    _write_json(manifest_path, data)
    return manifest_path


def _export_image_url(
    min_x: float,
    min_y: float,
    max_x: float,
    max_y: float,
    width: int,
    height: int,
    mosaic_rule: dict[str, Any],
    rendering_rule: dict[str, Any],
    interpolation: str,
) -> str:
    params = {
        "f": "image",
        "format": "tiff",
        "bbox": _join_numbers([min_x, min_y, max_x, max_y]),
        "bboxSR": "32612",
        "imageSR": "32612",
        "size": str(width) + "," + str(height),
        "pixelType": "U8",
        "interpolation": interpolation,
        "mosaicRule": json.dumps(mosaic_rule, separators=(",", ":"), sort_keys=True),
        "renderingRule": json.dumps(rendering_rule, separators=(",", ":"), sort_keys=True),
    }
    return NAIP_SERVICE_URL + "/exportImage?" + urlencode(params)


def _chunk_ranges(size: int) -> list[tuple[int, int]]:
    ranges = []
    chunk_count = int(math.ceil(float(size) / float(CHUNK_MAX_PIXELS)))
    chunk_size = int(math.ceil(float(size) / float(chunk_count)))
    start = 0
    while start < size:
        stop = min(size, start + chunk_size)
        ranges.append((start, stop))
        start = stop
    return ranges


def _write_png_l8(path: Path, surface_ids) -> None:
    import numpy as np

    arr = np.ascontiguousarray(surface_ids, dtype=np.uint8)
    height, width = arr.shape
    raw = b"".join(b"\x00" + arr[row].tobytes() for row in range(height))
    chunks = [
        _png_chunk(b"IHDR", width.to_bytes(4, "big") + height.to_bytes(4, "big") + b"\x08\x00\x00\x00\x00"),
        _png_chunk(b"IDAT", zlib.compress(raw, level=9)),
        _png_chunk(b"IEND", b""),
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + b"".join(chunks))


def _read_l8_png(path: Path) -> tuple[int, int, bytes]:
    """Pure-Python L8 (8-bit grayscale) PNG reader. Returns (width, height, samples).

    Used by the `--reclassify-only` offline path so the bake tool can refresh a
    committed surface-ID PNG without rasterio or any network access.
    """
    data = path.read_bytes()
    if len(data) < 24:
        raise ValueError("surface-ID PNG is too small for a PNG header")
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("surface-ID PNG has invalid signature")
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
            raise ValueError("surface-ID PNG has a truncated chunk")
        chunk_data = data[offset : offset + chunk_length]
        offset += chunk_length
        expected_crc = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ValueError("surface-ID PNG has invalid CRC for chunk " + chunk_type.decode("latin1"))
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack_from(">IIBBBBB", chunk_data, 0)
            if compression != 0 or filter_method != 0 or interlace != 0:
                raise ValueError("surface-ID PNG has unsupported header flags")
        elif chunk_type == b"IDAT":
            idat.extend(chunk_data)
        elif chunk_type == b"IEND":
            saw_iend = True
            break
    if not saw_iend:
        raise ValueError("surface-ID PNG is missing IEND")
    if width <= 0 or height <= 0:
        raise ValueError("surface-ID PNG has invalid dimensions " + str(width) + "x" + str(height))
    if bit_depth != 8:
        raise ValueError("surface-ID PNG must use 8-bit channels, got bit depth " + str(bit_depth))
    if color_type != 0:
        raise ValueError("surface-ID PNG must be grayscale (color type 0), got " + str(color_type))
    if not idat:
        raise ValueError("surface-ID PNG is missing IDAT data")
    raw = zlib.decompress(bytes(idat))
    stride = width
    expected_size = (stride + 1) * height
    if len(raw) != expected_size:
        raise ValueError("surface-ID PNG payload size " + str(len(raw)) + " != expected " + str(expected_size))
    samples = bytearray(width * height)
    previous = bytearray(stride)
    raw_offset = 0
    sample_offset = 0
    for _row in range(height):
        filter_type = raw[raw_offset]
        raw_offset += 1
        row = bytearray(raw[raw_offset : raw_offset + stride])
        raw_offset += stride
        _unfilter_l8_row(row, previous, filter_type)
        samples[sample_offset : sample_offset + stride] = row
        sample_offset += stride
        previous = row
    return width, height, bytes(samples)


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
    raise ValueError("surface-ID PNG has unsupported filter type " + str(filter_type))


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


def _reclassify_overclassified_paved_road(surface_ids) -> tuple[Any, dict[str, Any]]:
    """Reclassify over-classified paved_road (id 6) pixels to the surrounding natural surface.

    NLCD systematically tags large contiguous expanses of dry canyon floor as
    "developed / open space", which the NLCD remap collapses to surface id 6
    (paved_road). In the Cedar Hollow corridor these tags are spurious: there
    is no real pavement covering most of the canyon floor. Real paved
    infrastructure (parking pads, bridge decks, small pull-outs) is a handful
    of small footprints. Rule:

      * 8-connectivity component-label the (surface_ids == 6) mask.
      * Reclassify every pixel in components with size >=
        PAVED_ROAD_KEEP_COMPONENT_PIXELS back to natural surface.
      * Keep every pixel in components smaller than that threshold as
        paved_road (real infrastructure).

    Reclassified pixels are filled by multi-source BFS from their nearest
    stable neighbor (8-conn, raster-order seed enqueue, fixed neighbor order)
    so each pixel takes the surface id of whichever natural pixel reaches it
    first. This produces a deterministic Voronoi-like fill that preserves the
    natural-desert variety (sand / slickrock / wash / gravel) instead of
    collapsing to a single replacement id.

    Determinism: no RNG, no Python str hash, no wall clock. Pure-Python +
    numpy boolean ops. The rule depends only on the surface-id array, so the
    `--reclassify-only` offline path produces byte-identical output to a full
    NLCD+NAIP+NDVI re-bake that runs this same function in-line.
    """
    import numpy as np

    height, width = surface_ids.shape
    road_mask = surface_ids == SURFACE_ID_PAVED_ROAD
    road_total = int(road_mask.sum())
    if road_total == 0:
        return surface_ids, {
            "paved_road_pixels_before": 0,
            "paved_road_pixels_after": 0,
            "paved_road_components_before": 0,
            "paved_road_components_kept": 0,
            "paved_road_components_reclassified": 0,
            "paved_road_pixels_reclassified": 0,
            "paved_road_keep_component_pixels": PAVED_ROAD_KEEP_COMPONENT_PIXELS,
            "paved_road_reclassify_targets": {},
        }

    labels = _label_8connected(road_mask)
    num_components = int(labels.max())
    component_sizes = np.bincount(labels.ravel())
    reclassify_mask = np.zeros_like(road_mask)
    kept_components = 0
    reclassified_components = 0
    for label_id in range(1, num_components + 1):
        size = int(component_sizes[label_id])
        if size >= PAVED_ROAD_KEEP_COMPONENT_PIXELS:
            reclassify_mask |= labels == label_id
            reclassified_components += 1
        else:
            kept_components += 1

    reclassify_count = int(reclassify_mask.sum())
    before_counts = _counts(surface_ids)
    if reclassify_count == 0:
        return surface_ids.copy(), {
            "paved_road_pixels_before": road_total,
            "paved_road_pixels_after": road_total,
            "paved_road_components_before": num_components,
            "paved_road_components_kept": num_components,
            "paved_road_components_reclassified": 0,
            "paved_road_pixels_reclassified": 0,
            "paved_road_keep_component_pixels": PAVED_ROAD_KEEP_COMPONENT_PIXELS,
            "paved_road_reclassify_targets": {},
        }

    out = surface_ids.copy()
    pending = reclassify_mask.copy()
    stable = ~pending
    boundary_stable = np.zeros_like(stable)
    for dy, dx in _BFS_NEIGHBORS_8:
        shifted = np.zeros_like(pending)
        src_y = slice(max(0, dy), height + min(0, dy))
        src_x = slice(max(0, dx), width + min(0, dx))
        dst_y = slice(max(0, -dy), height + min(0, -dy))
        dst_x = slice(max(0, -dx), width + min(0, -dx))
        shifted[dst_y, dst_x] = pending[src_y, src_x]
        boundary_stable |= shifted & stable

    queue: deque = deque()
    for y, x in np.argwhere(boundary_stable).tolist():
        queue.append((int(y), int(x), int(out[y, x])))

    while queue:
        y, x, sid = queue.popleft()
        for dy, dx in _BFS_NEIGHBORS_8:
            ny = y + dy
            nx = x + dx
            if 0 <= ny < height and 0 <= nx < width and pending[ny, nx]:
                out[ny, nx] = sid
                pending[ny, nx] = False
                queue.append((ny, nx, sid))

    if pending.any():
        raise RuntimeError(
            "paved_road reclassify left "
            + str(int(pending.sum()))
            + " pixels unassigned (input must be entirely enclosed by stable surface)"
        )

    after_counts = _counts(out)
    targets: dict[str, int] = {}
    for value in sorted(int(v) for v in set(out[reclassify_mask].tolist())):
        targets[str(value)] = int(after_counts.get(str(value), 0)) - int(before_counts.get(str(value), 0))

    stats = {
        "paved_road_pixels_before": road_total,
        "paved_road_pixels_after": int((out == SURFACE_ID_PAVED_ROAD).sum()),
        "paved_road_components_before": num_components,
        "paved_road_components_kept": kept_components,
        "paved_road_components_reclassified": reclassified_components,
        "paved_road_pixels_reclassified": reclassify_count,
        "paved_road_keep_component_pixels": PAVED_ROAD_KEEP_COMPONENT_PIXELS,
        "paved_road_reclassify_targets": targets,
    }
    return out, stats


def _label_8connected(mask) -> Any:
    """8-connectivity component labeling, pure Python + numpy. Deterministic;
    labels are assigned in raster order of the first pixel encountered."""
    import numpy as np

    rows, cols = mask.shape
    labels = np.zeros((rows, cols), dtype=np.int32)
    next_label = 1
    stack: list[tuple[int, int]] = []
    mask_view = mask
    for y in range(rows):
        row = mask_view[y]
        labels_row = labels[y]
        for x in range(cols):
            if row[x] and labels_row[x] == 0:
                labels_row[x] = next_label
                stack.append((y, x))
                while stack:
                    cy, cx = stack.pop()
                    for dy in (-1, 0, 1):
                        ny = cy + dy
                        if ny < 0 or ny >= rows:
                            continue
                        for dx in (-1, 0, 1):
                            if dy == 0 and dx == 0:
                                continue
                            nx = cx + dx
                            if nx < 0 or nx >= cols:
                                continue
                            if mask_view[ny, nx] and labels[ny, nx] == 0:
                                labels[ny, nx] = next_label
                                stack.append((ny, nx))
                next_label += 1
    return labels


def _refresh_surface_id_manifest(
    after_counts: dict[str, int],
    before_counts: dict[str, int],
    reclassify_stats: dict[str, Any],
) -> Path | None:
    candidates = sorted((ROOT / "data/bake_inputs").glob("zion_naip_*/zion_naip_surface_id_manifest.json"))
    if not candidates:
        return None
    manifest_path = candidates[0]
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError("surface-ID manifest root must be an object: " + str(manifest_path))
    data["surface_id_png_sha256"] = _sha256(SURFACE_ID_PNG_PATH)
    stats = data.get("stats", {})
    if not isinstance(stats, dict):
        stats = {}
    stats["surface_id_counts_before_paved_road_reclass"] = before_counts
    stats["surface_id_counts"] = after_counts
    stats["paved_road_reclassification"] = reclassify_stats
    data["stats"] = stats
    _write_json(manifest_path, data)
    return manifest_path


def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
    return len(data).to_bytes(4, "big") + chunk_type + data + crc.to_bytes(4, "big")


def _read_json_url(url: str) -> dict[str, Any]:
    data = json.loads(_read_bytes_url(url).decode("utf-8"))
    if not isinstance(data, dict):
        raise ValueError("URL did not return a JSON object: " + url)
    if "error" in data:
        raise ValueError("URL returned error: " + json.dumps(data["error"], sort_keys=True))
    return data


def _read_bytes_url(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "TrailheadTerrainBake/1.0"})
    last_error: Exception | None = None
    for attempt in range(DOWNLOAD_ATTEMPTS):
        try:
            with urlopen(request, timeout=120) as response:
                return response.read()
        except (HTTPError, URLError, TimeoutError) as exc:
            last_error = exc
            if attempt + 1 < DOWNLOAD_ATTEMPTS:
                time.sleep(2.0 * float(attempt + 1))
    if last_error is not None:
        raise last_error
    raise RuntimeError("download failed without an exception")


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _counts(values) -> dict[str, int]:
    import numpy as np

    unique, counts = np.unique(values, return_counts=True)
    return {str(int(value)): int(count) for value, count in zip(unique, counts)}


def _format_counts(counts: dict[str, int]) -> str:
    return ", ".join(key + "=" + str(counts[key]) for key in sorted(counts, key=lambda value: int(value)))


def _join_numbers(values: list[float]) -> str:
    return ",".join(format(float(value), ".6f") for value in values)


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
