#!/usr/bin/env bash
# Pulls open Sentry issues and user feedback (Report a Problem) into .build/sentry/ so an agent
# can triage them without the token. `make sentry-pull` runs it.
#
# Credentials (R46): the token is read with the 1Password CLI from op://Private/Segue Sentry/read-token
# (override with SEGUE_SENTRY_READ_OP_REF) for this process only: never a file, never echoed, never
# on a command line. It needs a Sentry user auth token with event:read, project:read and org:read;
# the dSYM upload token cannot read issues. Run it in Ryan's Terminal.app; agent shells cannot use op.
# Organisation, project and URL come from .sentryclirc.
set -euo pipefail
cd "$(dirname "$0")/.."

die() {
    echo "sentry-pull: error: $*" >&2
    exit 1
}

conf() { awk -F= -v k="$1" '$1 == k { print $2 }' .sentryclirc; }
url=$(conf url)
org=$(conf org)
project=$(conf project)
[[ -n "$url" && -n "$org" && -n "$project" ]] || die ".sentryclirc is missing url, org or project"

ref="${SEGUE_SENTRY_READ_OP_REF:-op://Private/Segue Sentry/read-token}"
command -v op >/dev/null 2>&1 \
    || die "the 1Password CLI (op) is not on PATH. Run this in Terminal.app (R46); there is no plaintext fallback"
op whoami >/dev/null 2>&1 || die "1Password CLI is not signed in. Unlock 1Password, then re-run: make sentry-pull"
token=$(op read "$ref") || die "could not read $ref (create a user auth token with event:read, project:read, org:read and save it there)"
[[ -n "$token" ]] || die "$ref is empty"

out=.build/sentry
mkdir -p "$out/events"

# The header goes in on stdin so the token never shows up in the process list.
api() {
    local path="$1" dest="$2" code
    code=$(printf 'Authorization: Bearer %s\n' "$token" \
        | curl -sS -m 30 -H @- -o "$dest" -w '%{http_code}' "$url/api/0/$path") || die "request failed: $path"
    case "$code" in
        200) ;;
        401 | 403) die "Sentry refused $path ($code): the token needs event:read, project:read and org:read" ;;
        *) die "Sentry returned $code for $path: $(head -c 400 "$dest")" ;;
    esac
}

query() { python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }

# The project endpoint accepts only 24h or 14d here; it sets the stats window, not which issues
# come back, so every unresolved issue is listed.
api "projects/$org/$project/issues/?statsPeriod=14d&limit=100&query=$(query is:unresolved)" "$out/issues.json"
api "organizations/$org/issues/?project=-1&statsPeriod=30d&limit=100&query=$(query 'issue.category:feedback')" \
    "$out/feedback.json"

ids=$(python3 -I -c '
import json, sys
seen = []
for name in sys.argv[1:]:
    for issue in json.load(open(name)):
        if issue["id"] not in seen:
            seen.append(issue["id"])
print(" ".join(seen))
' "$out/issues.json" "$out/feedback.json")

count=0
for id in $ids; do
    api "organizations/$org/issues/$id/events/latest/" "$out/events/$id.json"
    count=$((count + 1))
done

echo "sentry-pull: $count issue(s) with their latest event saved to $out"
