#!/usr/bin/env bash
# `make eval-ai` (manual; never part of `make check` or `make gate`, docs/phases/
# 3-ai-entry-and-assistant.md section 14): real Foundation Models and the curated MLX model over
# the golden paste fixtures and, when present, Ryan's local pastes (research/phase3-eval/pastes,
# gitignored). Writes .build/eval-ai/results/ (jsonl per provider and set, summary.txt,
# summary.json) and compares the fixture scores with Packages/SegueAI/Sources/AIEval/Resources/baseline.json.
#
#   make eval-ai                     run and compare
#   make eval-ai BASELINE=1          store the fixture scores as the new baseline
#   make eval-ai RECORD=1            refresh the ScriptedProvider recordings of the committed
#                                    fixtures (never of Ryan's pastes) and the set assistant's
#                                    set-request recordings
#   make eval-ai PROVIDERS=mlx       one provider only (mlx, fm or mlx,fm)
#   make eval-ai MODEL=<dir>         the model folder (default .build/p3a/model/<revision>)
#
# The model is never downloaded here: place the pinned revision by hand (see
# docs/research/phase3-mlx-in-app.md section 7).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
lock="$root/.build/make.lock"
work="$root/.build/eval-ai"
catalog="Packages/SegueAI/Sources/ModelStore/Resources/curated-models.json"
revision="$(jq -r '.models[0].revision' "$catalog")"
model="${MODEL:-$root/.build/p3a/model/$revision}"
fixtures="Packages/SegueCore/Tests/Fixtures/paste"
pastes="research/phase3-eval/pastes"
mkdir -p "$work"

providers="${PROVIDERS:-mlx,fm}"
args=(--fixtures "$fixtures" --gold "$fixtures/gold.json" --out "$work/results"
    --providers "$providers" --baseline Packages/SegueAI/Sources/AIEval/Resources/baseline.json)
if [[ "$providers" == *mlx* ]]; then
    test -f "$model/config.json" || {
        echo "eval-ai: no model at $model (set MODEL=<dir>)" >&2
        exit 2
    }
    # Only the files the curated manifest pins, so the eval proves the trimmed download loads.
    trimmed="$work/model-$revision"
    mkdir -p "$trimmed"
    find "$trimmed" -type l -delete
    jq -r '.models[0].files[].name' "$catalog" | while read -r name; do
        ln -s "$model/$name" "$trimmed/$name"
    done
    args+=(--model "$trimmed")
fi
if [[ -d "$pastes" && -f research/phase3-eval/gold.local.json ]]; then
    args+=(--pastes "$pastes" --pastes-gold research/phase3-eval/gold.local.json)
fi
if [[ -n "${BASELINE:-}" ]]; then
    args+=(--write-baseline)
fi
if [[ -n "${RECORD:-}" ]]; then
    args+=(--record "$fixtures/recorded"
        --set-requests Packages/SegueCore/Tests/Fixtures/setRequests/requests.json)
fi

# Swift Build (the SwiftPM build system of Xcode 27) compiles MLX's Metal kernels into
# mlx-swift_Cmlx.bundle beside the tool; the legacy native build system does not, so it is
# named explicitly. (xcodebuild cannot be used here: Tuist generates a SegueAI.xcodeproj in the
# package folder that has no eval scheme.)
(cd Packages/SegueAI && lockf -k "$lock" swift build -c release --product segue-eval \
    --build-system swiftbuild --disable-index-store)
bin="$(cd Packages/SegueAI && swift build -c release --build-system swiftbuild --show-bin-path)"
test -f "$bin/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" || {
    echo "eval-ai: the build produced no MLX Metal library" >&2
    exit 2
}
"$bin/segue-eval" "${args[@]}"
