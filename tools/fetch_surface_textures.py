#!/usr/bin/env python3
"""Fetch curated CC0 ambientCG surface textures for Trailhead render materials."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from tempfile import TemporaryDirectory

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover - local tooling guard.
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from exc


PROJECT_ROOT = Path(__file__).resolve().parents[1]
API_URL = "https://ambientCG.com/api/v3/assets"
LICENSE_URL = "https://docs.ambientcg.com/license/"
DOWNLOAD_ATTRIBUTES = "1K-JPG"
ALBEDO_QUALITY = 88
NORMAL_QUALITY = 92


@dataclass(frozen=True)
class TextureCandidate:
    visual_id: str
    asset_id: str


CANDIDATES: tuple[TextureCandidate, ...] = (
    TextureCandidate("packed_gravel_default", "Gravel043"),
    TextureCandidate("packed_dirt_default", "Ground103"),
    TextureCandidate("pine_floor_dirt", "Ground078"),
    TextureCandidate("tall_grass_default", "Grass001"),
    TextureCandidate("mud_default", "Ground036"),
    TextureCandidate("dried_mud", "Ground025"),
    TextureCandidate("loose_rock_default", "Ground081"),
    TextureCandidate("wet_stone_default", "Ground068"),
    TextureCandidate("mossy_wet_stone", "Rock064"),
    TextureCandidate("wood_plank_default", "Planks037A"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", type=int, default=1024, help="maximum output texture dimension")
    parser.add_argument("--force", action="store_true", help="redownload archives and rewrite derived textures")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw_dir = PROJECT_ROOT / "assets" / "generated" / "ambientcg"
    output_dir = PROJECT_ROOT / "assets" / "textures" / "surface_visuals" / "ambientcg"
    raw_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    records: list[dict[str, object]] = []
    metadata = fetch_metadata([candidate.asset_id for candidate in CANDIDATES])
    for candidate in CANDIDATES:
        asset = metadata.get(candidate.asset_id)
        if asset is None:
            raise RuntimeError("ambientCG API did not return " + candidate.asset_id)
        download = find_download(asset)
        archive_path = raw_dir / f"{candidate.asset_id}_{DOWNLOAD_ATTRIBUTES}.zip"
        if args.force or not archive_path.exists():
            download_file(str(download["url"]), archive_path)
        archive_sha256 = sha256_file(archive_path)
        albedo_source, normal_source = extract_sources(archive_path)
        albedo_output = output_dir / f"{candidate.visual_id}_albedo.jpg"
        normal_output = output_dir / f"{candidate.visual_id}_normal.jpg"
        if args.force or not albedo_output.exists():
            write_texture(albedo_source, albedo_output, args.size, ALBEDO_QUALITY)
        if args.force or not normal_output.exists():
            write_texture(normal_source, normal_output, args.size, NORMAL_QUALITY)
        records.append({
            "visual_id": candidate.visual_id,
            "asset_id": candidate.asset_id,
            "title": str(asset.get("title", candidate.asset_id)),
            "source_url": str(asset.get("url", "https://ambientcg.com/a/" + candidate.asset_id)),
            "archive_url": str(download["url"]),
            "archive_size": int(download.get("size", 0)),
            "archive_sha256": archive_sha256,
            "albedo": to_res_path(albedo_output),
            "normal": to_res_path(normal_output),
        })

    write_sources(output_dir / "SOURCES.md", records, args.size)
    print("Wrote", len(records), "surface texture sets to", output_dir)
    return 0


def fetch_metadata(asset_ids: list[str]) -> dict[str, dict[str, object]]:
    query = urllib.parse.urlencode({
        "type": "material",
        "include": "downloads,title,url",
        "limit": "500",
        "id": ",".join(asset_ids),
    })
    with urllib.request.urlopen(API_URL + "?" + query, timeout=60) as response:
        payload = json.load(response)
    assets: dict[str, dict[str, object]] = {}
    for asset in payload.get("assets", []):
        if isinstance(asset, dict):
            asset_id = str(asset.get("id", ""))
            if asset_id:
                assets[asset_id] = asset
    return assets


def find_download(asset: dict[str, object]) -> dict[str, object]:
    downloads = asset.get("downloads", [])
    if not isinstance(downloads, list):
        raise RuntimeError("downloads missing for " + str(asset.get("id", "")))
    for download in downloads:
        if not isinstance(download, dict):
            continue
        if download.get("attributes") == DOWNLOAD_ATTRIBUTES and download.get("extension") == "zip":
            return download
    raise RuntimeError("missing " + DOWNLOAD_ATTRIBUTES + " zip for " + str(asset.get("id", "")))


def download_file(url: str, output_path: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "Trailhead asset fetcher"})
    with urllib.request.urlopen(request, timeout=180) as response:
        output_path.write_bytes(response.read())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def extract_sources(archive_path: Path) -> tuple[Path, Path]:
    with TemporaryDirectory() as temp_dir_name:
        temp_dir = Path(temp_dir_name)
        with zipfile.ZipFile(archive_path) as archive:
            archive.extractall(temp_dir)
        albedo = find_map(temp_dir, ("_color.", "_basecolor.", "_albedo.", "_diffuse."))
        normal = find_map(temp_dir, ("_normalgl.", "_normal."))
        copied_albedo = archive_path.with_suffix(".Color.jpg")
        copied_normal = archive_path.with_suffix(".NormalGL.jpg")
        copied_albedo.write_bytes(albedo.read_bytes())
        copied_normal.write_bytes(normal.read_bytes())
        return copied_albedo, copied_normal


def find_map(root: Path, suffixes: tuple[str, ...]) -> Path:
    matches: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        lower_name = path.name.lower()
        if any(suffix in lower_name for suffix in suffixes):
            matches.append(path)
    if not matches:
        raise RuntimeError("missing texture map with suffixes " + ", ".join(suffixes))
    matches.sort(key=lambda candidate: len(str(candidate)))
    return matches[0]


def write_texture(source_path: Path, output_path: Path, max_size: int, quality: int) -> None:
    with Image.open(source_path) as image:
        output = image.convert("RGB")
        largest = max(output.size)
        if largest > max_size:
            scale = float(max_size) / float(largest)
            size = (round(output.size[0] * scale), round(output.size[1] * scale))
            output = output.resize(size, Image.Resampling.LANCZOS)
        output.save(output_path, format="JPEG", quality=quality, optimize=True, progressive=True)


def write_sources(path: Path, records: list[dict[str, object]], texture_size: int) -> None:
    lines: list[str] = [
        "# Surface Texture Sources",
        "",
        "Generated by `tools/fetch_surface_textures.py`.",
        "",
        f"- Download date: {date.today().isoformat()}",
        f"- License: ambientCG assets are distributed under Creative Commons CC0 1.0 Universal, per {LICENSE_URL}",
        f"- Source archives: `{DOWNLOAD_ATTRIBUTES}` ambientCG zips retained under ignored `assets/generated/ambientcg/`.",
        f"- Derived maps: JPEG, max dimension {texture_size}px, albedo quality {ALBEDO_QUALITY}, normal quality {NORMAL_QUALITY}.",
        "",
        "| Visual id | ambientCG asset | Source | Raw zip SHA-256 | Maps |",
        "|---|---|---|---|---|",
    ]
    for record in records:
        maps = f"{record['albedo']}<br>{record['normal']}"
        lines.append(
            "| {visual_id} | {title} (`{asset_id}`) | [asset]({source_url}) / [zip]({archive_url}) | `{archive_sha256}` | {maps} |".format(
                **record,
                maps=maps,
            )
        )
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def to_res_path(path: Path) -> str:
    return "res://" + path.relative_to(PROJECT_ROOT).as_posix()


if __name__ == "__main__":
    sys.exit(main())
