#!/bin/bash
# Model bake-off for on-device paste refinement: every model in models.tsv (plus the Qwen3-4B
# baseline and Foundation Models) through the same pipeline, prompts and grammar as run.sh.
# Everything this writes (results/bakeoff-<ref>/) is gitignored: it names real songs.
#
#   research/phase3-eval/bakeoff.sh [ingest-ref] [model-name|fm ...]   default ref HEAD, all models
#   BAKEOFF_ARGS="memlimit=1536" ...   extra mlxspike options (e.g. a constrained-machine run)
#   BAKEOFF_TAG=lowmem ...             suffix for the output folder
#   BAKEOFF_NO_FM=1 ...                skip the Foundation Models run
#
# Weights live in .build/bakeoff/models/<name> (download: see models.tsv, `hf download <repo>
# --revision <sha> --local-dir .build/bakeoff/models/<name> --exclude '*.md'`), never in git.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
spikes="$root/research/phase3-spikes"
lock="$root/.build/make.lock"
ref="$(git -C "$root" rev-parse --short "${1:-HEAD}")"
shift || true
out="$here/results/bakeoff-$ref${BAKEOFF_TAG:+-$BAKEOFF_TAG}"
mkdir -p "$out"

"$spikes/sync-ingest.sh" "$ref"
(cd "$spikes/Spike" && lockf -k "$lock" swift build -c release --product fmspike)
(cd "$spikes/Spike" && lockf -k "$lock" xcodebuild -scheme mlxspike -configuration Release \
    -destination "platform=macOS,arch=arm64" -derivedDataPath ../dd -skipMacroValidation build >/dev/null)

export SPIKE_SEGMENTER=ingest
cd "$out"
SPIKE_INGEST_DUMP="ingest.json" "$spikes/Spike/.build/release/fmspike" dump ../../pastes >/dev/null

models=("qwen3-4b-2507	$root/.build/p3a/model/50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b")
while IFS=$'\t' read -r name _repo _sha; do
    models+=("$name	$root/.build/bakeoff/models/$name")
done <"$here/models.tsv"

for m in "${models[@]}"; do
    name="${m%%	*}"; dir="${m#*	}"
    if [[ $# -gt 0 ]] && [[ ! " $* " == *" $name "* ]]; then continue; fi
    echo "== $name"
    # shellcheck disable=SC2086
    "$spikes/dd/Build/Products/Release/mlxspike" "$dir" "$name" paste ../../pastes "mlx-$name.jsonl" \
        mode=hints split exact ebnf retry cachelimit=512 ${BAKEOFF_ARGS:-} >"mlx-$name.log" 2>&1 \
        || echo "   $name exited $?" | tee -a "mlx-$name.log"
done
if [[ -z "${BAKEOFF_NO_FM:-}" ]] && { [[ $# -eq 0 ]] || [[ " $* " == *" fm "* ]]; }; then
    echo "== fm"
    "$spikes/Spike/.build/release/fmspike" paste ../../pastes "fm.jsonl" mode=hints split exact >"fm.log" 2>&1
fi
# "none": the deterministic tier alone (every model call failed, so unheaded blocks stay
# {start_of_verse} placeholders and title/artist come from code only).
src="$(find . -name 'mlx-*.jsonl' -size +0 | head -1)"
[[ -n "$src" ]] && python3 -c '
import json, sys
with open(sys.argv[2], "w") as f:
    for line in open(sys.argv[1]):
        r = json.loads(line)
        if r["task"] != "paste": continue
        r.update(ok=False, output=None, errorKind="deterministicOnly", latencyMs=0, peakMemoryMB=0, retries=0)
        f.write(json.dumps(r) + "\n")' "$src" none.jsonl
python3 "$here/bakeoff_table.py" --gold "$here/gold.local.json" "$out"
