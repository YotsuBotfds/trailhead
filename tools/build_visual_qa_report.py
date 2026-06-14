#!/usr/bin/env python3
import argparse
import html
import json
import struct
import sys
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


def parse_args():
    parser = argparse.ArgumentParser(description="Build an HTML review sheet for Trailhead visual QA captures.")
    parser.add_argument("--capture-dir", type=Path, default=Path("tests/out/visual_qa"), help="Directory containing the exact visual QA PNG set.")
    parser.add_argument("--out", type=Path, default=None, help="HTML report path. Defaults to <capture-dir>/index.html.")
    parser.add_argument("--manifest", type=Path, default=None, help="JSON manifest path. Defaults to <capture-dir>/manifest.json.")
    return parser.parse_args()


def png_dimensions(path):
    with path.open("rb") as file:
        header = file.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("not a valid PNG with IHDR header")
    return struct.unpack(">II", header[16:24])


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
        captures.append({
            "name": capture_name,
            "label": CAPTURE_LABELS[capture_name],
            "filename": filename,
            "width": width,
            "height": height,
            "size_bytes": size_bytes,
        })
    return captures, errors


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
        details = f'{capture["width"]}x{capture["height"]} - {capture["size_bytes"]} bytes'
        cards.append(
            f"""
      <article>
        <a href="{filename}"><img src="{filename}" alt="{label}"></a>
        <h2>{label}</h2>
        <p>{html.escape(details)}</p>
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
    body {{
      margin: 0;
      font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #1f211b;
      background: #f3f0e7;
    }}
    header {{
      padding: 24px 28px 12px;
    }}
    h1 {{
      margin: 0 0 6px;
      font-size: 28px;
      letter-spacing: 0;
    }}
    header p {{
      margin: 0;
      color: #57584e;
    }}
    main {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 18px;
      padding: 18px 28px 32px;
    }}
    article {{
      background: #fffaf0;
      border: 1px solid #d8d1c1;
      border-radius: 8px;
      overflow: hidden;
    }}
    img {{
      display: block;
      width: 100%;
      aspect-ratio: 16 / 9;
      object-fit: cover;
      background: #d8d1c1;
    }}
    h2 {{
      margin: 12px 14px 2px;
      font-size: 16px;
      letter-spacing: 0;
    }}
    article p {{
      margin: 0 14px 14px;
      color: #62635b;
    }}
  </style>
</head>
<body>
  <header>
    <h1>Trailhead Visual QA</h1>
    <p>Exact capture set for low-camera readability, mood, surface, and landmark review.</p>
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
