#!/usr/bin/env bash
# Uploads debug symbols to Sentry so crash reports are symbolicated
# (docs/release/specs/WS3-services.md 6.5). `make upload` runs it after the App Store upload;
# `make upload-dsyms` runs it on its own.
#
#   scripts/upload-dsyms.sh <xcarchive>           the archive's dSYMs/ folder
#   DSYMS=<dir> scripts/upload-dsyms.sh           any folder of .dSYM bundles
#   scripts/upload-dsyms.sh --dry-run <xcarchive> checks and lists, uploads nothing
#
# Credentials (R46): the Sentry auth token is read with the 1Password CLI from
# op://Private/Segue Sentry/token (override with SEGUE_SENTRY_OP_REF) into SENTRY_AUTH_TOKEN
# for this process only: never a file, never echoed. Run it in Ryan's Terminal.app; agent
# shells cannot use op. There is no plaintext fallback. Organisation, project and region come
# from .sentryclirc; sentry-cli comes from mise (.mise.toml).
set -euo pipefail
cd "$(dirname "$0")/.."

die() {
    echo "upload-dsyms: error: $*" >&2
    exit 1
}

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=1
    shift
fi

if [[ -n "${DSYMS:-}" ]]; then
    [[ $# -eq 0 ]] || die "pass either DSYMS=<dir> or an archive, not both"
    dsyms="$DSYMS"
    retry="make upload-dsyms DSYMS=$DSYMS"
else
    [[ $# -eq 1 ]] || die "usage: scripts/upload-dsyms.sh [--dry-run] <xcarchive> (or DSYMS=<dir>)"
    dsyms="$1/dSYMs"
    retry="make upload-dsyms ARCHIVE=$1"
fi
[[ -d "$dsyms" ]] || die "no dSYM folder at $dsyms"

found=()
while IFS= read -r -d '' bundle; do found+=("$bundle"); done \
    < <(find "$dsyms" -maxdepth 1 -name '*.dSYM' -type d -print0)
((${#found[@]} > 0)) || die "no .dSYM bundles in $dsyms"

sentry() { mise exec -- sentry-cli "$@"; }

# Local check (no network, no token): every dSYM is usable and has the UUIDs we expect.
for bundle in "${found[@]}"; do
    sentry debug-files check "$bundle" || die "$bundle is not a usable debug file"
    echo "upload-dsyms: $(basename "$bundle"): $(dwarfdump --uuid "$bundle" | awk '{print $2, $3}' | tr '\n' ' ')"
done

ref="${SEGUE_SENTRY_OP_REF:-op://Private/Segue Sentry/token}"
if ((dry_run)); then
    echo "upload-dsyms: dry run: would read $ref and run:"
    echo "  sentry-cli debug-files upload --include-sources --wait $dsyms"
    exit 0
fi

if ! command -v op >/dev/null 2>&1; then
    die "the 1Password CLI (op) is not installed or not on PATH. Run this in Terminal.app" \
        "(R46); there is no plaintext-token fallback. Retry: $retry"
fi
if ! op whoami >/dev/null 2>&1; then
    die "1Password CLI is not signed in. Unlock 1Password, then re-run in Terminal.app: $retry"
fi
SENTRY_AUTH_TOKEN=$(op read "$ref") || die "could not read $ref. Retry: $retry"
[[ -n "$SENTRY_AUTH_TOKEN" ]] || die "$ref is empty"
export SENTRY_AUTH_TOKEN

echo "upload-dsyms: uploading ${#found[@]} dSYM(s) from $dsyms"
sentry debug-files upload --include-sources --wait "$dsyms" || die "upload failed. Retry: $retry"
echo "upload-dsyms: done"
