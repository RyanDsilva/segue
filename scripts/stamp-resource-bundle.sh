#!/usr/bin/env bash
# Xcode build phase (app targets, after resources are copied, before code signing): gives the
# embedded SegueUI resource bundle the app's copyright and version and a real identifier
# instead of Tuist's placeholder plist (docs/release/specs/WS1-release-pipeline.md 4.2 item 9,
# B-6). verify-appstore.sh and verify-archive.sh assert the result.
set -euo pipefail

app_plist="${TARGET_BUILD_DIR:?}/${INFOPLIST_PATH:?}"
bundle_plist="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/SegueUI_SegueUI.bundle/Contents/Info.plist"
buddy=/usr/libexec/PlistBuddy

[[ -f "$app_plist" ]] || { echo "error: no app Info.plist at $app_plist" >&2; exit 1; }
[[ -f "$bundle_plist" ]] || { echo "error: no SegueUI resource bundle plist at $bundle_plist" >&2; exit 1; }

copyright=$("$buddy" -c "Print :NSHumanReadableCopyright" "$app_plist")

# set <key> <value>: sets a string key, adding it when missing.
set_key() {
    "$buddy" -c "Set :$1 \"$2\"" "$bundle_plist" 2>/dev/null \
        || "$buddy" -c "Add :$1 string \"$2\"" "$bundle_plist"
}

set_key CFBundleIdentifier "dev.ryandsilva.segue.SegueUI.resources"
set_key NSHumanReadableCopyright "$copyright"
set_key CFBundleShortVersionString "${MARKETING_VERSION:?}"
set_key CFBundleVersion "${CURRENT_PROJECT_VERSION:?}"
echo "stamped $bundle_plist ($copyright, ${MARKETING_VERSION} (${CURRENT_PROJECT_VERSION}))"
