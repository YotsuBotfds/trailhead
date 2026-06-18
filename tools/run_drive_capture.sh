#!/usr/bin/env bash
set -euo pipefail

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
out_root="${OUT_ROOT:-tests/out/drive_capture}"
spawn="${SPAWN:-stream_west}"

# Runs windowed, not --headless, because this tool captures real rendered
# gameplay-POV frames from the GPU. --audio-driver Dummy avoids audible output
# while keeping the audio server initialized (mirrors run_perf_drive.sh).
#
# With no env overrides, the GDScript default cadence is used verbatim
# (drive_t04/09/15/22/30_chase plus a t15 lookback). Set DURATION and/or SHOTS
# to switch to evenly-spaced capture fractions of the drive.
args=(--out-root="$out_root" --spawn="$spawn")
if [ -n "${DURATION:-}" ]; then args+=("--duration=$DURATION"); fi
if [ -n "${SHOTS:-}" ]; then args+=("--shots=$SHOTS"); fi

"$godot_bin" --audio-driver Dummy --path . res://tools/drive_capture.tscn -- "${args[@]}"
