#!/usr/bin/env bash
# Reusable driving-POV capture for fidelity review.
#   usage: bash tools/capture_drive.sh <out_subdir> [duration_s]
# Warms import (cold cache => blank scene), movie-captures a drive, extracts DENSE 30fps frames.
# Per the standing directive: every final capture is reviewed frame-by-frame (30fps), never sparse.
set -uo pipefail
sub="${1:-after_capture}"
dur="${2:-16}"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out="tests/out/$sub"
rm -rf "$out"; mkdir -p "$out/frames"

echo "[1/3] warming import cache..."
"$godot_bin" --headless --import --path . >/dev/null 2>&1 || true
# A headless --import re-saves project.godot (drops default-valued keys); keep main pristine.
git checkout project.godot >/dev/null 2>&1 || true

echo "[2/3] movie-capturing driving pass (${dur}s)..."
defaults write org.godotengine.godot NSAppSleepDisabled -bool true || true
caffeinate -dimsu "$godot_bin" --audio-driver Dummy --path . res://tools/perf_autodrive.tscn \
  --write-movie "$out/drive.avi" -- --duration="$dur" --steer-strength=0.18 >/dev/null 2>&1 || true

echo "[3/3] extracting dense 30fps frames + trimming the cold-start cover..."
if [ -f "$out/drive.avi" ]; then
  ffmpeg -y -i "$out/drive.avi" -vf "fps=30" "$out/frames/f_%04d.png" >/dev/null 2>&1 || true
  # The cold-start title-card cover (near-black) holds at the start until the world streams in.
  # Drop every leading frame whose mean brightness is below the reveal threshold, then renumber,
  # so the captured frames start at the moment the car actually drives the revealed world.
  python3 - "$out/frames" <<'PY' || true
import sys, os, glob, struct, zlib
d = sys.argv[1]
def mean_brightness(p):
    # cheap PNG mean luma via Pillow if present, else a coarse file-size proxy
    try:
        from PIL import Image
        im = Image.open(p).convert("L").resize((64,36))
        px = list(im.getdata()); return sum(px)/len(px)
    except Exception:
        return os.path.getsize(p)/1000.0
frames = sorted(glob.glob(os.path.join(d, "f_*.png")))
THRESH = 40.0  # luma; cover ~ <15, revealed world ~ >80 (file-size proxy fallback: ~120)
first = 0
for i,f in enumerate(frames):
    if mean_brightness(f) >= THRESH:
        first = i; break
else:
    first = 0
dropped = frames[:first]
kept = frames[first:]
for f in dropped: os.remove(f)
for i,f in enumerate(kept, start=1):
    os.rename(f, os.path.join(d, "tmp_%04d.png" % i))
for i in range(1, len(kept)+1):
    os.rename(os.path.join(d, "tmp_%04d.png" % i), os.path.join(d, "f_%04d.png" % i))
print("trimmed %d cover frames; kept %d drive frames" % (len(dropped), len(kept)))
PY
  n=$(ls "$out/frames"/*.png 2>/dev/null | wc -l | tr -d ' ')
  echo "DONE: $n drive frames at 30fps in $out/frames"
else
  echo "FAIL: no movie written to $out/drive.avi"
fi
