#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GAME_CONFIG_PATH = ROOT / "autoload/game_config.gd"
EXPECTED_NUMPY_VERSION = "2.4.6"
EXPECTED_RASTERIO_VERSION = "1.4.3"
EXPECTED_CRS = "EPSG:32612"
DEFAULT_REGION_ID = "cedar_hollow_zion"


@dataclass(frozen=True)
class ZionBakeConfig:
    region_id: str
    origin_easting: float
    origin_northing: float
    max_easting: float
    max_northing: float
    tile_cols: int
    tile_rows: int

    @property
    def width_m(self) -> float:
        return self.max_easting - self.origin_easting

    @property
    def height_m(self) -> float:
        return self.max_northing - self.origin_northing


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bake the Cedar Hollow Zion-inspired terrain corridor.")
    parser.add_argument("--source", choices=("10m", "1m"), default="10m", help="DEM source tier to bake.")
    parser.add_argument("--region-id", default=DEFAULT_REGION_ID, help="Output region id under data/regions/.")
    parser.add_argument("--dry-run", action="store_true", help="Validate inputs/configuration without writing artifacts.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        _assert_python_deps()
        config = _load_bake_config(args.region_id)
    except Exception as exc:
        print("fail: " + str(exc), file=sys.stderr)
        return 1

    if args.dry_run:
        print("ok: zion bake dry-run")
        print("source: " + args.source)
        print("crs: " + EXPECTED_CRS)
        print("region: " + config.region_id)
        print(
            "utm_bounds: "
            + f"{config.origin_easting:.6f},{config.origin_northing:.6f} -> "
            + f"{config.max_easting:.6f},{config.max_northing:.6f}"
        )
        print("tile_grid: " + str(config.tile_cols) + "x" + str(config.tile_rows))
        print("extent_m: " + f"{config.width_m:.3f}x{config.height_m:.3f}")
        return 0

    print("fail: real bake is implemented in Z2-B; use --dry-run for the Z1 skeleton", file=sys.stderr)
    return 1


def _assert_python_deps() -> None:
    import numpy as np
    import rasterio

    if np.__version__ != EXPECTED_NUMPY_VERSION:
        raise RuntimeError("numpy " + np.__version__ + " != " + EXPECTED_NUMPY_VERSION)
    if rasterio.__version__ != EXPECTED_RASTERIO_VERSION:
        raise RuntimeError("rasterio " + rasterio.__version__ + " != " + EXPECTED_RASTERIO_VERSION)


def _load_bake_config(region_id: str) -> ZionBakeConfig:
    text = GAME_CONFIG_PATH.read_text(encoding="utf-8")
    return ZionBakeConfig(
        region_id=region_id,
        origin_easting=_const_float(text, "ZION_CORRIDOR_UTM_ORIGIN_E"),
        origin_northing=_const_float(text, "ZION_CORRIDOR_UTM_ORIGIN_N"),
        max_easting=_const_float(text, "ZION_CORRIDOR_UTM_MAX_E"),
        max_northing=_const_float(text, "ZION_CORRIDOR_UTM_MAX_N"),
        tile_cols=_const_int(text, "ZION_CORRIDOR_TILE_COLS"),
        tile_rows=_const_int(text, "ZION_CORRIDOR_TILE_ROWS"),
    )


def _const_float(text: str, name: str) -> float:
    return float(_const_value(text, name))


def _const_int(text: str, name: str) -> int:
    return int(_const_value(text, name))


def _const_value(text: str, name: str) -> str:
    match = re.search(r"^const\s+" + re.escape(name) + r"\s*:\s*\w+\s*=\s*([^\n]+)$", text, flags=re.MULTILINE)
    if match is None:
        raise ValueError("missing GameConfig constant: " + name)
    return match.group(1).strip().strip('"')


if __name__ == "__main__":
    raise SystemExit(main())
