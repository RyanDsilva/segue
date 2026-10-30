---
name: macos-release
description: Shipping a macOS app build to App Store Connect or as a notarized download - version and build bumps, manual code signing, archiving and exporting, verifying the archive before upload, validating, uploading, and the post-upload chores (dSYMs, release tag, notes). Use whenever the user wants to cut a release, make a TestFlight or App Store build, archive, notarize, fix a signing or provisioning error, or prepare an upload, even if they just say "ship it" or "send a build".
---

# macOS release

Releases are irreversible once uploaded, so read before acting: find the project's release scripts and Makefile targets, its release docs or checklist, the signing settings in the manifests, and the export options plist. Use the project's commands where they exist, and stop and ask if the docs and the scripts disagree.

Apple's tooling changes between Xcode releases (`xcodebuild`, `altool` vs `notarytool`, App Store Connect API). Check flags with `--help` or `man` on the installed Xcode, and current docs, before relying on remembered syntax.

## Versioning

- Marketing version (`CFBundleShortVersionString`) changes per release; build number (`CFBundleVersion`) must increase on every upload, including re-uploads of the same version.
- Bump through the project's mechanism (a script, manifest setting, or `agvtool`) and commit the bump on its own.

## Manual signing

- Sign with explicitly named certificates and provisioning profiles in the project and export config, not Xcode automatic signing, so builds are reproducible.
- Confirm the team ID from the project config; an Apple ID can belong to several teams.
- On a signing error, inspect what is actually installed: `security find-identity -v -p codesigning`, the profiles in `~/Library/Developer/Xcode/UserData/Provisioning Profiles`, and `codesign -d --entitlements - <app>`. Fix the mismatch; don't switch to automatic signing to make it go away.

## Verify the archive before upload

After archive and export, and before any upload, check the built product:
- Version and build number are the intended ones.
- Entitlements (`codesign -d --entitlements -`) are the release set: sandbox on, no debug or temporary exceptions.
- A privacy manifest (`PrivacyInfo.xcprivacy`) is present and covers the APIs and SDKs used.
- No debug-only, test-only, or excluded-flavor code shipped (`nm`/`strings` on the binary, bundle contents).
- dSYMs exist for every binary.
- Validation passes (App Store Connect validate, or `notarytool` plus `stapler` for direct distribution).

## Upload and after

- Run validate and upload directly when credentials are available in the shell. If the credential tool isn't reachable from the agent's shell, say so and give the exact command for the user to run, rather than working around it with plaintext keys.
- After a successful upload: upload dSYMs to the crash reporter, create a signed local release tag, and draft release notes from the commits since the last tag.
- Never push commits or tags to the remote without the user's explicit go-ahead.
