# 02 - Technical submission pipeline (source to App Store Connect / TestFlight)

Researched 2026-10-17. Scope: signing, sandbox/entitlements, privacy manifest, Info.plist and SDK rules, archive/export/upload from the command line, TestFlight for Mac, and the repo changes to automate it. Read-only research: no code or config was changed.

Inputs read: `Project.swift`, `Tuist/Package.swift`, `Makefile`, `scripts/xcodebuild.sh`, `scripts/verify-appstore.sh`, `App/Segue.entitlements`, `App/Segue-Debug.entitlements`, `UITests/SegueUITests.entitlements`, `design/icon/Segue.icon/icon.json`, `.mise.toml`, `.gitignore`, the existing Release-AppStore product at `.build/DerivedData-verify/Build/Products/Release-AppStore/Segue.app` (Info.plist, signed entitlements, `lipo`, `nm -u`, `assetutil`, `iconutil`), `xcodebuild -showBuildSettings` for `Segue-AppStore` / `Release-AppStore`, `xcodebuild -help` and `xcrun altool --help` from the installed Xcode 26.6 (17F113), and the resolved GRDB 7.11.1 / Tonic 2.1.2 sources.

Team decision received mid-research: Ryan renews his lapsed paid Apple Developer Program membership on the same team `V6BM673U35`, so `developmentTeam` in `Project.swift` stays; only the comment calling it a Personal Team changes. App is free, no IAP in v1.

---

## 1. Summary (top findings)

1. **No blocking SDK problem.** Apple's minimum-SDK rule (Xcode 26 since 2026-04-28; OS 27 SDKs from April 2027) names iOS, iPadOS, tvOS, visionOS and watchOS only. App Store Connect's upload table lists macOS apps as "built with Xcode 6+". The installed Xcode 26.6 with the macOS 26.5 SDK is fine today. Xcode 27 shipped 2026-09-09 (macOS 27 submissions open); moving to it is optional for this release.
2. **Keep the universal binary.** The Release-AppStore build is already `x86_64 arm64` (`ARCHS = arm64 x86_64`, `ONLY_ACTIVE_ARCH = NO`). Apple says macOS 26 is the last release that supports Intel Macs, so a macOS 26 minimum still reaches Intel Tahoe users. Going arm64-only is allowed (Apple tells you to set the arch to arm64 if you want that), but it is a product decision (see Open decisions).
3. **What ships, entitlement-wise, is clean.** `SegueAppStore` in every configuration signs with `App/Segue.entitlements`, which has exactly three entitlements: `app-sandbox`, `files.user-selected.read-write` and `files.bookmarks.app-scope`. None of these needs a review justification. The `/private/tmp/segue-e2e/` temporary exception is only in `App/Segue-Debug.entitlements`, which Project.swift applies to `Debug-Personal` of the `Segue` target only. The UI-test runner's copy is in `UITests/SegueUITests.entitlements`, and that target is not in the `Segue-AppStore` scheme. The signed Release-AppStore product confirms this: its entitlements are the three above plus `get-task-allow`, which comes from Apple Development signing and is removed when the archive is re-signed for App Store export. `verify-appstore.sh` already checks for this, but it checks DerivedData builds, not the archive that actually gets uploaded. Adding the same check against the `.xcarchive` is recommended.
4. **A privacy manifest is not required for a macOS app today, but ship one anyway.** Apple's required-reason API page scopes the rule to "iOS, iPadOS, tvOS, visionOS, or watchOS". So ITMS-91053 should not block a Mac upload. A manifest still costs nothing, keeps the app ready if Apple extends the rule, and feeds the privacy report. The binary references `NSUserDefaults` (reason `CA92.1`) and `NSURLContentModificationDateKey` / `NSURLCreationDateKey` (reason `3B52.1`, for files in the user-selected library folder). It has no boot-time, disk-space or active-keyboard symbols. GRDB 7.11.1 ships its own (empty-reasons) manifest, and it ends up in the app at `Contents/Resources/GRDB_GRDB.bundle`. Tonic 2.1.2 ships none and uses no required-reason APIs.
5. **App icon risk to verify before the first upload.** The `.icon` compiles into `Assets.car` (renditions from 16pt to 512pt@2x / 1024px, so that part is fine) plus a fallback `Segue.icns`. That `Segue.icns` only contains 16, 16@2x, 128 and 128@2x; it has **no 512 or 512@2x**. Developer forum threads from the Xcode 26 cycle report "Missing required icon ... ICNS format, containing both a 512x512 and a 512x512@2x image" and alpha-channel rejections for Icon Composer icons. Our `icon.json` has no blur, which was the alpha-channel trigger in those threads. Whether the current validator accepts an asset-catalog icon alongside a partial icns is UNVERIFIED. Check it with `altool --validate-app` (or an Xcode Organizer "Validate") on the first archive, before anything else.
6. **Info.plist gaps.** It already has `LSApplicationCategoryType = public.app-category.music`, `LSMinimumSystemVersion = 26.0` (from the deployment target), `NSHumanReadableCopyright`, `CFBundleIconName`, `CFBundleShortVersionString = 0.1.0` and `CFBundleVersion = 1`. Missing: `ITSAppUsesNonExemptEncryption = NO`. The app only uses CryptoKit `SHA256` for hashing and has no networking, so without the key App Store Connect asks the export-compliance questionnaire on every upload. Also, `NSMainStoryboardFile = Main` comes from Tuist's default macOS plist even though no storyboard exists. This is harmless in practice but worth removing as hygiene. The version strings are hard-coded inside `Project.swift`, which makes scripted bumping awkward.
7. **Command-line upload path is fully supported.** Use `xcodebuild archive`, then `xcodebuild -exportArchive` with `method = app-store-connect` and `destination = upload`, authenticating with `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`. That one command signs the `.pkg` and uploads it, with no separate altool step. `altool` 26.40.1 is still shipped and documented for `--upload-package` / `--upload-app` / `--validate-app` with API-key auth. Transporter.app is the GUI fallback.
8. **Signing choice is the main open decision.** Automatic (cloud) signing on export needs an Admin or Account Holder identity. An API key cannot be given the "Access to Cloud Managed Distribution Certificate" permission on its own, so headless automatic signing needs an **Admin** API key. Manual signing needs locally installed `Apple Distribution` and `Mac Installer Distribution` certs plus a Mac App Store provisioning profile, but then a lower-privilege key can do the upload.
9. **Same bundle ID on both flavors is a footgun.** `Segue` (Personal, which links the license-encumbered `SeguePersonalModules`) and `SegueAppStore` both use `dev.ryandsilva.segue`. App Store Connect would accept a Personal archive. The upload script has to refuse any archive that is not the SegueAppStore product. The shared ID also means a TestFlight/MAS install and a local Personal build share one sandbox container and LaunchServices identity on Ryan's Mac.
10. **Build numbers must strictly increase for macOS.** Apple: "For macOS apps, increment the build version before you distribute a build." `manageAppVersionAndBuildNumber` defaults to **YES** on export, which lets Xcode silently rewrite the build number so the uploaded build no longer matches the repo. Set it to NO and own the counter.

---

## 2. What ships (verified against the built Release-AppStore product)

| Item | Value | Source |
|---|---|---|
| Bundle ID | `dev.ryandsilva.segue` | `Project.swift` `bundleID`; showBuildSettings |
| Signed entitlements (SegueAppStore, all configs) | `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.bookmarks.app-scope` (+ `get-task-allow` from development signing, removed on distribution re-sign) | `App/Segue.entitlements`; `codesign -d --entitlements -` on the product |
| Temporary exception | Only `App/Segue-Debug.entitlements` (Debug-Personal of `Segue` target) and `UITests/SegueUITests.entitlements` (test runner). Never in SegueAppStore | `Project.swift` `e2eDebugConfiguration`; `verify-appstore.sh` `check_no_exception` |
| Hardened runtime | ON (`ENABLE_HARDENED_RUNTIME = YES`). Allowed for MAS, not required | showBuildSettings |
| Architectures | `x86_64 arm64` universal | `lipo -archs` |
| Linkage | All SwiftPM deps (GRDB, Tonic, SegueCore modules, SegueUI) are static frameworks merged into `Contents/MacOS/Segue`. No `Contents/Frameworks`, so there are no nested code signatures to manage | bundle listing |
| Resource bundles | `GRDB_GRDB.bundle` (has `PrivacyInfo.xcprivacy`), `SegueUI_SegueUI.bundle` (colour `Assets.car`, Schibsted Grotesk fonts, OFL `Licenses`). Both have Info.plists with `CFBundleIdentifier` | bundle listing |
| Icon | `Assets.car` with `Segue` icon stack and renditions 16-1024px, plus `Segue.icns` with 16, 32, 128 and 256px only | `assetutil --info`, `iconutil -c iconset` |
| Info.plist | see section 5 | `plutil -p` |
| Quarantine xattrs | none on sources (fonts, icon) or product | `xattr -r -l` |

App Sandbox notes for review:
- Shortcuts are run with `NSWorkspace.shared.open(shortcuts://run-shortcut?name=...)` (`Packages/SegueUI/Sources/SegueUI/Live/ShortcutRunner.swift:38-42`). That is a URL open: sandbox-safe and needs no Apple Events entitlement.
- Keep-awake uses `ProcessInfo.beginActivity` (`Packages/SegueUI/Sources/SegueUI/Live/KeepAwake.swift:9`), which needs no entitlement.
- Data written inside the container: `Application Support/<bundle id>/shape-library.json` and `bindings.json` (`AppModel.swift:52`, `LiveDependencies.swift:37`). The library and its `.segue/index.sqlite` live in the user-selected folder and are reached through a security-scoped bookmark.
- Entitlements that would trigger a review justification or rejection risk: any `com.apple.security.temporary-exception.*`, `com.apple.security.automation.apple-events`, `cs.disable-library-validation`, `cs.allow-unsigned-executable-memory`, and broad `files.downloads/pictures/music` access. None of these ship. Guideline 2.4.5(i) requires the app to be "appropriately sandboxed".

---

## 3. Certificates, profiles, signing

### What the Mac App Store needs
| Asset | Purpose | Notes |
|---|---|---|
| **Apple Distribution** certificate (or legacy "Mac App Distribution") | Signs the `.app` for App Store Connect | Apple: Apple Distribution can "submit it to App Store Connect" on all platforms; Mac App Distribution is "Sign a Mac app before submitting it to the Mac App Store" |
| **Mac Installer Distribution** certificate (legacy name "3rd Party Mac Developer Installer") | Signs the `.pkg` that wraps the app | Apple: "Sign and submit a Mac Installer Package, containing your signed app, to the Mac App Store". `xcodebuild -help` lists `"Mac Installer Distribution"` as the `installerSigningCertificate` auto-selector |
| **Mac App Store Connect provisioning profile** for `dev.ryandsilva.segue` | Embedded as `Contents/embedded.provisionprofile` | TestFlight help: builds "must include application identifiers within the provisioning profiles to be eligible for TestFlight" |
| Explicit App ID `dev.ryandsilva.segue` on team V6BM673U35 | Profile and App Store Connect record | Automatic signing registers it. Capabilities: none beyond sandbox (sandbox is not a portal capability) |

Local keychain today: only two `Apple Development` identities, and no distribution or installer identity (`security find-identity -v -p codesigning`).

### Option A - automatic (cloud) signing (fewest moving parts)
- Keep `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = Apple Development` for archive. Export re-signs with a **cloud-managed** Apple Distribution cert and Mac Installer Distribution cert, so no private keys sit in the local keychain.
- Works interactively when Ryan's Account Holder Apple ID is signed into Xcode > Settings > Accounts. `scripts/xcodebuild.sh` already passes `-allowProvisioningUpdates`.
- Headless, it needs an App Store Connect API key with the **Admin** role. Apple: Admin/Account Holder can cloud sign by default, and the "Access to Cloud Managed Distribution Certificate" permission exists for users but not for API keys. An Admin key is very powerful: it can manage users, agreements and certificates.

### Option B - manual signing for Release-AppStore (least privilege)
- One-time: create Apple Distribution and Mac Installer Distribution certs in the portal (or in Xcode, which then holds the private keys in the login keychain), and create a "Mac App Store Connect" profile named e.g. `Segue MAS`.
- In Tuist, override only the `Release-AppStore` configuration of `SegueAppStore`: `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = Apple Distribution`, `PROVISIONING_PROFILE_SPECIFIER = Segue MAS`, `DEVELOPMENT_TEAM = V6BM673U35`. Other configurations stay automatic.
- ExportOptions: `signingStyle = manual`, `signingCertificate = Apple Distribution`, `installerSigningCertificate = Mac Installer Distribution`, `provisioningProfiles = { dev.ryandsilva.segue = "Segue MAS" }`.
- Upload can then use an **App Manager** (or Developer) key. UNVERIFIED: the exact minimum role that may upload builds by API key. Apple docs say the Developer role can upload builds, but this was not checked for keys specifically.
- Cost: profile renewal each year, and manual cert management.

### Expressing it in Tuist
`Project.swift` already sets signing at project and target level (the target repeat works around Tuist's default macOS `CODE_SIGN_IDENTITY`). Add a per-configuration override on the `appStoreApp` target in the same way `e2eDebugConfiguration` does for Personal:
```swift
// sketch, not applied
let appStoreReleaseSigning: Configuration = .release(
    name: releaseAppStore,
    settings: [/* Option B keys above */ ],
)
// appTarget(... personal: false) -> configurations: [appStoreReleaseSigning]
```
Another route: give the configuration an `xcconfig:` (Tuist `Configuration.release(name:settings:xcconfig:)` supports this). `.gitignore` already reserves `Tuist/Signing.xcconfig` for local signing overrides. Profile names and team IDs are not secrets, so committing them is fine. Only `.p8` / `.p12` material must stay out of the repo.

---

## 4. Privacy manifest

### Rule status
- Apple: "Describe the reasons your app or third-party SDK on iOS, iPadOS, tvOS, visionOS, or watchOS uses these APIs..." and "Starting May 1, 2024, apps that don't describe their use of required reason API in their privacy manifest file aren't accepted by App Store Connect." **macOS is not in the enforced list**, so a Mac upload should not get ITMS-91053. Whether App Store Connect sends advisory emails for Mac builds is UNVERIFIED.
- For static linking, Apple says the bundle that contains each executable needs the manifest. GRDB is merged into our executable and its manifest arrives as a resource bundle, which is how SwiftPM packages ship manifests and is accepted in Xcode's privacy report.

### Required-reason API use in Segue's own code (App Store flavor)
| Category | Reason | Call sites | Binary evidence |
|---|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` (only accessible to the app itself) | `App/Sources/SegueApp.swift:65`, `App/Sources/LaunchOptions.swift:112-121`, `Packages/SegueUI/Sources/SegueUI/Settings/LiveSettingsStore.swift:34-43`, `Packages/SegueUI/Sources/SegueUI/App/LibraryLocation.swift:23-33`, `Packages/SegueUI/Sources/SegueUI/App/UITesting.swift:11` | `_OBJC_CLASS_$_NSUserDefaults` |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `3B52.1` (metadata of files/directories the user specifically granted access to) | `Packages/SegueCore/Sources/Support/FileSystem.swift:187-193` (`contentModificationDateKey`, `creationDateKey`), consumed at `Library/SongFiles.swift:14,176-177,194,225`, `Library/SongFiles+Scan.swift:92,175-177,195`, `Library/LibraryStore+Phase2.swift:284`, `Library/LibraryStore+DisplayPrefs.swift:22` | `_NSURLContentModificationDateKey`, `_NSURLCreationDateKey` |
| `NSPrivacyAccessedAPICategorySystemBootTime` | not needed | `SuspendingClock` (`Support/Clock.swift:58`, `Live/LiveDependencies.swift:57`) and `CACurrentMediaTime` (`Editor/SourceTextView.swift:29`, `Editor/CanvasViews.swift:58`, `Editor/EditorPerformance.swift:79`) are not on Apple's list (the list is `systemUptime`, `mach_absolute_time()`) | no `mach_absolute_time` or `systemUptime` reference in `nm -u` |
| `NSPrivacyAccessedAPICategoryDiskSpace` | not used | none | none |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | not used | none | none |

The timestamps are not shown to the user (`DDA9.1` is not needed) and do not cover container files (`C617.1` is not needed). If a later change displays file dates or stats container files, add those reasons. Re-run `nm -u` on the release binary as part of the release gate (see section 8) so new symbols are caught.

### Proposed `App/PrivacyInfo.xcprivacy` (app target resource)
```xml
NSPrivacyTracking = false
NSPrivacyTrackingDomains = []
NSPrivacyCollectedDataTypes = []          # no data leaves the device
NSPrivacyAccessedAPITypes = [
  { NSPrivacyAccessedAPIType = NSPrivacyAccessedAPICategoryUserDefaults,  NSPrivacyAccessedAPITypeReasons = [CA92.1] },
  { NSPrivacyAccessedAPIType = NSPrivacyAccessedAPICategoryFileTimestamp, NSPrivacyAccessedAPITypeReasons = [3B52.1] },
]
```
Add it to `resources:` in `appTarget` next to `design/icon/Segue.icon`. It lands at `Contents/Resources/PrivacyInfo.xcprivacy`.

### Third-party packages
- **GRDB 7.11.1**: `GRDB/PrivacyInfo.xcprivacy` exists (`~/.cache/swifterpm/sources/grdb.swift/7.11.1-b83108d.../GRDB/PrivacyInfo.xcprivacy`), declared in `Package.swift:83` as `resources: [.copy("PrivacyInfo.xcprivacy")]`. Contents: tracking false, no collected data, empty `NSPrivacyAccessedAPITypes`. It is present in the built product.
- **Tonic 2.1.2**: `Package.swift` has only `resources: [.process("Tonic.docc")]`, no manifest, and a grep of `Sources/` finds no required-reason API. Nothing to do.
- Whether GRDB/Tonic are on Apple's "commonly used third-party SDKs" list (which would require a signature as well as a manifest) was not re-fetched. From memory neither is on it: UNVERIFIED. The list also only applies to iOS-family platforms.

---

## 5. Info.plist, versions, SDK, architectures

| Key | Current | Needed | Note |
|---|---|---|---|
| `LSApplicationCategoryType` | `public.app-category.music` | keep | required for MAS. Must match the primary category chosen in App Store Connect (UNVERIFIED that a mismatch errors) |
| `ITSAppUsesNonExemptEncryption` | missing | **add `false`** | Apple: without it App Store Connect "walks you through an export compliance questionnaire every time you upload". Segue uses only CryptoKit SHA-256 hashing (`Packages/SegueCore/Sources/Library/SongFiles.swift:2,311,316`) and no networking or TLS of its own |
| `CFBundleShortVersionString` | `0.1.0` (hard-coded in Project.swift) | three integers `X.Y.Z` | Apple: "The required format is three period-separated integers". First public release likely `1.0.0` (decision) |
| `CFBundleVersion` | `1` (hard-coded) | strictly increasing per upload | Apple: "For macOS apps, increment the build version before you distribute a build." Use a single monotonically increasing integer that never resets across marketing versions, so ordering is unambiguous |
| `LSMinimumSystemVersion` | `26.0` (auto from `MACOSX_DEPLOYMENT_TARGET`) | keep | |
| `NSHumanReadableCopyright` | `Copyright 2026 Ryan D'Silva` | keep, or switch to the `©` symbol | |
| `CFBundleIconName` / `CFBundleIconFile` | `Segue` / `Segue` | keep | see icon risk |
| `NSMainStoryboardFile` | `Main` (Tuist default, no storyboard exists) | remove (hygiene) | SwiftUI `@main` app. Not known to fail validation (UNVERIFIED) |
| `CFBundleDisplayName` | `Segue` | keep, must match the App Store name policy (sibling doc) | |

**Versioning mechanics.** Move the two version values out of the Info.plist literal into build settings: `"CFBundleShortVersionString": "$(MARKETING_VERSION)"`, `"CFBundleVersion": "$(CURRENT_PROJECT_VERSION)"`. Source them from a tracked `Config/Version.xcconfig` attached to all configurations (or read a `version.json` in `Project.swift`). Export with `manageAppVersionAndBuildNumber = NO` so the uploaded build is exactly the committed one.

**SDK/Xcode.**
- App Store Connect upload table: "macOS app | Built with Xcode 6+ | Uploaded with Xcode 6+". The note says Xcode 14+ will be required to upload starting 2026.
- The Xcode 26 SDK rule (since 2026-04-28) and the OS-27 SDK rule (April 2027) list iOS, iPadOS, tvOS, visionOS and watchOS only.
- Installed: Xcode 26.6 (17F113), macOS 26.5 SDK, so we comply. Guideline 2.4.5(viii): "Apps should run on the currently shipping OS". macOS 27 shipped in September 2026, so **smoke-test the build on macOS 27** before submitting (sibling QA doc).

**Architectures.**
- Apple (2026-09-09): "macOS 26 is the final release supporting Intel Mac computers ... To limit your app to Macs with Apple silicon, set your Xcode build architecture to arm64 only."
- Apple (2026-09-01) on Rosetta: "distribute as universal binary".
- Current universal output is the right default for a macOS 26 minimum. Cost: about 2x binary size (32 MB executable today) and no Intel test hardware. See Open decisions.

**Quarantine.** Since 2025-02-18 Apple requires removing `com.apple.quarantine` from all files before upload. None present now. Add an `xattr -r` check to the release gate, because a downloaded font or SVG could reintroduce it.

---

## 6. Archive, export, upload (command line)

```bash
# 1. Archive (generic destination, not arch=arm64, so the archive is unambiguously universal)
xcodebuild -workspace Segue.xcworkspace -scheme Segue-AppStore -configuration Release-AppStore \
  -destination 'generic/platform=macOS' -archivePath .build/archives/Segue-<ver>-<build>.xcarchive \
  -allowProvisioningUpdates [auth flags] archive

# 2. Export + upload in one step (destination=upload in ExportOptions)
xcodebuild -exportArchive -archivePath .build/archives/Segue-<ver>-<build>.xcarchive \
  -exportOptionsPlist Config/ExportOptions-AppStore.plist -exportPath .build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

Proposed `Config/ExportOptions-AppStore.plist` (keys and values from `xcodebuild -help`, Xcode 26.6):

| Key | Value | Why |
|---|---|---|
| `method` | `app-store-connect` | `app-store` is deprecated |
| `destination` | `upload` | export + upload in one command. Use `export` to only produce the `.pkg` |
| `teamID` | `V6BM673U35` | |
| `signingStyle` | `automatic` (Option A) or `manual` (Option B) | |
| `signingCertificate` / `installerSigningCertificate` / `provisioningProfiles` | Option B only: `Apple Distribution` / `Mac Installer Distribution` / `{dev.ryandsilva.segue: "Segue MAS"}` | |
| `manageAppVersionAndBuildNumber` | `false` | default YES rewrites the build number |
| `uploadSymbols` | `true` | dSYM for crash reports (default YES) |
| `testFlightInternalTestingOnly` | `false` for release builds. A separate `ExportOptions-Internal.plist` with `true` is an option for throwaway builds | |

Alternative upload paths:
- Export to `.pkg` (`destination = export`) and then run `xcrun altool --upload-package <pkg> --api-key <id> --api-issuer <issuer> --p8-file-path <p8>` (or `--upload-app -f <pkg> -t macos`). `--validate-app` gives a dry-run validation, which is useful for the icon question.
- Transporter.app (Mac App Store) is the GUI fallback.
- altool still ships (v26.40.1) and the App Store Connect help lists it as a supported upload tool. Only its notarization role was retired in favour of notarytool. Altool searches `./private_keys`, `~/private_keys`, `~/.private_keys` and `~/.appstoreconnect/private_keys` for `AuthKey_<id>.p8` when `--p8-file-path` is not given. Pass the path explicitly rather than relying on those directories.

**Auth.** Create an App Store Connect **Team API key** (Users and Access > Integrations), note the Issuer ID and Key ID, and download `AuthKey_<KEYID>.p8` once. Keep it out of the repo, ideally in 1Password. The script materialises it to a 0600 file in `$TMPDIR` via `op read` and deletes it on exit, or reads a path from env. Neither the key ID nor the issuer ID is secret, but keep them in env/1Password too so the repo stays account-agnostic.

**Common Mac validation errors to pre-empt.** Codes are from memory and practice; the exact numbers are UNVERIFIED unless a source is given.
| Error | Cause | Our status |
|---|---|---|
| ITMS-90296 "App sandbox not enabled" | missing `app-sandbox` in any executable | OK (only one executable) |
| ITMS-90886 / 90889-family "Cannot be used with TestFlight because the bundle ... is missing a provisioning profile" / missing `com.apple.application-identifier` entitlement | exporting without a distribution profile | handled by export signing. Check `embedded.provisionprofile` in the gate |
| "Invalid Code Signing Entitlements" / disallowed key | entitlement not in profile, or a `temporary-exception` left in | release gate re-checks the archive |
| Missing installer certificate / "No signing certificate Mac Installer Distribution found" | Option B without the installer cert | [RYAN] creates it |
| ITMS-90236-style "Missing required icon ... ICNS ... 512x512 and 512x512@2x" | `.icon` fallback icns lacks 512 sizes (observed in our build) | **verify with --validate-app** |
| Icon alpha-channel error (Icon Composer) | blur on a group plus a layer near the edge | our `icon.json` has no blur |
| "Redundant Binary Upload" / "must contain a higher version" | build number reused or not increasing | bump script + `manageAppVersionAndBuildNumber=false` |
| Quarantine attribute | `com.apple.quarantine` on bundled files | gate check |
| ITMS-91053 missing privacy manifest reason | iOS-family only | not applicable, but manifest provided |

---

## 7. TestFlight for Mac

- Eligibility: the build must be Xcode 13+ and carry "application identifiers within the provisioning profiles" (App Store Connect TestFlight overview).
- Processing: after upload the build shows as Processing, and Apple emails when it completes. Duration is typically minutes to an hour (UNVERIFIED, not documented).
- Export compliance: answered once per build unless `ITSAppUsesNonExemptEncryption = NO` is in Info.plist. With the key set, builds go straight to "Ready to Submit" / testable.
- Internal testers: up to 100 App Store Connect users, no Beta App Review. External: up to 10,000. The first build added to an external group goes to Beta App Review, and later builds "may not require a full review".
- Build expiry: 90 days.
- Testers install the TestFlight app from the Mac App Store. TestFlight 2.3+ on macOS supports feedback and screenshots. Automatic updates of beta builds are a per-app toggle in TestFlight for Mac (UNVERIFIED for 2026 wording).
- A TestFlight build can be the same binary that is later submitted for review, so the build that was tested is the build that ships.
- Local conflict: a TestFlight install and a locally built Personal app share bundle ID `dev.ryandsilva.segue` and the sandbox container `~/Library/Containers/dev.ryandsilva.segue`. Personal and TestFlight builds will read each other's UserDefaults (library bookmark, live settings). See Open decisions.

---

## 8. Step-by-step checklist

Order matters; [RYAN] = manual/out-of-band, [AGENT] = we can implement in the repo.

1. [RYAN] Renew the Apple Developer Program membership on team V6BM673U35 and wait for it to be active. Accept the latest Program License Agreement (updated 2026-10-13) and, in App Store Connect > Business, the Free Apps agreement if prompted. Tax/banking is not needed for a free app.
2. [RYAN] In Xcode > Settings > Accounts, confirm the Apple ID shows team V6BM673U35 as a paid team (not "Personal Team") and that the role is Account Holder.
3. [RYAN] Confirm or register the explicit App ID `dev.ryandsilva.segue` (Certificates, IDs & Profiles > Identifiers). Automatic signing does this on first archive.
4. [RYAN] Create the App Store Connect app record: platform macOS, bundle ID `dev.ryandsilva.segue`, SKU, primary language, name (sibling docs cover metadata and naming).
5. [RYAN] Choose signing Option A or B (Open decision 1).
   - Option A: nothing else to create; cloud certificates are created on first export.
   - Option B: create an **Apple Distribution** cert and a **Mac Installer Distribution** cert (easiest from Xcode > Accounts > Manage Certificates > "+", which keeps the private keys in the login keychain), then create a **Mac App Store Connect** profile for `dev.ryandsilva.segue` named `Segue MAS` and download it (Xcode > Download Manual Profiles).
6. [RYAN] Create an App Store Connect API key (Users and Access > Integrations > Team Keys). Use the role the signing choice needs: Admin for Option A headless, App Manager for Option B (UNVERIFIED minimum). Store the `.p8`, Key ID and Issuer ID in 1Password. The `.p8` can only be downloaded once.
7. [AGENT] Add `ITSAppUsesNonExemptEncryption = false`, remove `NSMainStoryboardFile`, and switch the version keys to build settings (section 9).
8. [AGENT] Add `App/PrivacyInfo.xcprivacy` and wire it into resources.
9. [AGENT] Add `Config/ExportOptions-AppStore.plist`, `scripts/bump-version.sh`, `scripts/release.sh`, and the `make archive` / `make validate` / `make upload` targets. Add the archive-level gate (`scripts/verify-archive.sh`).
10. [AGENT] Update the `Project.swift` signing comment (paid team). For Option B, add the `Release-AppStore` manual-signing configuration on `SegueAppStore`.
11. [AGENT] Run `make archive` then `make validate` (altool `--validate-app` on the exported `.pkg`). Resolve the icon question here first.
12. [RYAN] Unlock 1Password so the script can read the key, then approve the upload run (`make upload`).
13. [RYAN] In App Store Connect: wait for processing, add the build to an internal TestFlight group, and install via TestFlight on his Mac (and, if available, on an Intel Mac or macOS 27 machine).
14. [RYAN] When ready, submit the same build for review (sibling doc covers metadata, screenshots, review notes, age rating).

---

## 9. Proposed repo changes (plan only, nothing applied)

| File | Change |
|---|---|
| `Project.swift` | (a) Update the `developmentTeam` comment: paid team V6BM673U35. (b) In `infoPlist`: `"CFBundleShortVersionString": "$(MARKETING_VERSION)"`, `"CFBundleVersion": "$(CURRENT_PROJECT_VERSION)"`, add `"ITSAppUsesNonExemptEncryption": false`, override `NSMainStoryboardFile` away (or switch from `.extendingDefault` to an explicit dictionary). (c) Add `App/PrivacyInfo.xcprivacy` to `resources`. (d) Attach `Config/Version.xcconfig` to all four configurations (`.debug(name:..., xcconfig:)`). (e) Option B only: a `Release-AppStore` configuration override on `appStoreApp` with manual signing settings. (f) Optional (Open decision 4): Personal bundle ID `dev.ryandsilva.segue.personal` |
| `Config/Version.xcconfig` (new, tracked) | `MARKETING_VERSION = 1.0.0` and `CURRENT_PROJECT_VERSION = <int>`, the single source of truth |
| `App/PrivacyInfo.xcprivacy` (new) | as in section 4 |
| `Config/ExportOptions-AppStore.plist` (new) | as in section 6 |
| `scripts/bump-version.sh` (new) | `bump-version.sh build` increments `CURRENT_PROJECT_VERSION`. `bump-version.sh marketing X.Y.Z` validates the three-integer format and that it is greater than the current value. Never lowers either value |
| `scripts/verify-archive.sh` (new) | Runs on the `.xcarchive` and the exported `.pkg` (`pkgutil --expand` / `--check-signature`). Fails unless: product is SegueAppStore (no `SeguePersonalModules`/`SEGUE_PERSONAL` strings, reusing `verify-appstore.sh` patterns); signed entitlements are exactly the three expected keys (no `temporary-exception`, no `get-task-allow` after export); `ITSAppUsesNonExemptEncryption` is present; `PrivacyInfo.xcprivacy` is present; `lipo -archs` is as decided; no `com.apple.quarantine` xattr; `embedded.provisionprofile` is present with the right team and bundle ID; `CFBundleVersion` equals the xcconfig value; `nm -u` required-reason symbols match the manifest categories |
| `scripts/release.sh` (new) | Refuse a dirty tree. `tuist generate`. Archive via a variant of `scripts/xcodebuild.sh` (keep the warnings-fail result-bundle check, but with `-destination 'generic/platform=macOS'`). Run `verify-archive.sh`. Load the API key from 1Password (`op read` into a mktemp 0600 file, trap-delete). Export with `destination=upload` (or export then `altool --validate-app` for `make validate`). On success print the version/build and tag `v<ver>+<build>` locally, signed per repo convention, never pushing |
| `Makefile` | New phony targets: `archive` (archive + verify-archive), `validate` (export to pkg + `altool --validate-app`), `upload` (full release.sh), `bump-build`, `bump-version VERSION=X.Y.Z`. `release` = `check verify-appstore bump-build archive upload` (or leave `check` separate, since it runs the slow E2E) |
| `.gitignore` | `.build/` already covers `.build/archives` and `.build/export`. Add `*.p8`, `AuthKey_*.p8` and `*.p12` as a backstop |
| `scripts/xcodebuild.sh` | Optionally accept a `SEGUE_DESTINATION` override so archive can use `generic/platform=macOS` without duplicating the warning check |

**Local vs CI.** Recommend **local-only** for now. The signing identity (or Admin key), 1Password and a Mac with Xcode are all on Ryan's machine; distribution credentials stay host-side, matching his deploy-credentials rule; and there is no macOS runner cost. A GitHub Actions macOS job could later run `make archive` without upload as a smoke test. Upload stays a local, explicitly triggered step.

---

## 10. Risks

1. **Icon validation** (partial icns from `.icon`). Likelihood medium, impact blocks upload. Mitigation: validate the first archive. Fallbacks: add a full `.icns` / AppIcon set alongside, or update Xcode.
2. **Admin API key blast radius** if Option A runs headless. Mitigation: Option B, or Option A only interactively through the Xcode account.
3. **Uploading the Personal flavor by mistake** (same bundle ID). Mitigation: the archive gate rejects it. Optionally, a separate Personal bundle ID.
4. **Build-number drift** if `manageAppVersionAndBuildNumber` is left at its default. Mitigation: set false and gate on equality.
5. **Intel coverage untested** if we ship universal. Mitigation: arm64-only, or borrow an Intel Mac on macOS 26.
6. **macOS 27 compatibility**: reviewers likely test on the current OS. Mitigation: test on macOS 27 before submission.
7. **Lapsed-membership side effects**: old certificates/profiles may be revoked or expired after renewal, and App IDs remain. Mitigation: let automatic signing regenerate them, and delete stale ones in the portal.
8. **1Password locked during upload**: the script must fail fast with a clear "unlock 1Password" message rather than hang.

---

## 11. Open decisions (need Ryan)

1. **Signing**: Option A (automatic/cloud; headless needs an Admin API key), Option B (manual certs + MAS profile; least-privilege key), or A-interactive (sign via the Xcode account, upload with a low-privilege key). Or make it a research ticket.
2. **Architectures**: universal (reaches Intel Macs on macOS 26, about 2x binary, untested on Intel) or arm64-only.
3. **First public version string**: `1.0.0` vs `0.1.0`, and the build-number scheme (committed counter vs `git rev-list --count` vs timestamp).
4. **Personal flavor bundle ID**: keep the shared `dev.ryandsilva.segue` (shared container/defaults with TestFlight/MAS installs, accidental-upload risk) or split it to `dev.ryandsilva.segue.personal`. Splitting means the Personal build gets a fresh container and bookmark.
5. **Xcode**: ship from Xcode 26.6 (macOS 26.5 SDK) or move to Xcode 27 first (new SDK; possible new warnings under warnings-as-errors).
6. **Local-only release vs CI**: recommend local-only plus an optional CI archive smoke job.
7. **Auto-tag/commit on bump**: should `make upload` create the signed version-bump commit and tag automatically, or leave committing to Ryan?

---

## 12. Sources

- Upcoming requirements (SDK minimum since 2026-04-28; quarantine attribute; privacy manifest since 2024-05-01): https://developer.apple.com/news/upcoming-requirements/
- App Store submissions open for OS 27, macOS 26 final Intel release, arm64-only guidance (2026-09-09): https://developer.apple.com/news/?id=k1mtkt1k
- Rosetta changes, universal binary guidance (2026-09-01), and news index: https://developer.apple.com/news/
- Prior-year rule wording (iOS-family only): https://developer.apple.com/news/?id=6lxhtioi
- Upload builds (tools table, macOS built with Xcode 6+): https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
- Certificate types: https://developer.apple.com/help/account/reference/certificate-types
- Cloud-managed certificates (Admin/Account Holder, Developer permission): https://developer.apple.com/help/account/certificates/cloud-managed-certificates/
- API key cannot get the cloud-cert permission (forum): https://developer.apple.com/forums/thread/698117
- TestFlight overview: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- Required-reason API (platform scope, reasons): https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api and https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons
- ITSAppUsesNonExemptEncryption: https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption
- CFBundleVersion: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion
- CFBundleShortVersionString: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring
- App Review Guidelines 2.4.5: https://developer.apple.com/app-store/review/guidelines/
- Icon Composer upload issues (forums): https://developer.apple.com/forums/thread/795411 and https://www.developer.apple.com/forums/thread/788102
- Tuist Configuration (per-configuration settings/xcconfig): https://docs.tuist.dev/en/references/project-description/structs/configuration
- GRDB privacy manifest: `GRDB/PrivacyInfo.xcprivacy` in https://github.com/groue/GRDB.swift (v7.11.1, local copy under `~/.cache/swifterpm/sources/grdb.swift/`)
- Tonic 2.1.2 `Package.swift`: https://github.com/AudioKit/Tonic (local copy at `Tuist/.build/checkouts/Tonic`)
- Local tool help: `xcodebuild -help` (Xcode 26.6, 17F113) for ExportOptions keys and `-authenticationKey*` flags; `xcrun altool --help` (26.40.1) for `--upload-package`, `--validate-app` and `--p8-file-path`
