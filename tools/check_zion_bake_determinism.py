#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BAKE_INPUT_DIR = ROOT / "data/bake_inputs"
INPUT_MANIFEST = BAKE_INPUT_DIR / "zion_dem_input_manifest.json"
OUTPUT_MANIFEST = BAKE_INPUT_DIR / "zion_bake_output_manifest.json"
EXPECTED_NUMPY_VERSION = "2.4.6"
EXPECTED_RASTERIO_VERSION = "1.4.3"
EXPECTED_TNM_10M_SOURCE_URL = (
    "https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current/"
    "n38w113/USGS_13_n38w113.tif"
)
EXPECTED_TILE_COLS = 55
EXPECTED_TILE_ROWS = 57
EXPECTED_TILE_COUNT = EXPECTED_TILE_COLS * EXPECTED_TILE_ROWS
EXPECTED_OUTPUT_ROLES = {
    "heightmap_bin": EXPECTED_TILE_COUNT,
    "tile_sidecar": EXPECTED_TILE_COUNT,
    "collision_resource": EXPECTED_TILE_COUNT,
    "terrain_def": 1,
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def main() -> int:
    try:
        _assert_python_deps()
        if not INPUT_MANIFEST.exists():
            missing = [path for path in (INPUT_MANIFEST, OUTPUT_MANIFEST) if not path.exists()]
            names = ", ".join(str(path.relative_to(ROOT)) for path in missing)
            print("ok: zion bake not-yet-baked; missing manifest(s): " + names)
            return 0
        _check_input_manifest(INPUT_MANIFEST)
        _check_manifest(INPUT_MANIFEST, base_dir=BAKE_INPUT_DIR)
        if not OUTPUT_MANIFEST.exists():
            print("ok: zion input manifest; output not-yet-baked: " + str(OUTPUT_MANIFEST.relative_to(ROOT)))
            return 0
        _check_output_manifest(OUTPUT_MANIFEST)
    except Exception as exc:
        print("fail: " + str(exc), file=sys.stderr)
        return 1
    print("ok: zion bake determinism manifests")
    return 0


def _assert_python_deps() -> None:
    import numpy as np

    if np.__version__ != EXPECTED_NUMPY_VERSION:
        raise RuntimeError("numpy " + np.__version__ + " != " + EXPECTED_NUMPY_VERSION)
    try:
        import rasterio
    except ModuleNotFoundError:
        if os.environ.get("TRAILHEAD_REQUIRE_BAKE_DEPS") == "1":
            raise RuntimeError("rasterio is missing; expected " + EXPECTED_RASTERIO_VERSION)
        return
    if rasterio.__version__ != EXPECTED_RASTERIO_VERSION:
        raise RuntimeError("rasterio " + rasterio.__version__ + " != " + EXPECTED_RASTERIO_VERSION)


def _check_input_manifest(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    source = data.get("source", {})
    if not isinstance(source, dict):
        raise ValueError(str(path.relative_to(ROOT)) + " source must be an object")
    source_url = str(source.get("url", ""))
    if source_url != EXPECTED_TNM_10M_SOURCE_URL:
        raise ValueError("unexpected Zion 10m source URL: " + source_url)
    _require_sha256(source, "sha256", "source")
    if int(source.get("bytes", 0)) <= 0:
        raise ValueError("source bytes must be positive")
    clip = data.get("clip", {})
    if not isinstance(clip, dict):
        raise ValueError(str(path.relative_to(ROOT)) + " clip must be an object")
    if str(clip.get("path", "")) != "data/bake_inputs/zion_dem_10m_corridor.tif":
        raise ValueError("unexpected Zion clipped DEM path: " + str(clip.get("path", "")))
    _require_sha256(clip, "sha256", "clip")
    if int(clip.get("width", 0)) <= 0 or int(clip.get("height", 0)) <= 0:
        raise ValueError("clip dimensions must be positive")


def _check_output_manifest(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    _check_output_shape(path, data)
    _check_manifest(path, base_dir=ROOT)


def _check_manifest(path: Path, base_dir: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = _manifest_entries(data)
    if not entries:
        raise ValueError(str(path.relative_to(ROOT)) + " has no hash entries")
    for filename, expected_sha in entries:
        artifact_path = _resolve_manifest_path(filename, base_dir)
        if not artifact_path.is_file():
            raise FileNotFoundError("manifest artifact is missing: " + str(artifact_path.relative_to(ROOT)))
        actual_sha = _sha256(artifact_path)
        if actual_sha != expected_sha:
            raise ValueError(
                "sha256 mismatch for "
                + str(artifact_path.relative_to(ROOT))
                + ": "
                + actual_sha
                + " != "
                + expected_sha
            )


def _manifest_entries(data: dict[str, Any]) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for key in ("files", "artifacts"):
        values = data.get(key, [])
        if isinstance(values, list):
            for value in values:
                if isinstance(value, dict):
                    filename = str(value.get("path", value.get("filename", "")))
                    sha = str(value.get("sha256", ""))
                    if filename and sha:
                        entries.append((filename, sha))
    for key in ("heightmap_sha256", "surface_id_sha256", "collision_sha256"):
        values = data.get(key, {})
        if isinstance(values, dict):
            for filename, sha in values.items():
                entries.append((str(filename), str(sha)))
    return entries


def _check_output_shape(path: Path, data: dict[str, Any]) -> None:
    if data.get("region_id") != "cedar_hollow_zion":
        raise ValueError(str(path.relative_to(ROOT)) + " region_id must be cedar_hollow_zion")
    if data.get("tile_grid") != [EXPECTED_TILE_COLS, EXPECTED_TILE_ROWS]:
        raise ValueError(str(path.relative_to(ROOT)) + " tile_grid must be [55, 57]")
    files = data.get("files", [])
    if not isinstance(files, list):
        raise ValueError(str(path.relative_to(ROOT)) + " files must be a list")
    roles: dict[str, int] = {}
    for entry in files:
        if not isinstance(entry, dict):
            raise ValueError(str(path.relative_to(ROOT)) + " file entry must be an object")
        role = str(entry.get("role", ""))
        roles[role] = roles.get(role, 0) + 1
        _require_sha256(entry, "sha256", "output file")
    for role, expected_count in EXPECTED_OUTPUT_ROLES.items():
        actual_count = roles.get(role, 0)
        if actual_count != expected_count:
            raise ValueError(role + " count " + str(actual_count) + " != " + str(expected_count))
    expected_total = sum(EXPECTED_OUTPUT_ROLES.values())
    if len(files) != expected_total:
        raise ValueError("output manifest file count " + str(len(files)) + " != " + str(expected_total))


def _require_sha256(data: dict[str, Any], key: str, label: str) -> None:
    value = str(data.get(key, ""))
    if SHA256_RE.fullmatch(value) is None:
        raise ValueError(label + " " + key + " must be a lowercase SHA-256")


def _resolve_manifest_path(filename: str, base_dir: Path) -> Path:
    path = Path(filename)
    if path.is_absolute():
        return path
    root_candidate = ROOT / path
    if root_candidate.exists():
        return root_candidate
    return base_dir / path


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
