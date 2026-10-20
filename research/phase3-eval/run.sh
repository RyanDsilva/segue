#!/bin/bash
# P3-A part 2: score the curated MLX model and Foundation Models on Ryan's real pastes (R64).
# Everything this writes (results/, gold.local.json) is gitignored: it names real songs.
#
#   research/phase3-eval/run.sh [ingest-ref]     default ref 55d8701 (P3-1 as landed)
#
# Needs: the pastes in pastes/, gold.local.json (labels per P3-1 block, see the README), the
# model at .build/p3a/model/<revision> (docs/research/phase3-mlx-in-app.md section 7), Xcode's
# Metal Toolchain. Builds take the shared build lock.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
spikes="$root/research/phase3-spikes"
lock="$root/.build/make.lock"
ref="${1:-55d8701}"
rev=50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b
model="$root/.build/p3a/model/$rev"
out="$here/results"
mkdir -p "$out"

"$spikes/sync-ingest.sh" "$ref"
(cd "$spikes/Spike" && lockf -k "$lock" swift build -c release --product fmspike)
(cd "$spikes/Spike" && lockf -k "$lock" xcodebuild -scheme mlxspike -configuration Release \
    -destination "platform=macOS,arch=arm64" -derivedDataPath ../dd -skipMacroValidation build >/dev/null)

export SPIKE_SEGMENTER=ingest
cd "$out"
SPIKE_INGEST_DUMP="ingest-$ref.json" "$spikes/Spike/.build/release/fmspike" dump ../pastes >/dev/null
"$spikes/dd/Build/Products/Release/mlxspike" "$model" qwen3-4b-2507 paste ../pastes \
    "mlx-qwen3-$ref.jsonl" mode=hints split exact ebnf retry cachelimit=512 >"mlx-$ref.log" 2>&1
"$spikes/Spike/.build/release/fmspike" paste ../pastes "fm-$ref.jsonl" mode=hints split exact \
    >"fm-$ref.log" 2>&1

cd "$spikes"
for f in "mlx-qwen3-$ref" "fm-$ref"; do
    python3 score.py --gold ../phase3-eval/gold.local.json --ingest "../phase3-eval/results/ingest-$ref.json" \
        --skip-meta "../phase3-eval/results/$f.jsonl"
done
