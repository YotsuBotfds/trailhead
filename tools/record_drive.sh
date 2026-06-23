#!/usr/bin/env bash
# record_drive.sh — REAL-TIME screen recording of the windowed auto-drive.
#
# `--write-movie` renders frames offline, so it HIDES exactly what we hunt: present-path
# hitches, terrain pop-in, and the threaded foliage streamer falling behind. This records
# the LIVE rendered window with ffmpeg avfoundation (the way a human screen-records), then
# runs review_recording.sh over it (frames + ffmpeg freezedetect + dense-QA batches) so the
# captured video can be reviewed frame-by-frame.
#
# Requires macOS Screen Recording permission for the controlling terminal + a display
# (caffeinate -d wakes it). ONE Godot at a time — never run this alongside the headless
# suite or another capture. POSIX-sh parseable (check.sh runs `sh -n` over tools/*.sh).
#
# Usage:  bash tools/record_drive.sh [label]
#   env:  DURATION=40  SCREEN_DEV=3  GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
set -u

LABEL="${1:-drive}"
DURATION="${DURATION:-40}"
SCREEN_DEV="${SCREEN_DEV:-3}"            # ffmpeg avfoundation "[3] Capture screen 0"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
REC="/tmp/th_rec_${LABEL}.mov"
REC_SECONDS=$(( DURATION + 10 ))         # startup buffer; recorder is killed when the drive exits

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

# Warm the import cache so we never record a blank scene (a cold cache => failed GLB preloads
# => the world never renders => a bogus "smooth" recording of nothing).
"$GODOT_BIN" --headless --import --path . >/dev/null 2>&1 || true
# Keep windowed Godot in the foreground present-path (App Nap throttles backgrounded layers).
defaults write org.godotengine.godot NSAppSleepDisabled -bool true 2>/dev/null || true

echo "record_drive: capturing screen device ${SCREEN_DEV} for up to ${REC_SECONDS}s -> ${REC}"
caffeinate -d ffmpeg -hide_banner -nostdin -y -f avfoundation -capture_cursor 0 -framerate 30 \
	-i "${SCREEN_DEV}:none" -t "${REC_SECONDS}" "${REC}" >"/tmp/th_rec_${LABEL}_ffmpeg.log" 2>&1 &
rec_pid=$!

# Real-time windowed auto-drive (audio dummied; the harness pulls the window foreground + on-top).
caffeinate -dimsu "$GODOT_BIN" --audio-driver Dummy --path . res://tools/perf_autodrive.tscn -- \
	--out-root="tests/out/perf" --duration="${DURATION}" --hitch-threshold-ms=20 --steer-strength=0.18 \
	>"/tmp/th_rec_${LABEL}_drive.log" 2>&1 || true

# Drive finished (or errored) — stop the recorder and let ffmpeg flush the file.
kill "$rec_pid" 2>/dev/null || true
wait "$rec_pid" 2>/dev/null || true
echo "record_drive: drive complete; recording at ${REC}"

if [ -f "$REC" ]; then
	bash tools/review_recording.sh "$REC" "$LABEL" || true
	echo "record_drive: review under /tmp/th_review_${LABEL}/ (frames/, freezedetect.txt, batch_* lists)"
else
	echo "record_drive: ERROR no recording produced at ${REC} (screen-record permission? display asleep?)"
	tail -20 "/tmp/th_rec_${LABEL}_ffmpeg.log" 2>/dev/null || true
fi
