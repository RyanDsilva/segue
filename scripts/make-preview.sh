#!/usr/bin/env bash
# Edits the App Store preview (docs/release/specs/WS5-store-listing.md 9.4) from a raw
# screen recording, then checks it against Apple's spec (9.1).
#
#   scripts/make-preview.sh <raw.mov> <from seconds> <length seconds> [<timings file>]
#
# Cuts <length> seconds from <from>, scales it into a 1920x1080 frame at 30 fps under a
# caption band, overlays the caption
# PNGs that `compose-screenshots.swift --video-captions` renders (timed by the test's scene
# markers, or store/screenshots.json previewCaptions; 150 ms fades, nothing bounces), adds a silent
# stereo AAC track and encodes H.264 High@4.0 with libx264 (checked present in the pinned
# mise ffmpeg 9.0.2) to .build/preview/segue-preview-en-US.mp4. Exits non-zero if the
# result misses any of: 1920x1080, at most 30 fps, 15-30 s, H.264 High 4.0, stereo AAC,
# at most 500 MB.
set -euo pipefail
cd "$(dirname "$0")/.."

raw="$1" from="$2" length="$3"
out=".build/preview"
captions="$out/captions"
mp4="$out/segue-preview-en-US.mp4"
mkdir -p "$out"

scripts/compose-screenshots.swift --video-captions "$captions" \
    --captions store/screenshots.json --tokens design/tokens.json \
    --fonts Packages/SegueUI/Sources/SegueUI/Theme/Fonts

# One overlay per caption: id, from, to (seconds into the cut).
# Timings: <timings file> from the recorded run (one "id from to" line per caption, from the
# test's scene markers), else the storyboard's nominal times in store/screenshots.json.
if [[ -n "${4:-}" && -s "$4" ]]; then
    mapfile -t rows <"$4"
else
    mapfile -t rows < <(mise exec -- jq -r '.previewCaptions[] | "\(.id) \(.from) \(.to)"' \
        store/screenshots.json)
fi
inputs=(-ss "$from" -t "$length" -i "$raw")
# The footage scaled to 1664x936 (16:9) under a 112 px caption band of ground.dark.
filter="[0:v]scale=1664:936:flags=lanczos,fps=30,pad=1920:1080:128:112:color=0x101113"
filter+=",format=yuv420p[v0]"
index=0
for row in "${rows[@]}"; do
    read -r id start end <<<"$row"
    index=$((index + 1))
    inputs+=(-loop 1 -t "$length" -framerate 30 -i "$captions/$id.png")
    fade_out=$(perl -e "printf '%.3f', $end - 0.15")
    filter+=";[$index:v]format=rgba,fade=t=in:st=$start:d=0.15:alpha=1"
    filter+=",fade=t=out:st=$fade_out:d=0.15:alpha=1[c$index]"
    filter+=";[v$((index - 1))][c$index]overlay=0:0:enable='between(t,$start,$end)'"
    filter+=",format=yuv420p[v$index]"
done
silence=$((index + 1))
inputs+=(-f lavfi -t "$length" -i "anullsrc=channel_layout=stereo:sample_rate=48000")

mise exec -- ffmpeg -hide_banner -loglevel error -y "${inputs[@]}" \
    -filter_complex "$filter" -map "[v$index]" -map "$silence:a" \
    -c:v libx264 -profile:v high -level:v 4.0 -b:v 11M -maxrate 12M -bufsize 24M \
    -r 30 -pix_fmt yuv420p -c:a aac -b:a 256k -ar 48000 -ac 2 \
    -t "$length" -movflags +faststart "$mp4"

# The 9.1 gate.
field() { # <stream selector> <entry>: one value from ffprobe
    mise exec -- ffprobe -v error -select_streams "$1" -show_entries "stream=$2" \
        -of default=noprint_wrappers=1:nokey=1 "$mp4"
}
video="$(field v:0 codec_name) $(field v:0 profile) $(field v:0 level) $(field v:0 width)x$(field v:0 height) $(field v:0 r_frame_rate)"
audio="$(field a:0 codec_name) $(field a:0 channels)ch $(field a:0 sample_rate)Hz"
duration=$(mise exec -- ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp4")
size=$(stat -f %z "$mp4")
problems=""
[[ "$video" == "h264 High 40 1920x1080 30/1" ]] || problems+="video is $video (want h264 High 40 1920x1080 30/1); "
[[ "$audio" == "aac 2ch 48000Hz" ]] || problems+="audio is $audio (want aac 2ch 48000Hz); "
perl -e "exit !($duration >= 15 && $duration <= 30)" || problems+="duration ${duration}s (15-30 s); "
((size <= 500 * 1024 * 1024)) || problems+="size $((size / 1048576)) MB (at most 500 MB); "
if [[ -n "$problems" ]]; then
    echo "make-preview: FAIL: $problems" >&2
    exit 1
fi
echo "make-preview: $mp4 ok (${duration}s, $((size / 1024)) KB, $video, $audio)"
