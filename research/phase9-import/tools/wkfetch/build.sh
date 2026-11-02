#!/bin/bash
# Builds wkfetch twice into research/phase9-import/.build/wkfetch: an unsandboxed binary for
# corpus collection (it writes into the gitignored corpus folders) and a sandboxed app with
# exactly the Personal build's network entitlements, for the sandbox spike (spec 19 a3).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../../.build/wkfetch"
mkdir -p "$out/WKFetch.app/Contents/MacOS"
swiftc -O -swift-version 5 -o "$out/wkfetch" "$here/main.swift"
codesign -f -s - "$out/wkfetch"
cp "$here/Info.plist" "$out/WKFetch.app/Contents/Info.plist"
cp "$out/wkfetch" "$out/WKFetch.app/Contents/MacOS/WKFetch"
codesign -f -s - --entitlements "$here/../pat-spike/PATSpike.entitlements" "$out/WKFetch.app"
echo "$out/wkfetch"
