#!/usr/bin/env python3
import argparse
import hashlib
import html
import json
import math
import struct
import sys
import zlib
from pathlib import Path

EXPECTED_CAPTURE_NAMES = [
    "trailhead_dusk_chase",
    "trailhead_dusk_chase_map",
    "meadow_dusk_chase",
    "meadow_dusk_orbit",
    "bog_bottom_dusk_chase",
    "crossing_dawn_chase",
    "boardwalk_dusk_chase",
    "boardwalk_dusk_fpv",
    "overlook_dusk_orbit",
    "old_cedar_dusk_chase",
]

CAPTURE_LABELS = {
    "trailhead_dusk_chase": "Trailhead dusk chase",
    "trailhead_dusk_chase_map": "Trailhead dusk with map",
    "meadow_dusk_chase": "Meadow low chase",
    "meadow_dusk_orbit": "Meadow orbit",
    "bog_bottom_dusk_chase": "Bog bottom dusk chase",
    "crossing_dawn_chase": "Crossing dawn chase",
    "boardwalk_dusk_chase": "Boardwalk dusk chase",
    "boardwalk_dusk_fpv": "Boardwalk FPV",
    "overlook_dusk_orbit": "Overlook orbit",
    "old_cedar_dusk_chase": "Old Cedar dusk chase",
}

CAPTURE_REVIEW_FOCUS = {
    "trailhead_dusk_chase": "Default low chase framing, trailhead prop scale, and clear route exit.",
    "trailhead_dusk_chase_map": "Optional map visibility without dominating the primary driving view.",
    "meadow_dusk_chase": "Grass occluders, low-camera scale, and route readability through meadow scatter.",
    "meadow_dusk_orbit": "Secondary orbit camera usefulness for inspecting the same meadow composition.",
    "bog_bottom_dusk_chase": "Mud pocket readability, tire scale, and safe grass height near the route.",
    "crossing_dawn_chase": "Dawn comparison, creek crossing silhouette, wet-stone contrast, and mood legibility.",
    "boardwalk_dusk_chase": "Wood-plank path clarity, rail/gap readability, and low-camera obstacle scale.",
    "boardwalk_dusk_fpv": "FPV camera utility and boardwalk surface legibility from the tighter view.",
    "overlook_dusk_orbit": "Ridge silhouette, long-shadow mood, and distant route composition.",
    "old_cedar_dusk_chase": "Destination landmark scale, final approach readability, and vehicle silhouette.",
}

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_COLOR_CHANNELS = {
    0: 1,
    2: 3,
    6: 4,
}
STATS_SAMPLE_STEP = 16
EXPECTED_CAPTURE_WIDTH = 1280
EXPECTED_CAPTURE_HEIGHT = 720
MIN_LUMA_RANGE = 0.15
MIN_LUMA_STDDEV = 0.03
MIN_CHROMA_MEAN = 0.04


def parse_args():
    parser = argparse.ArgumentParser(description="Build an HTML review sheet for Trailhead visual QA captures.")
    parser.add_argument("--capture-dir", type=Path, default=Path("tests/out/visual_qa"), help="Directory containing the exact visual QA PNG set.")
    parser.add_argument("--out", type=Path, default=None, help="HTML report path. Defaults to <capture-dir>/index.html.")
    parser.add_argument("--manifest", type=Path, default=None, help="JSON manifest path. Defaults to <capture-dir>/manifest.json.")
    return parser.parse_args()


def png_dimensions(path):
    with path.open("rb") as file:
        header = file.read(24)
    if len(header) < 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValueError("not a valid PNG with IHDR header")
    return struct.unpack(">II", header[16:24])


def png_stats(path):
    width, height, bit_depth, color_type, compressed = _read_png_payload(path)
    if bit_depth != 8:
        raise ValueError("unsupported PNG bit depth for stats: " + str(bit_depth))
    if color_type not in PNG_COLOR_CHANNELS:
        raise ValueError("unsupported PNG color type for stats: " + str(color_type))
    channels = PNG_COLOR_CHANNELS[color_type]
    row_bytes = width * channels
    raw = zlib.decompress(compressed)
    expected_size = height * (row_bytes + 1)
    if len(raw) != expected_size:
        raise ValueError("unexpected PNG decompressed size")

    previous = bytearray(row_bytes)
    count = 0
    luma_sum = 0.0
    luma_sum_sq = 0.0
    luma_min = 999999.0
    luma_max = -999999.0
    chroma_sum = 0.0
    for y in range(height):
        offset = y * (row_bytes + 1)
        filter_type = raw[offset]
        row = bytearray(raw[offset + 1:offset + 1 + row_bytes])
        _unfilter_png_row(row, previous, channels, filter_type)
        if y % STATS_SAMPLE_STEP == 0:
            for x in range(0, width, STATS_SAMPLE_STEP):
                pixel_index = x * channels
                if color_type == 0:
                    r = row[pixel_index]
                    g = r
                    b = r
                else:
                    r = row[pixel_index]
                    g = row[pixel_index + 1]
                    b = row[pixel_index + 2]
                luma = (
                    float(r) * 0.2126
                    + float(g) * 0.7152
                    + float(b) * 0.0722
                ) / 255.0
                chroma = float(max(r, g, b) - min(r, g, b)) / 255.0
                luma_sum += luma
                luma_sum_sq += luma * luma
                luma_min = min(luma_min, luma)
                luma_max = max(luma_max, luma)
                chroma_sum += chroma
                count += 1
        previous = row
    if count == 0:
        raise ValueError("PNG has no pixels to sample")
    luma_mean = luma_sum / float(count)
    luma_variance = max(luma_sum_sq / float(count) - luma_mean * luma_mean, 0.0)
    return {
        "sample_step": STATS_SAMPLE_STEP,
        "sample_count": count,
        "luma_mean": round(luma_mean, 4),
        "luma_min": round(luma_min, 4),
        "luma_max": round(luma_max, 4),
        "luma_range": round(luma_max - luma_min, 4),
        "luma_stddev": round(math.sqrt(luma_variance), 4),
        "chroma_mean": round(chroma_sum / float(count), 4),
    }


def _read_png_payload(path):
    with path.open("rb") as file:
        signature = file.read(8)
        if signature != PNG_SIGNATURE:
            raise ValueError("not a valid PNG signature")
        width = 0
        height = 0
        bit_depth = 0
        color_type = 0
        idat_chunks = []
        while True:
            length_bytes = file.read(4)
            if len(length_bytes) == 0:
                break
            if len(length_bytes) != 4:
                raise ValueError("truncated PNG chunk length")
            length = struct.unpack(">I", length_bytes)[0]
            chunk_type = file.read(4)
            if len(chunk_type) != 4:
                raise ValueError("truncated PNG chunk type")
            chunk_data = file.read(length)
            if len(chunk_data) != length:
                raise ValueError("truncated PNG chunk data")
            crc = file.read(4)
            if len(crc) != 4:
                raise ValueError("truncated PNG chunk checksum")
            if chunk_type == b"IHDR":
                width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(
                    ">IIBBBBB",
                    chunk_data,
                )
                if compression != 0 or filter_method != 0 or interlace != 0:
                    raise ValueError("unsupported PNG compression/filter/interlace mode")
            elif chunk_type == b"IDAT":
                idat_chunks.append(chunk_data)
            elif chunk_type == b"IEND":
                break
        if width <= 0 or height <= 0:
            raise ValueError("PNG missing IHDR dimensions")
        if not idat_chunks:
            raise ValueError("PNG missing IDAT image data")
        return width, height, bit_depth, color_type, b"".join(idat_chunks)


def _unfilter_png_row(row, previous, channels, filter_type):
    if filter_type == 0:
        return
    if filter_type == 1:
        for i in range(len(row)):
            left = row[i - channels] if i >= channels else 0
            row[i] = (row[i] + left) & 0xff
        return
    if filter_type == 2:
        for i in range(len(row)):
            row[i] = (row[i] + previous[i]) & 0xff
        return
    if filter_type == 3:
        for i in range(len(row)):
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            row[i] = (row[i] + ((left + up) // 2)) & 0xff
        return
    if filter_type == 4:
        for i in range(len(row)):
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            up_left = previous[i - channels] if i >= channels else 0
            row[i] = (row[i] + _paeth_predictor(left, up, up_left)) & 0xff
        return
    raise ValueError("unsupported PNG filter type: " + str(filter_type))


def _paeth_predictor(left, up, up_left):
    estimate = left + up - up_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    up_left_distance = abs(estimate - up_left)
    if left_distance <= up_distance and left_distance <= up_left_distance:
        return left
    if up_distance <= up_left_distance:
        return up
    return up_left


def sha256_digest(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        while True:
            chunk = file.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def capture_manifest(capture_dir):
    errors = []
    observed_pngs = sorted(path.name for path in capture_dir.glob("*.png"))
    expected_pngs = [name + ".png" for name in EXPECTED_CAPTURE_NAMES]
    for expected_png in expected_pngs:
        if expected_png not in observed_pngs:
            errors.append("missing expected capture: " + str(capture_dir / expected_png))
    for observed_png in observed_pngs:
        if observed_png not in expected_pngs:
            errors.append("unexpected capture PNG: " + str(capture_dir / observed_png))
    if errors:
        return [], errors

    captures = []
    for capture_name in EXPECTED_CAPTURE_NAMES:
        filename = capture_name + ".png"
        path = capture_dir / filename
        try:
            width, height = png_dimensions(path)
        except ValueError as exc:
            errors.append(str(path) + " " + str(exc))
            continue
        size_bytes = path.stat().st_size
        capture = {
            "name": capture_name,
            "label": CAPTURE_LABELS[capture_name],
            "review_focus": CAPTURE_REVIEW_FOCUS[capture_name],
            "filename": filename,
            "width": width,
            "height": height,
            "size_bytes": size_bytes,
            "sha256": sha256_digest(path),
            "image_stats": png_stats(path),
        }
        _validate_capture_sanity(capture, errors)
        captures.append(capture)
    return captures, errors


def _validate_capture_sanity(capture, errors):
    name = capture["name"]
    if capture["width"] != EXPECTED_CAPTURE_WIDTH or capture["height"] != EXPECTED_CAPTURE_HEIGHT:
        errors.append(
            f"{name} expected {EXPECTED_CAPTURE_WIDTH}x{EXPECTED_CAPTURE_HEIGHT}, "
            f"got {capture['width']}x{capture['height']}"
        )
    stats = capture["image_stats"]
    if stats["luma_range"] < MIN_LUMA_RANGE:
        errors.append(f"{name} luma range {stats['luma_range']} < {MIN_LUMA_RANGE}")
    if stats["luma_stddev"] < MIN_LUMA_STDDEV:
        errors.append(f"{name} luma stddev {stats['luma_stddev']} < {MIN_LUMA_STDDEV}")
    if stats["chroma_mean"] < MIN_CHROMA_MEAN:
        errors.append(f"{name} chroma mean {stats['chroma_mean']} < {MIN_CHROMA_MEAN}")


def write_manifest(path, captures):
    data = {
        "capture_count": len(captures),
        "expected_capture_names": EXPECTED_CAPTURE_NAMES,
        "captures": captures,
    }
    path.write_text(json.dumps(data, indent=2) + "\n")


def write_html(path, captures):
    cards = []
    for capture in captures:
        label = html.escape(capture["label"])
        filename = html.escape(capture["filename"])
        details = (
            f'{capture["width"]}x{capture["height"]} - {capture["size_bytes"]} bytes '
            f'- sha256 {capture["sha256"][:12]}'
        )
        stats = capture["image_stats"]
        stat_details = (
            f'luma mean {stats["luma_mean"]} - luma range {stats["luma_range"]} '
            f'- chroma mean {stats["chroma_mean"]}'
        )
        focus = html.escape(capture["review_focus"])
        cards.append(
            f"""
      <article>
        <a href="{filename}"><img src="{filename}" alt="{label}"></a>
        <h2>{label}</h2>
        <p class="meta">{html.escape(details)}</p>
        <p class="meta">{html.escape(stat_details)}</p>
        <p>{focus}</p>
      </article>"""
        )
    path.write_text(
        f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Trailhead Visual QA</title>
  <style>
    :root {{
      color-scheme: light;
      --page: #f5f7f2;
      --panel: #ffffff;
      --text: #1f241f;
      --muted: #626b61;
      --line: #d7dfd2;
      --accent: #416b43;
      --accent-soft: #dfe9d9;
    }}
    body {{
      margin: 0;
      font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--text);
      background: var(--page);
    }}
    header {{
      padding: 24px 28px 14px;
      border-bottom: 1px solid var(--line);
      background: var(--panel);
    }}
    h1 {{
      margin: 0 0 6px;
      font-size: 28px;
      letter-spacing: 0;
    }}
    header p {{
      margin: 0;
      color: var(--muted);
    }}
    .summary {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 14px;
    }}
    .summary span {{
      padding: 4px 8px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--accent-soft);
      color: var(--accent);
      font-size: 13px;
      font-weight: 600;
    }}
    main {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 18px;
      padding: 18px 28px 32px;
    }}
    article {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
      box-shadow: 0 1px 2px rgba(31, 36, 31, 0.06);
    }}
    img {{
      display: block;
      width: 100%;
      aspect-ratio: 16 / 9;
      object-fit: cover;
      background: var(--line);
    }}
    h2 {{
      margin: 12px 14px 2px;
      font-size: 16px;
      letter-spacing: 0;
    }}
    article p {{
      margin: 6px 14px 14px;
      color: var(--muted);
    }}
    article p.meta {{
      margin-bottom: 0;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
      font-size: 12px;
      color: #3d463d;
      overflow-wrap: anywhere;
    }}
  </style>
</head>
<body>
  <header>
    <h1>Trailhead Visual QA</h1>
    <p>Exact capture set for low-camera readability, mood, surface, and landmark review.</p>
    <div class="summary">
      <span>{len(captures)} captures</span>
      <span>1280x720 target</span>
      <span>hashes + stats gates</span>
    </div>
  </header>
  <main>{"".join(cards)}
  </main>
</body>
</html>
""")


def main():
    args = parse_args()
    capture_dir = args.capture_dir
    if not capture_dir.is_dir():
        print("fail: missing capture directory: " + str(capture_dir), file=sys.stderr)
        return 1
    captures, errors = capture_manifest(capture_dir)
    if errors:
        print("fail: visual QA capture set is not exact", file=sys.stderr)
        for error in errors:
            print("- " + error, file=sys.stderr)
        return 1
    out_path = args.out if args.out is not None else capture_dir / "index.html"
    manifest_path = args.manifest if args.manifest is not None else capture_dir / "manifest.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    write_manifest(manifest_path, captures)
    write_html(out_path, captures)
    print("ok: wrote visual QA report: " + str(out_path))
    print("ok: wrote visual QA manifest: " + str(manifest_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
