#!/usr/bin/env bash
# Uploads the App Store text and screenshots with fastlane deliver
# (docs/release/specs/WS5-store-listing.md 10; settings in store/Deliverfile).
#
#   scripts/store-upload.sh [--dry-run]
#
# Checks first: `store-check` passes, the screenshots in .build/screenshots/final/en-US pass the
# compositor's verify, and SEGUE_REVIEW_PHONE is set (the review contact phone, never in git).
# Then reads the App Store Connect API key from 1Password into a private temp file, writes the
# key JSON deliver wants next to it, and runs `fastlane deliver` from store/. deliver shows
# its HTML preview and asks before uploading; nothing here passes --force. The temp files are
# removed on exit.
#
# Credentials (R46): `op` works only in Ryan's Terminal.app, so run this there. There is no
# plaintext fallback. --dry-run does every check and prints the deliver command, without `op`
# or App Store Connect. 1Password item as for `make upload`: SEGUE_ASC_OP_VAULT (default
# Private) / SEGUE_ASC_OP_ITEM (default "Segue ASC API Key"), fields key_id and issuer_id and
# the attachment AuthKey.p8.
set -euo pipefail
cd "$(dirname "$0")/.."

die() {
    echo "store-upload: error: $*" >&2
    exit 1
}
say() { echo "store-upload: $*"; }

dry_run=0
for arg in "$@"; do
    case "$arg" in
    --dry-run) dry_run=1 ;;
    *) die "usage: store-upload.sh [--dry-run]" ;;
    esac
done

vault="${SEGUE_ASC_OP_VAULT:-Private}"
item="${SEGUE_ASC_OP_ITEM:-Segue ASC API Key}"
read -r marketing _ < <(scripts/bump-version.sh show)
[[ -n "${marketing:-}" ]] || die "could not read the version (bump-version.sh show)"

scripts/check-store-metadata.swift store
shots=".build/screenshots/final"
[[ -d "$shots/en-US" ]] || die "no screenshots in $shots/en-US: run \`make screenshots\` first"
scripts/compose-screenshots.swift --verify "$shots"
want=$(mise exec -- jq '.locales["en-US"] | length' store/screenshots.json)
have=$(find "$shots/en-US" -name '*.png' | wc -l | tr -d ' ')
[[ "$have" == "$want" ]] || die "$have screenshots in $shots/en-US, store/screenshots.json has $want: run \`make screenshots\`"
if [[ -z "${SEGUE_REVIEW_PHONE:-}" ]]; then
    die "set SEGUE_REVIEW_PHONE to the review contact phone (e.g. +1 555 123 4567); it is never committed"
fi

deliver=(mise exec -- fastlane deliver)
if ((dry_run)); then
    say "dry run: checks passed for version $marketing"
    say "would run: op read op://$vault/$item/{AuthKey.p8,key_id,issuer_id}"
    say "would run (in store/): SEGUE_STORE_VERSION=$marketing SEGUE_ASC_KEY_JSON=<tmp>/key.json ${deliver[*]}"
    exit 0
fi

command -v op >/dev/null || die "the 1Password CLI \`op\` is not available; run this in Terminal.app (R46)"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/segue-store.XXXXXX")
cleanup() {
    for file in "$scratch/AuthKey.p8" "$scratch/key.json"; do
        [[ -f "$file" ]] && rm -f -P "$file"
    done
    find "$scratch" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

op read --out-file "$scratch/AuthKey.p8" --file-mode 0600 "op://$vault/$item/AuthKey.p8" >/dev/null \
    || die "could not read the AuthKey.p8 attachment from op://$vault/$item (is 1Password unlocked?)"
key_id=$(op read "op://$vault/$item/key_id") || die "could not read key_id from op://$vault/$item"
issuer=$(op read "op://$vault/$item/issuer_id") || die "could not read issuer_id from op://$vault/$item"
(
    umask 077
    # shellcheck disable=SC2016 # jq variables, not shell ones
    mise exec -- jq -n --arg key_id "$key_id" --arg issuer "$issuer" \
        --rawfile key "$scratch/AuthKey.p8" \
        '{key_id: $key_id, issuer_id: $issuer, key: $key, in_house: false}' >"$scratch/key.json"
)
say "API key $key_id loaded from 1Password into a private temp file"

cd store
SEGUE_STORE_VERSION="$marketing" SEGUE_ASC_KEY_JSON="$scratch/key.json" \
    FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1 FASTLANE_HIDE_CHANGELOG=1 \
    "${deliver[@]}"
