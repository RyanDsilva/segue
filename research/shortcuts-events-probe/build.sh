#!/bin/bash
# R35 probe build (docs/release/specs/WS1-release-pipeline.md 4.10): compile the sandboxed
# Shortcuts Events probe app into .build/shortcuts-probe, sign it with a development identity
# (hardened runtime + sandbox, the same shape as Segue) and print the signed entitlements.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# Two "Apple Development" identities exist on Ryan's Mac; default to the V6BM673U35 team's.
identity=${SEGUE_PROBE_IDENTITY:-Apple Development: Ryan Rony Dsilva}
app="$root/.build/shortcuts-probe/ShortcutsEventsProbe.app"

mkdir -p "$app/Contents/MacOS"
xcrun swiftc -O -o "$app/Contents/MacOS/ShortcutsEventsProbe" "$here/main.swift"
cp "$here/Info.plist" "$app/Contents/Info.plist"
codesign --force --options runtime --entitlements "$here/probe.entitlements" \
	--sign "$identity" "$app"
codesign --verify --strict "$app"
echo "Signed entitlements of $app:"
codesign -d --entitlements - --xml "$app" | plutil -p -
