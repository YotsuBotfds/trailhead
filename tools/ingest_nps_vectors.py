#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
GAME_CONFIG_PATH = ROOT / "autoload/game_config.gd"
ZION_TERRAIN_DEF_PATH = ROOT / "data/terrain/cedar_hollow_zion_terrain_def.tres"
NAME_MAP_PATH = ROOT / "data/bake_inputs/zion_name_map.json"
TRAILS_QUERY_URL = (
    "https://mapservices.nps.gov/arcgis/rest/services/NationalDatasets/"
    "NPS_Public_Trails/FeatureServer/0/query"
)
POIS_QUERY_URL = (
    "https://mapservices.nps.gov/arcgis/rest/services/NationalDatasets/"
    "NPS_Public_POIs/FeatureServer/0/query"
)
EXPECTED_SOURCE_CRS = "EPSG:3857"
TARGET_CRS = "EPSG:32612"
BACKLOG_EXPECTED_TRAIL_COUNT = 13
DEFAULT_PAGE_SIZE = 2000


@dataclass(frozen=True)
class CorridorConfig:
    origin_easting: float
    origin_northing: float
    max_easting: float
    max_northing: float


@dataclass(frozen=True)
class VectorSummary:
    feature_count: int
    coordinate_count: int
    corridor_feature_count: int
    world_bounds: tuple[float, float, float, float] | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Ingest NPS vectors for the internal Zion terrain bake.")
    parser.add_argument("--dry-run", action="store_true", help="Fetch and reproject without writing resources.")
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE, help="ArcGIS query page size.")
    parser.add_argument("--timeout", type=float, default=30.0, help="HTTP request timeout in seconds.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.page_size <= 0:
        print("fail: --page-size must be positive", file=sys.stderr)
        return 1
    if not args.dry_run:
        print("fail: resource writes are reserved for Z5-A; use --dry-run for the Z1-C skeleton", file=sys.stderr)
        return 1

    try:
        _assert_python_deps()
        config = _load_corridor_config()
        _assert_terrain_def_origin(config)
        name_map_entries = _load_name_map_entry_count()
        trails = _fetch_geojson(
            TRAILS_QUERY_URL,
            out_fields="OBJECTID,UNITCODE,TRLNAME,MAPLABEL,TRLSURFACE,TRLTYPE",
            page_size=args.page_size,
            timeout=args.timeout,
        )
        pois = _fetch_geojson(
            POIS_QUERY_URL,
            out_fields="OBJECTID,UNITCODE,MAPLABEL,POITYPE",
            page_size=args.page_size,
            timeout=args.timeout,
        )
        trail_summary = _summarize_features(trails, config)
        poi_summary = _summarize_features(pois, config)
    except Exception as exc:
        print("fail: " + str(exc), file=sys.stderr)
        return 1

    print("ok: nps vector ingest dry-run")
    print("source_crs: " + EXPECTED_SOURCE_CRS)
    print("target_crs: " + TARGET_CRS)
    print("name_map_entries: " + str(name_map_entries))
    _print_summary("trails", trail_summary)
    _print_summary("pois", poi_summary)
    if trail_summary.feature_count != BACKLOG_EXPECTED_TRAIL_COUNT:
        print(
            "warning: trail feature count "
            + str(trail_summary.feature_count)
            + " differs from backlog expected "
            + str(BACKLOG_EXPECTED_TRAIL_COUNT)
            + "; see planning/open-questions.md Q31"
        )
    return 0


def _assert_python_deps() -> None:
    import pyproj  # noqa: F401


def _load_corridor_config() -> CorridorConfig:
    text = GAME_CONFIG_PATH.read_text(encoding="utf-8")
    return CorridorConfig(
        origin_easting=_const_float(text, "ZION_CORRIDOR_UTM_ORIGIN_E"),
        origin_northing=_const_float(text, "ZION_CORRIDOR_UTM_ORIGIN_N"),
        max_easting=_const_float(text, "ZION_CORRIDOR_UTM_MAX_E"),
        max_northing=_const_float(text, "ZION_CORRIDOR_UTM_MAX_N"),
    )


def _const_float(text: str, name: str) -> float:
    match = re.search(r"^const\s+" + re.escape(name) + r"\s*:\s*\w+\s*=\s*([^\n]+)$", text, flags=re.MULTILINE)
    if match is None:
        raise ValueError("missing GameConfig constant: " + name)
    return float(match.group(1).strip().strip('"'))


def _assert_terrain_def_origin(config: CorridorConfig) -> None:
    sys.path.insert(0, str(ROOT / "tools"))
    from terrain_def_parser import load_terrain_def

    terrain = load_terrain_def(ZION_TERRAIN_DEF_PATH)
    if abs(terrain.bounds_min_xz[0] - config.origin_easting) > 0.001:
        raise ValueError("Zion TerrainDef easting origin does not match GameConfig")
    if abs(terrain.bounds_min_xz[1] - config.origin_northing) > 0.001:
        raise ValueError("Zion TerrainDef northing origin does not match GameConfig")


def _load_name_map_entry_count() -> int:
    data = json.loads(NAME_MAP_PATH.read_text(encoding="utf-8"))
    names = data.get("names", {})
    if not isinstance(names, dict):
        raise ValueError("zion_name_map.json names must be an object")
    return len(names)


def _fetch_geojson(endpoint: str, out_fields: str, page_size: int, timeout: float) -> list[dict[str, Any]]:
    features: list[dict[str, Any]] = []
    offset = 0
    while True:
        params = {
            "where": "UNITCODE='ZION'",
            "f": "geojson",
            "outFields": out_fields,
            "returnGeometry": "true",
            "outSR": "3857",
            "orderByFields": "OBJECTID ASC",
            "resultOffset": str(offset),
            "resultRecordCount": str(page_size),
        }
        data = _read_json(endpoint + "?" + urllib.parse.urlencode(params), timeout)
        if "error" in data:
            raise RuntimeError("ArcGIS query failed: " + json.dumps(data["error"], sort_keys=True))
        page_features = data.get("features", [])
        if not isinstance(page_features, list):
            raise ValueError("ArcGIS response features must be an array")
        features.extend(_feature for _feature in page_features if isinstance(_feature, dict))
        if not data.get("exceededTransferLimit"):
            break
        if not page_features:
            raise RuntimeError("ArcGIS pagination stalled at offset " + str(offset))
        offset += len(page_features)
    return features


def _read_json(url: str, timeout: float) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": "TrailheadBake/1.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = json.load(response)
    if not isinstance(data, dict):
        raise ValueError("ArcGIS response must be an object")
    return data


def _summarize_features(features: list[dict[str, Any]], config: CorridorConfig) -> VectorSummary:
    from pyproj import Transformer

    transformer = Transformer.from_crs(EXPECTED_SOURCE_CRS, TARGET_CRS, always_xy=True)
    coordinate_count = 0
    corridor_feature_count = 0
    min_x = float("inf")
    min_z = float("inf")
    max_x = float("-inf")
    max_z = float("-inf")
    for feature in features:
        feature_has_corridor_coord = False
        geometry = feature.get("geometry", {})
        if not isinstance(geometry, dict):
            continue
        for source_x, source_y in _iter_coordinate_pairs(geometry.get("coordinates")):
            coordinate_count += 1
            utm_x, utm_y = transformer.transform(source_x, source_y)
            snapped_utm_x = round(float(utm_x))
            snapped_utm_y = round(float(utm_y))
            world_x = snapped_utm_x - config.origin_easting
            world_z = snapped_utm_y - config.origin_northing
            min_x = min(min_x, world_x)
            min_z = min(min_z, world_z)
            max_x = max(max_x, world_x)
            max_z = max(max_z, world_z)
            if (
                config.origin_easting <= snapped_utm_x <= config.max_easting
                and config.origin_northing <= snapped_utm_y <= config.max_northing
            ):
                feature_has_corridor_coord = True
        if feature_has_corridor_coord:
            corridor_feature_count += 1
    bounds = None
    if coordinate_count > 0:
        bounds = (min_x, min_z, max_x, max_z)
    return VectorSummary(
        feature_count=len(features),
        coordinate_count=coordinate_count,
        corridor_feature_count=corridor_feature_count,
        world_bounds=bounds,
    )


def _iter_coordinate_pairs(value: Any) -> Iterable[tuple[float, float]]:
    if not isinstance(value, list):
        return
    if len(value) >= 2 and isinstance(value[0], (float, int)) and isinstance(value[1], (float, int)):
        yield float(value[0]), float(value[1])
        return
    for child in value:
        yield from _iter_coordinate_pairs(child)


def _print_summary(label: str, summary: VectorSummary) -> None:
    print(label + "_features: " + str(summary.feature_count))
    print(label + "_coordinates: " + str(summary.coordinate_count))
    print(label + "_corridor_features: " + str(summary.corridor_feature_count))
    if summary.world_bounds is None:
        print(label + "_world_bounds: none")
        return
    min_x, min_z, max_x, max_z = summary.world_bounds
    print(label + "_world_bounds: " + f"{min_x:.3f},{min_z:.3f} -> {max_x:.3f},{max_z:.3f}")


if __name__ == "__main__":
    raise SystemExit(main())
