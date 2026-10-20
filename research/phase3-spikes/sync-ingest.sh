#!/bin/bash
# Copies P3-1's deterministic pipeline (SegueCore Ingest, ChordPro, MusicTheory) into
# Spike/.build/ingest-src, which Spike/Sources/{Ingest,ChordPro,MusicTheory} link to.
#   sync-ingest.sh <git ref>   the sources as committed at that ref (e.g. 55d8701)
#   sync-ingest.sh             the working tree as it is now (sibling work in progress)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
dest="$here/Spike/.build/ingest-src"
mkdir -p "$dest"
for m in Ingest ChordPro MusicTheory; do
    [[ -e "$dest/$m" ]] && trash "$dest/$m"
done
if [[ $# -eq 1 ]]; then
    git -C "$root" archive "$1" Packages/SegueCore/Sources/Ingest Packages/SegueCore/Sources/ChordPro \
        Packages/SegueCore/Sources/MusicTheory | tar -x -C "$dest" --strip-components 3
    echo "ingest sources: $(git -C "$root" rev-parse --short "$1")" | tee "$dest/SOURCE"
else
    for m in Ingest ChordPro MusicTheory; do cp -R "$root/Packages/SegueCore/Sources/$m" "$dest/$m"; done
    echo "ingest sources: working tree at $(date -u +%FT%TZ)" | tee "$dest/SOURCE"
fi
