#!/bin/bash
# Private Access Token spike (P9-4 step a0, R183). Builds a tiny sandboxed app
# (app-sandbox + network.client, the Personal build's network entitlements) that
# loads Cloudflare Research's PAT demo page once with URLSession and once in a
# hidden WKWebView on a dedicated WKWebsiteDataStore(forIdentifier:), and prints
# whether a token was presented. Manual, live network, two requests. Never in
# make quick, gate or check.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../../.build/pat-spike"
app="$out/PATSpike.app"
mkdir -p "$app/Contents/MacOS"
cp "$here/Info.plist" "$app/Contents/Info.plist"
swiftc -O -o "$app/Contents/MacOS/PATSpike" "$here/main.swift"
codesign -f -s - --entitlements "$here/PATSpike.entitlements" "$app"
"$app/Contents/MacOS/PATSpike"
