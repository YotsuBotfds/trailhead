#!/usr/bin/env bash
# review_recording.sh — intake a screen-record for visual + hitch QA in one command.
#
# Extracts frames, runs ffmpeg freezedetect (the hitch ground-truth), and splits the
# frames into 40-frame batches ready for dense codex-mini frame-QA. Read-only; writes
# only under /tmp. POSIX-sh parseable (check.sh runs `sh -n` over tools/*.sh).
#
# Usage:  bash tools/review_recording.sh <recording.mov> [label]
#   e.g.  bash tools/review_recording.sh ~/Desktop/take2.mov take2
# Then dense-QA: codex-mini over the /tmp/th_review_<label>/batch_* lists (see the
# capture-frame-by-frame + codex-vision-frame-qa memories), and read freezedetect.txt
# against the prior baseline (dogshit.mov: 4.7s freeze @16.7s + recurring 0.1-0.35s).
set -u

REC="${1:-}"
LABEL="${2:-rec}"
if [ -z "$REC" ] || [ ! -f "$REC" ]; then
	echo "usage: bash tools/review_recording.sh <recording.mov> [label]   (file not found: '$REC')"
	exit 1
fi
OUT="/tmp/th_review_${LABEL}"
rm -rf "$OUT"; mkdir -p "$OUT/frames"

echo "== probe =="
ffprobe -v error -select_streams v:0 \
	-show_entries stream=width,height,r_frame_rate,nb_frames,duration \
	-of default=noprint_wrappers=1 "$REC"

echo ""
echo "== freezedetect (frozen-frame runs = visual hitches) -> $OUT/freezedetect.txt =="
ffmpeg -nostdin -i "$REC" -vf "freezedetect=n=0.003:d=0.05" -map 0:v -f null - 2>&1 \
	| grep -E 'freeze_(start|duration|end)' | tee "$OUT/freezedetect.txt"
echo "freeze events: $(grep -c freeze_start "$OUT/freezedetect.txt" 2>/dev/null || echo 0)"

echo ""
echo "== extract every frame (native fps, scaled to 1280w) =="
ffmpeg -nostdin -i "$REC" -vf "scale=1280:-2" -q:v 3 "$OUT/frames/f_%05d.png" >/dev/null 2>&1
n=$(ls "$OUT/frames"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "frames extracted: $n  -> $(( (n + 39) / 40 )) batches of 40"

echo ""
echo "== split into 40-frame batch lists for codex-mini dense QA =="
ls "$OUT/frames"/*.png | split -l 40 - "$OUT/batch_"
echo "DONE: $OUT  (frames/, freezedetect.txt, batch_aa.. lists)"
