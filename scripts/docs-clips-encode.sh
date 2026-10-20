#!/usr/bin/env bash
# Cuts and encodes one guide clip (WS6 section 6): <recording.mov> <id> <recording start,
# epoch seconds> <exported attachments folder with the clip-start / clip-end markers>.
# Output: guide/public/clips/<id>.mp4 (H.264, 1280 px wide, 30 fps, no audio track, at most
# 1.5 MB) plus its poster (the last frame, AVIF) and the clip's entry in shots.json.
set -euo pipefail
cd "$(dirname "$0")/.."

raw="$1" id="$2" started="$3" attachments="$4"
marker() { # <name>: the marker's epoch time from the exported attachments
    local file
    # shellcheck disable=SC2016 # $name is a jq variable
    file=$(mise exec -- jq -r --arg name "$1" \
        '[.[].attachments[] | select(.suggestedHumanReadableName | startswith($name))][0].exportedFileName' \
        "$attachments/manifest.json")
    [[ -n "$file" && "$file" != null ]] || { echo "docs-clips: no $1 marker for $id" >&2; exit 1; }
    tr -d '[:space:]' <"$attachments/$file"
}
start=$(marker clip-start)
end=$(marker clip-end)
from=$(perl -e "printf '%.3f', $start - $started")
length=$(perl -e "printf '%.3f', $end - $start")

mkdir -p guide/public/clips .build/docs-shots/clips
mp4="guide/public/clips/$id.mp4"
mise exec -- ffmpeg -hide_banner -loglevel error -y -ss "$from" -t "$length" -i "$raw" \
    -vf "scale=1280:-2:flags=lanczos,fps=30,format=yuv420p" \
    -c:v libx264 -profile:v high -crf 28 -preset slow -an -movflags +faststart "$mp4"
size=$(stat -f %z "$mp4")
if ((size > 1536 * 1024)); then
    echo "docs-clips: $mp4 is $((size / 1024)) KB (budget 1.5 MB)" >&2
    exit 1
fi
poster=".build/docs-shots/clips/$id-poster.png"
mise exec -- ffmpeg -hide_banner -loglevel error -y -sseof -0.1 -i "$mp4" -frames:v 1 "$poster"
dims=$(mise exec -- ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
    -of csv=p=0 "$mp4")
scripts/docs-shots.swift --poster "$poster" --clip "$id" \
    --width "${dims%,*}" --height "${dims#*,}" --seconds "$length"
echo "docs-clips: $mp4 ($((size / 1024)) KB, ${length}s)"
