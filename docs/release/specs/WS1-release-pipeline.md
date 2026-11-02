# WS1 - Release pipeline and readiness fixes

Spec for one focused implementation session. Written 2026-10-17, finalised the same day against the resolved decisions. Canonical rulings: `docs/release/decisions.md` (R1-R41). Resolved questions: `docs/release/open-questions.md` (A items take their **Recommend** option unless R30-R41 overrides; B items take their default; section 4 inconsistencies are applied here). Research: `docs/release/research/02-technical-submission.md` (signing, manifest, export, upload), `06-readiness-audit.md` (findings B*/R*/P*), `03-review-risk.md` (F4-F8, F14), `01-account-and-connect.md` (B, C, F), `09-shortcut-confirmation.md` (R35).

**Before you start:** every decision this spec needs is made; section 9 lists the one remaining question, and it blocks nothing. Steps that need Ryan's hands are marked **[RYAN]** and listed in section 3; stop and ask when you reach one that is not done. When you hit a fork the spec does not settle, stop and ask rather than choosing. Sibling workstreams (WS2a, WS2b, WS3, WS4, WS5) may be editing the same tree; do not expect a clean `git status`, and do not treat their edits as conflicts. In Bash never use plain `cat` (it is aliased to eza and hangs); use `command cat` or the Read tool. No em dashes in anything you write; use "-".

## 1. Goal

At the end of this session:

1. `make archive && make validate` produces a Mac App Store `.pkg` of the `SegueAppStore` target, version `1.0` (R176; first planned as `0.5`), a build number from a tracked xcconfig, signed at export with the Apple Distribution and Mac Installer Distribution certificates and the `Segue Mac App Store` profile (R12, B-1), and it passes App Store Connect validation. `make upload` sends that same verified `.pkg` with the API key read from 1Password at run time (R13). Build 1 is uploaded to internal TestFlight as soon as validation is clean (B-9).
2. The Personal flavor has its own bundle ID `dev.ryandsilva.segue.personal` (R11) and its own sandbox container; Ryan's shapes and bindings are copied into it and the old container is moved aside before any TestFlight install (R40).
3. Shipping hygiene: `ITSAppUsesNonExemptEncryption = NO`, copyright `© 2026 Ryan Rony Dsilva` (R30), no stray storyboard key, `PrivacyInfo.xcprivacy`, `network.client` on both flavors (A61), version from build settings, arm64 only (R41/A59), test hooks compiled out of Release (B-7), a clean SegueUI resource-bundle plist (B-6).
4. Readiness fixes from `06` that belong to no other workstream: no typed characters in logs, editor perf logging out of Release, no test-only accessibility help in Release, Gig Mode Shortcuts off by default (R18) with a truthful checklist row (R35) and E2E tests, a cross-flavor library lock (B-2).
5. A `verify-archive` gate that checks the archive and the exact `.pkg` that gets uploaded, including any embedded Quick Look extension (I-14).

### Out of scope (owned elsewhere; reference only)

| Item | Owner |
|---|---|
| Import / Delete Song, Trash, autosave (R17), menus, Help menu + privacy link (06 P2, 03 F1), About panel, reopen main window (03 F2) | WS2a core UX |
| Welcome library (R19, 06 R6), What's New, TipKit (incl. `GigModeTip`), review prompt, Settings TabView host (`SegueSettingsView.swift`, I-6), Quick Look extension targets | WS2b first run and discovery |
| Analytics, bug report, crash upload, consent (R23-R26); the vendor SDKs; `NSPrivacyCollectedDataTypes` entries; App Privacy label; verify-archive check 14 (vendor keys) | WS3 services |
| Privacy/support/terms pages (06 B2), help docs (R21) | WS4 website |
| App record metadata, screenshots, preview video, review notes, age rating, App Privacy answers in App Store Connect | WS5 store listing |

WS1 creates the files WS3 extends (privacy manifest, `App/SegueAppStore.entitlements`, `scripts/release.sh`, `scripts/verify-archive.sh`). WS3 adds its collected-data entries and check 14; WS1 does not guess them. WS2b adds the Quick Look targets; WS1's export options, [RYAN] steps and verify-archive already handle the extension (I-14). In `LiveSettingsView.swift` WS1 changes only the Live pane text (I-6); WS2b moves the pane into its TabView host.

## 2. Current state (verified 2026-10-17)

- `Project.swift`: one `bundleID = "dev.ryandsilva.segue"` for both app targets (`Segue` = Personal, `SegueAppStore`). Signing is project- and target-level automatic, `CODE_SIGN_IDENTITY = Apple Development`, team `V6BM673U35` (the comment wrongly calls it a free Personal Team; it is the paid individual team, renewed per R1). `ENABLE_HARDENED_RUNTIME = YES`. Both targets use `App/Segue.entitlements`; `Debug-Personal` uses `App/Segue-Debug.entitlements` (E2E temp exception). No `ARCHS` override, so Release builds are universal.
- Info.plist is `.extendingDefault` with literals `CFBundleShortVersionString = 0.1.0`, `CFBundleVersion = 1`, copyright `Copyright 2026 Ryan D'Silva`; Tuist adds `NSMainStoryboardFile = Main` and `CFBundleIconFile = ""`. No `ITSAppUsesNonExemptEncryption`.
- The SegueUI resource bundle ships Tuist's placeholder plist (`Packages/SegueUI/Derived/InfoPlists/SegueUI_SegueUI-Info.plist`): copyright "Copyright ©. All rights reserved.", identifier `SegueUI.generated.resources` (06 P3).
- No privacy manifest for the app (GRDB ships its own, empty).
- `Makefile` has no archive/export/upload. `scripts/xcodebuild.sh` hard-codes `-destination 'platform=macOS,arch=arm64'` and writes to `.build/DerivedData`.
- The built `Release-AppStore` product's `Segue.icns` contains only 16, 16@2x, 128, 128@2x (checked with `iconutil -c iconset`); `Assets.car` has renditions up to 1024 px. The icon comes from `design/icon/Segue.icon` (Icon Composer document generated by `scripts/gen-icon.swift`, which already renders previews with `ictool`).
- `nm -u` on the Release-AppStore binary shows these required-reason-relevant symbols: `_OBJC_CLASS_$_NSUserDefaults`, `_NSURLContentModificationDateKey`, `_NSURLCreationDateKey`, `URLResourceValues.creationDate/contentModificationDate`, and `_CACurrentMediaTime` (perf timing only; not on Apple's list).
- Test-only code in Release: `RecordingShortcutRunner` (`Packages/SegueUI/Sources/SegueUI/Live/ShortcutRunner.swift:63-85`) and the launch-option parser (`App/Sources/LaunchOptions.swift:19-103`) are compiled in; parsing is only called under `#if DEBUG` (`App/Sources/SegueApp.swift:44-50`) (06 P6).
- Live mode: `ShortcutRunner.run(_:) async throws`; `WorkspaceShortcutRunner` opens `shortcuts://run-shortcut?name=` via `NSWorkspace.open` and only knows hand-over. `PreShowChecklist.FocusStatus` is `notConfigured | notRun | running(String) | ran(String) | failed(String, message:)`; `isDone(.focus)` is true for `.ran`, which today means "handed over" (violates R18).
- Shapes and bindings live at `Application Support/<bundle id>/shape-library.json` and `.../bindings.json` inside the sandbox container (`AppDependencies.defaultShapeLibraryURL`, `LiveDependencies.defaultBindingsURL`), so the bundle-ID split moves both paths.
- `~/Library/Containers/dev.ryandsilva.segue` exists and holds Ryan's real Personal-build state (library bookmark, Live settings, `shape-library.json`, `bindings.json`). Research 09 left an empty `~/Library/Containers/dev.ryandsilva.segueshortcutprobe`. Agent shells cannot read other apps' containers (macOS app-data protection: "Operation not permitted"), so container moves are [RYAN] steps.
- Toolchain (R41): **Xcode 27.1 (27A9275) / Swift 6.4** is the release toolchain; `Tuist.swift` already allows Xcode 27 (commit 78d2a1d) and the baseline `make check` is green on it. Re-checked under 27.1 for this spec: `xcodebuild -help` lists every ExportOptions key used in 4.5 (`method` values include `app-store-connect`); `xcrun altool --help` runs (licence accepted) and shows `--validate-app <file>`, `--upload-package <file> [--wait]`, `--api-key`, `--api-issuer`, `--p8-file-path`.
- Shortcuts: this Mac (macOS 26.6.2) has an empty Shortcuts library. `/System/Library/CoreServices/Shortcuts Events.app` (`com.apple.shortcuts.events`) declares access group `com.apple.shortcuts.run` and the `run` command (event class `srct`, id `run `, direct parameter `shortcut`, optional `with input` code `inpt`).
- Keychain: only two `Apple Development` identities; no distribution or installer identity.
- 1Password CLI `op` 2.35.0 is installed (`/opt/homebrew/bin/op`).
- Repo commits are signed (`git log --show-signature` shows `G`); signing goes through the 1Password SSH agent.

## 3. [RYAN] manual steps

Do these in order unless noted. The agent stops and asks when it needs one that is not done. Steps 1-6 need the paid membership active (R1); step 7 needs App Store Connect access (pending up to 48 h per R1).

0. **Xcode licence (only if needed).** If `xcrun altool --help` ever prints a licence prompt, run `sudo xcodebuild -license accept` in Terminal. (It ran cleanly on 2026-10-17.)
1. **Confirm the team.** developer.apple.com/account (sign in with contact@ryandsilva.dev) > Membership details: Team ID `V6BM673U35`, entity Individual, status active. In Xcode > Settings > Accounts, the team must show as "Ryan Rony Dsilva" (not "Personal Team"), role Account Holder.
2. **Create a Certificate Signing Request (CSR).** On macOS 26 Keychain Access is not in `/Applications/Utilities`; it lives at `/System/Library/CoreServices/Applications/Keychain Access.app` (open it with Spotlight, "Keychain Access"). Menu **Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority...**. User Email Address: your email; Common Name: `Ryan Dsilva Distribution`; CA Email Address: empty; select **Saved to disk**; Continue; save `Segue-Distribution.certSigningRequest` outside the repo. The private key is created in the login keychain. (Apple: developer.apple.com/help/account/certificates/create-a-certificate-signing-request.)
3. **Apple Distribution certificate.** developer.apple.com/account > **Certificates, IDs & Profiles > Certificates > "+"**. Under Software choose **Apple Distribution** > Continue > upload the CSR > Continue > **Download**. Double-click the downloaded `.cer`; it installs into the login keychain next to its private key. Check: `security find-identity -v -p codesigning` lists `Apple Distribution: Ryan Rony Dsilva (V6BM673U35)`.
4. **Mac Installer Distribution certificate.** Same page, "+" > **Mac Installer Distribution** > Continue > upload the same CSR (reusing it is fine) > Download > double-click. Check: `security find-identity -v` (no `-p codesigning`; installer identities are not code-signing identities) lists `3rd Party Mac Developer Installer: Ryan Rony Dsilva (V6BM673U35)` (the legacy display name of Mac Installer Distribution).
5. **Back up both private keys.** Keychain Access > login > My Certificates: select both certificates (with their keys), File > Export Items... > `.p12` with a strong password. Store the `.p12` and its password in 1Password. Never put it in the repo. Losing the key means revoking and recreating the certificate.
6. **App IDs and profiles (app and Quick Look extension, I-14).**
   - Certificates, IDs & Profiles > **Identifiers > "+"** > App IDs > App > Continue. Description `Segue`, Bundle ID **Explicit** `dev.ryandsilva.segue`, no capabilities ticked > Continue > Register. (Skip if it already exists.)
   - Same again: Description `Segue Quick Look`, Bundle ID **Explicit** `dev.ryandsilva.segue.quicklook`, no capabilities > Register.
   - Do not register `dev.ryandsilva.segue.personal` or `dev.ryandsilva.segue.personal.quicklook` by hand: automatic signing registers them on the first Personal build.
   - **Profiles > "+"** > under Distribution choose **Mac App Store Connect** > Continue. App ID `dev.ryandsilva.segue` > Continue. Certificate: the Apple Distribution certificate from step 3 > Continue. Name: **`Segue Mac App Store`** (exactly; ExportOptions refers to it by name) > Generate > Download.
   - Same again for App ID `dev.ryandsilva.segue.quicklook`, name **`Segue Mac App Store QuickLook`** (exactly) > Generate > Download.
   - Double-click each `.provisionprofile` to install it (or Xcode > Settings > Accounts > the team > Download Manual Profiles).
7. **App Store Connect API key** (after App Store Connect access arrives).
   - appstoreconnect.apple.com > **Users and Access > Integrations > App Store Connect API**. If shown, click **Request Access** (Account Holder only; Apple approves case by case).
   - Once approved: **Team Keys > "+"** (Generate API Key). Name `Segue uploads`, Access **App Manager** (B-8) > Generate.
   - Note the **Issuer ID** (top of the page) and the **Key ID**. Click **Download API Key**: `AuthKey_<KEYID>.p8` can be downloaded **only once**.
   - In 1Password create an item **`Segue ASC API Key`** in vault **`Private`** (category API Credential is fine) with text fields `key_id` and `issuer_id`, and attach the file renamed to **`AuthKey.p8`**. Then move the downloaded `.p8` to the Trash and empty it.
   - Tell the agent the vault/item names if you used different ones (the scripts read `SEGUE_ASC_OP_VAULT` / `SEGUE_ASC_OP_ITEM`).
8. **Create the App Store Connect app record** (Apps > "+" > New macOS App, bundle ID `dev.ryandsilva.segue`, SKU `segue-macos` per B-33). WS5 owns the metadata; WS1 only needs the record to exist before `make validate` / `make upload`, because validation checks the bundle ID against a record.
9. **Probe Shortcuts (R35), any time before step 8 of section 5.** In the Shortcuts app create two shortcuts with exactly these names:
   - **`Segue Probe OK`**: one action, **Show Notification** with text `probe ok`.
   - **`Segue Probe Fail`**: one action, **Get Contents of URL** with URL `https://invalid.invalid` (it fails with a network error).
   Then run the probe the agent prepares (section 4.10): click **OK** on the "wants to control Shortcuts Events" prompt the first time, and tell the agent what you saw (any extra prompts, whether the Shortcuts app came to the front, how long each run took). Delete both shortcuts afterwards if you like.
10. **Move the old container aside and carry over shapes and bindings (R40, A60).** Do this once section 5 step 1 has landed, and in any case before installing any TestFlight build. Run in **Terminal** (not an agent shell). macOS may ask "Terminal would like to access data from other apps": click **Allow**. If a command still fails with "Operation not permitted", grant Terminal Full Disk Access (System Settings > Privacy & Security > Full Disk Access), re-run, then remove it again.
    ```sh
    # a. Quit every Segue (both flavors); never launch one just to quit it.
    osascript -e 'if application id "dev.ryandsilva.segue" is running then tell application id "dev.ryandsilva.segue" to quit'
    osascript -e 'if application id "dev.ryandsilva.segue.personal" is running then tell application id "dev.ryandsilva.segue.personal" to quit'
    pgrep -fl 'Segue.app/Contents/MacOS/Segue' || echo "no Segue running"

    # b. Launch the NEW Personal build once (built from the step 1 commit) so macOS creates its
    #    container, choose your library folder, then quit it again (repeat the line from a.).
    #    Check the container exists:
    ls -d ~/Library/Containers/dev.ryandsilva.segue.personal/Data

    # c. Copy shapes and bindings into the Personal container (cp -p keeps timestamps;
    #    -n never overwrites a file the new build already wrote).
    old="$HOME/Library/Containers/dev.ryandsilva.segue/Data/Library/Application Support/dev.ryandsilva.segue"
    new="$HOME/Library/Containers/dev.ryandsilva.segue.personal/Data/Library/Application Support/dev.ryandsilva.segue.personal"
    mkdir -p "$new"
    for f in shape-library.json bindings.json; do
      if [ -f "$old/$f" ]; then cp -pn "$old/$f" "$new/$f" && echo "copied $f"; else echo "no $f in old container"; fi
    done
    ls -l "$new"

    # d. Move the old App Store-flavor container aside (outside ~/Library/Containers, outside
    #    ~/Documents and ~/Desktop). Nothing is deleted.
    mkdir -p ~/segue-backups
    mv ~/Library/Containers/dev.ryandsilva.segue ~/segue-backups/dev.ryandsilva.segue-container-20261017
    mv ~/Library/Containers/dev.ryandsilva.segueshortcutprobe ~/segue-backups/ 2>/dev/null || true
    ls ~/Library/Containers | grep -i segue    # expect: dev.ryandsilva.segue.personal (+ uitests runner)
    ```
    Then open the Personal build: shapes and key bindings are back; re-enter your Gig Mode Shortcut names in Settings > Live (the library bookmark and Live settings are app-scoped and do not move). If any App Store-flavor build is launched between now and the TestFlight install (it recreates `~/Library/Containers/dev.ryandsilva.segue`), re-run step a and `mv ~/Library/Containers/dev.ryandsilva.segue ~/segue-backups/dev.ryandsilva.segue-container-$(date +%Y%m%d-%H%M)` right before installing TestFlight. To roll back, quit Segue and `mv` the backup to its original path.
11. **Before each `make upload`:** unlock 1Password (the script needs the key and the SSH agent for the signed tag).
12. **After the first upload:** in App Store Connect > the app > TestFlight, wait for processing, add the build to an internal group with yourself, install from the TestFlight app (R6). Step 10 must be done first, so this is a clean first run.

## 4. File-level changes

Paths are relative to the repo root. "New" = new file.

### 4.1 `Config/Version.xcconfig` (new, tracked)

```
// Single source of truth for the app version. Edit only with scripts/bump-version.sh.
// MARKETING_VERSION: at most three period-separated integers (App Store Connect ITMS-90060).
// CURRENT_PROJECT_VERSION: one integer, strictly increasing on every upload, never reset.
MARKETING_VERSION = 1.0
CURRENT_PROJECT_VERSION = 1
```

`1.0` is valid: App Store Connect's rule (error ITMS-90060) is "a period-separated list of at most three non-negative integers" (R5). Build starts at `1` because nothing has been uploaded yet. WS4's changelog uses the same `0.5` string (I-2).

### 4.2 `Project.swift`

1. **Signing comment:** replace the "free Personal Team" text with "paid individual Apple Developer Program team (Ryan Rony Dsilva), renewed 2026-10 (docs/release/decisions.md R1)". Value unchanged.
2. **Bundle IDs (R11):** split the constant:
   ```swift
   let appStoreBundleID = "dev.ryandsilva.segue"
   let personalBundleID = "dev.ryandsilva.segue.personal"
   ```
   `appTarget(name:personal:)` uses `personal ? personalBundleID : appStoreBundleID`. Update the doc comment above `appTarget` (the flavors no longer share a bundle ID or an entitlements file). `uiTestsBundleID` stays `dev.ryandsilva.segue.uitests`. WS2b's Quick Look targets derive their IDs from these constants (`<host>.quicklook`).
3. **Entitlements per flavor:** App Store uses the new `App/SegueAppStore.entitlements` for every configuration; Personal keeps `App/Segue.entitlements` (Release-Personal) and `App/Segue-Debug.entitlements` (Debug-Personal). Set both `CODE_SIGN_ENTITLEMENTS` and `entitlements:` from the same per-flavor path. All three files gain `com.apple.security.network.client = true` (A61, I-15; WS3's services live in shared SegueUI code and Personal links them). On both app targets also set `"ENABLE_OUTGOING_NETWORK_CONNECTIONS": "YES"` so the Xcode sandbox build setting and the entitlements files agree (the real settings showed `NO`; do not rely on how Xcode merges a disagreement).
4. **Version and Info.plist:** replace `.extendingDefault(with:)` by an explicit `.dictionary` so `NSMainStoryboardFile` and the empty `CFBundleIconFile` are gone (06 P1):
   ```swift
   infoPlist: .dictionary([
       "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
       "CFBundleExecutable": "$(EXECUTABLE_NAME)",
       "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
       "CFBundleInfoDictionaryVersion": "6.0",
       "CFBundleName": "$(PRODUCT_NAME)",
       "CFBundleDisplayName": "Segue",                 // R3: Dock name stays "Segue"
       "CFBundlePackageType": "APPL",
       "CFBundleShortVersionString": "$(MARKETING_VERSION)",
       "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
       "LSApplicationCategoryType": "public.app-category.music",  // R3 primary category
       "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
       "NSPrincipalClass": "NSApplication",
       "NSHumanReadableCopyright": "© 2026 Ryan Rony Dsilva",     // R30, one string everywhere
       "ITSAppUsesNonExemptEncryption": false,
   ])
   ```
   `CFBundleIconName` / `CFBundleIconFile` are added by the asset compiler from `ASSETCATALOG_COMPILER_APPICON_NAME`; confirm they are still present in the built plist. `ITSAppUsesNonExemptEncryption = NO` stays correct after WS3: the app's only crypto is CryptoKit SHA-256 hashing, and HTTPS through the OS (URLSession) is exempt. No `CFBundleURLTypes`: R35 rules out x-callback-url, so WS1 registers no URL scheme. If section 5 step 8 picks the Shortcuts Events path, step 9 adds `NSAppleEventsUsageDescription` here (4.8d). WS2b adds its UTType/document-type keys to this same dictionary.
5. **Version xcconfig:** attach `Config/Version.xcconfig` to all four project configurations: `.debug(name: debugPersonal, xcconfig: "Config/Version.xcconfig")`, and the same for the other three (Tuist `Configuration.debug/release(name:settings:xcconfig:)`).
6. **Privacy manifest:** `resources: ["design/icon/Segue.icon", "App/PrivacyInfo.xcprivacy"]` for both flavors. It must land at `Segue.app/Contents/Resources/PrivacyInfo.xcprivacy`.
7. **Signing stays automatic in every configuration (B-1).** The archive is signed with Apple Development as today; the Mac App Store signing (Apple Distribution, Mac Installer Distribution, `Segue Mac App Store`, R12) happens at export through `Config/ExportOptions-AppStore.plist` (4.5). This keeps `make verify-appstore`, `make check` and local Release-AppStore launches working without the distribution certificates, while the uploaded `.pkg` is the manually signed one that verify-archive checks. Do not add `CODE_SIGN_STYLE = Manual` or a `PROVISIONING_PROFILE_SPECIFIER` anywhere.
8. **arm64 only (R41/A59):** add `"ARCHS": "arm64"` to the shared app-target base settings (next to `ENABLE_HARDENED_RUNTIME`) and to `Tuist/Package.swift` `packageSettings.baseSettings.base` (next to `MACOSX_DEPLOYMENT_TARGET`), so the app and every package target build one slice. Confirm with `lipo -archs` on a Release-AppStore build (expect exactly `arm64`).
9. **SegueUI resource bundle plist (B-6):** in `Tuist/Package.swift` `targetSettings`, give the generated resource-bundle target (`SegueUI_SegueUI`) `PRODUCT_BUNDLE_IDENTIFIER = dev.ryandsilva.segue.SegueUI.resources` and the R30 copyright. If Tuist's derived plist hard-codes those values so build settings cannot override them, stop and ask before inventing a post-processing step. `Bundle.module` finds the bundle by name, so the identifier change is safe; prove it with `make quick` (SegueUI tests load fonts and resources through `Bundle.module`).

### 4.3 `App/SegueAppStore.entitlements` (new)

Today identical to `App/Segue.entitlements` after 4.2 item 3: `app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `network.client` (R23, A61; 03 F14). It is a separate file because verify-archive pins the store set exactly while Personal may later gain personal-only keys; WS3 depends on this path. Never `network.server`, never a `temporary-exception`. Header comment: "App Store flavor only. The set is asserted exactly by scripts/verify-archive.sh check 4; change both together." Section 5 step 9 adds the Shortcuts Events keys (4.8d) to all three entitlements files if that path is chosen.

### 4.4 `App/PrivacyInfo.xcprivacy` (new)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<!-- Filled by WS3 (services) for analytics, bug reports and diagnostics. -->
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>CA92.1</string></array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>3B52.1</string></array>
		</dict>
	</array>
</dict>
</plist>
```

Basis (B-4): `UserDefaults` for the bookmark and Live settings (CA92.1, app-only); `URLResourceValues` creation/modification dates of files in the user-selected library folder (3B52.1), never shown to the user and never on container files (`FileSystem.swift:184-195`, callers in `Library/`). No disk-space or active-keyboard API. `CACurrentMediaTime` is not on Apple's list and is removed from Release by 4.8a anyway. `35F9.1` (boot time) is not declared by WS1; WS3 adds it only if the vendor SDK symbols need it, and verify-archive check 9 decides. A manifest is not enforced for macOS uploads today (Apple scopes ITMS-91053 to iOS-family platforms, research 02 section 4); it is shipped as insurance and so WS3 has a place to declare collected data.

### 4.5 `Config/ExportOptions-AppStore.plist` (new)

Keys checked against `xcodebuild -help` under Xcode 27.1 (27A9275) on 2026-10-17 (I-17):

| Key | Value | Why |
|---|---|---|
| `method` | `app-store-connect` | `app-store` is deprecated |
| `destination` | `export` | Write the `.pkg` locally so `verify-archive` checks the exact file that `altool` uploads |
| `teamID` | `V6BM673U35` | |
| `signingStyle` | `manual` | R12; the archive itself is automatic (B-1) |
| `signingCertificate` | `Apple Distribution` | |
| `installerSigningCertificate` | `Mac Installer Distribution` | |
| `provisioningProfiles` | `{ dev.ryandsilva.segue = "Segue Mac App Store"; dev.ryandsilva.segue.quicklook = "Segue Mac App Store QuickLook"; }` | I-14: one profile per bundle in the archive |
| `manageAppVersionAndBuildNumber` | `false` | The default YES lets Xcode rewrite the build number |
| `uploadSymbols` | `true` | dSYMs for App Store crash reports |
| `testFlightInternalTestingOnly` | `false` | The same build goes TestFlight then App Review (R6) |

Until WS2b lands the Quick Look extension, the archive has no `dev.ryandsilva.segue.quicklook` bundle. If `-exportArchive` under 27.1 rejects a `provisioningProfiles` entry for a bundle that is not in the archive, have `release.sh archive` drop that key from a temp copy of the plist when `Products/Applications/Segue.app/Contents/PlugIns/` has no `.appex` (log which entries were used), rather than editing the tracked file.

### 4.6 `.gitignore`

Add a backstop: `*.p8`, `AuthKey_*.p8`, `*.p12`, `*.cer`, `*.certSigningRequest`, `*.provisionprofile`. Keep the existing `Tuist/Signing.xcconfig` line. `.build/` already covers archives and exports. The R35 probe (4.10) builds into `.build/` too.

### 4.7 Scripts and Makefile

**`scripts/xcodebuild.sh`:** accept `SEGUE_DESTINATION` (default `platform=macOS,arch=arm64`), so archive can pass `generic/platform=macOS` and keep the warnings-fail result-bundle check. With `ARCHS = arm64` (4.2 item 8) the generic destination still yields an arm64-only binary.

**`scripts/bump-version.sh` (new):**
- `bump-version.sh build`: `CURRENT_PROJECT_VERSION += 1`.
- `bump-version.sh marketing X.Y[.Z]`: validates at most three non-negative integers and strictly greater than the current value (numeric, per component). Never lowers either value. Does not reset the build number.
- `bump-version.sh show`: prints `MARKETING_VERSION CURRENT_PROJECT_VERSION`, used by the other scripts (one parser, no duplicated sed).
- `build` and `marketing` edit only `Config/Version.xcconfig`, then make one signed commit of that file alone (B-5): `git commit -S -m "release: bump to <ver> (<build>)" -- Config/Version.xcconfig`. Refuse if `Config/Version.xcconfig` already has uncommitted changes. Other dirty files are fine (siblings may be working). `SEGUE_BUMP_NO_COMMIT=1` skips the commit (used by the scratch-copy test in step 2 via `SEGUE_VERSION_FILE=<path>`).

**`scripts/release.sh` (new)**, subcommands `archive | validate | upload`:
- Common: `tuist generate --no-open` via mise; read the version with `bump-version.sh show`.
- `archive`: `SEGUE_DESTINATION='generic/platform=macOS' scripts/xcodebuild.sh -scheme Segue-AppStore -configuration Release-AppStore -archivePath .build/archives/Segue-<ver>-<build>.xcarchive archive`; then `xcodebuild -exportArchive -archivePath ... -exportOptionsPlist Config/ExportOptions-AppStore.plist -exportPath .build/export/Segue-<ver>-<build>`; then `scripts/verify-archive.sh <xcarchive> <pkg>`. Refuses to overwrite an existing archive for the same version and build. Before exporting, check `security find-identity -v` lists both distribution identities and `~/Library/Developer/Xcode/UserData/Provisioning Profiles` (or `~/Library/MobileDevice/Provisioning Profiles`) holds a profile named `Segue Mac App Store`; on failure exit 1 naming the missing [RYAN] step (3, 4 or 6).
- `validate`: `archive`, then load the API key (below) and `xcrun altool --validate-app <pkg> --api-key <id> --api-issuer <issuer> --p8-file-path <tmp>/AuthKey.p8`. Add `-t macos` only if altool asks for a platform.
- `upload`: refuse a dirty `Config/Version.xcconfig` or any staged change, and refuse if tag `v<ver>+<build>` already exists; run `validate`; then `xcrun altool --upload-package <pkg> --api-key ... --api-issuer ... --p8-file-path ... --wait`. On success print version, build, git SHA, and create a signed local tag `git tag -s v<ver>+<build> -m "App Store Connect upload <ver> (<build>)"` (B-5). Never push.
- **API key loading:** `vault=${SEGUE_ASC_OP_VAULT:-Private}`, `item=${SEGUE_ASC_OP_ITEM:-Segue ASC API Key}`. First `op whoami` (or the first `op read`); on failure exit 1 with "Unlock 1Password (and enable CLI integration), then re-run". Then `tmp=$(mktemp -d)`, `trap 'rm -rf "$tmp"' EXIT`, `op read --out-file "$tmp/AuthKey.p8" --file-mode 0600 "op://$vault/$item/AuthKey.p8"`, `key_id=$(op read "op://$vault/$item/key_id")`, `issuer=$(op read "op://$vault/$item/issuer_id")`. Never echo the key, never write it under the repo. Verify the file-attachment reference syntax with a harmless `op read` once Ryan has created the item; adjust if 1Password wants the field path in a different form.
- If the tag or any `git` signing step fails with "failed to fill whole buffer", 1Password is locked: stop, leave the state, tell Ryan to unlock. Never fall back to an unsigned tag or commit.
- WS3 later appends `scripts/upload-dsyms.sh` after the tag in `upload`; leave a clearly marked hook point (a comment `# WS3: dSYM upload goes here`).

**`scripts/verify-archive.sh` (new)** `<xcarchive> <pkg>`: fails closed (any unreadable input is a failure), prints `ok:` / `FAIL:` lines like `verify-appstore.sh`, exits 1 on any failure. Factor the `forbidden` regex, the test-hook string list (below) and pass/fail helpers into `scripts/lib/verify-common.sh` and source it from both scripts so they cannot drift. "Bundles" below means the app plus every `Contents/PlugIns/*.appex`. Checks:

| # | Check | How |
|---|---|---|
| 1 | Right product | Archive `Info.plist` `ApplicationProperties.CFBundleIdentifier == dev.ryandsilva.segue`; app `CFBundleIdentifier` equal; `SchemeName == Segue-AppStore`. The only allowed appex is `dev.ryandsilva.segue.quicklook` |
| 2 | No personal code | Reuse `verify-appstore.sh` checks on every bundle: `grep -r -a -E 'SeguePersonalModules|PersonalModules|SEGUE_PERSONAL'`, `nm -a`, `otool -L` |
| 3 | Not a Debug build, no test hooks | No `Contents/MacOS/Segue.debug.dylib`; binary has none of the strings `slow key`, `slow keystroke`, `slow run loop turn`; binary has none of the test-hook strings: every launch-option key in `App/Sources/LaunchOptions.swift` (extracted with one regex from the source, so new flags are covered automatically) plus `RecordingShortcutRunner` (B-7) |
| 4 | Entitlements exact | Expand the pkg (`pkgutil --expand-full` into a temp dir) and read each bundle's signed entitlements (`codesign -d --entitlements - --xml`). App, allowed set exactly: `app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `network.client`, `print` (P9-1 spec 10: Print... from the PDF preview), `com.apple.application-identifier` (= `V6BM673U35.dev.ryandsilva.segue`), `com.apple.developer.team-identifier` (= `V6BM673U35`), plus, only if 4.8d's Shortcuts Events path is chosen, `com.apple.security.automation.apple-events = true` and `com.apple.security.scripting-targets` = exactly `{com.apple.shortcuts.events: [com.apple.shortcuts.run]}`. Quick Look appex, allowed set exactly: `app-sandbox`, application-identifier `V6BM673U35.dev.ryandsilva.segue.quicklook`, team-identifier. Fail on anything else, including `get-task-allow`, any `temporary-exception`, `network.server`, `cs.*`, or a `scripting-targets` value other than the one above |
| 5 | Signatures | `codesign --verify --deep --strict` on the app; every bundle's signing authority starts with `Apple Distribution:` and `TeamIdentifier=V6BM673U35`; `pkgutil --check-signature <pkg>` shows the installer identity (`3rd Party Mac Developer Installer` or `Mac Installer Distribution`) |
| 6 | Profiles | Each bundle has `Contents/embedded.provisionprofile`; decoded with `security cms -D -i`: `Name` is `Segue Mac App Store` (app) or `Segue Mac App Store QuickLook` (appex), `TeamIdentifier` contains `V6BM673U35`, entitlement `com.apple.application-identifier` matches the bundle, `ExpirationDate` in the future, no `ProvisionedDevices` (a distribution profile) |
| 7 | Version sanity | `CFBundleShortVersionString == MARKETING_VERSION` and `CFBundleVersion == CURRENT_PROJECT_VERSION` from `bump-version.sh show`; short version matches `^[0-9]+(\.[0-9]+){0,2}$`; build matches `^[0-9]+$`; same values in archive and pkg, and in every appex |
| 8 | Info.plist keys | `ITSAppUsesNonExemptEncryption` present and false; `LSApplicationCategoryType = public.app-category.music`; `NSHumanReadableCopyright == "© 2026 Ryan Rony Dsilva"`; `LSMinimumSystemVersion = 26.0`; `CFBundleDisplayName = Segue`; no `NSMainStoryboardFile`; `NSAppleEventsUsageDescription` present if and only if the Shortcuts Events path is chosen. SegueUI resource bundle (`Contents/Resources/SegueUI_SegueUI.bundle/Contents/Info.plist`): identifier `dev.ryandsilva.segue.SegueUI.resources`, copyright equal to the app's (B-6) |
| 9 | Privacy manifest | `Contents/Resources/PrivacyInfo.xcprivacy` exists and `plutil -lint` passes; required-reason symbols in `nm -u` map to declared categories. Symbol map: `NSUserDefaults` -> UserDefaults; `NSURLContentModificationDateKey`, `NSURLCreationDateKey`, `NSFileModificationDate`, `NSFileCreationDate`, `_stat`, `_fstat`, `_lstat`, `_fstatat`, `_getattrlist*`, `_fgetattrlist` -> FileTimestamp; `_mach_absolute_time`, `systemUptime` -> SystemBootTime; `_statfs`, `_statvfs`, `_fstatfs`, `_fstatvfs`, `NSFileSystemFreeSize`, `NSFileSystemSize`, `NSURLVolumeAvailableCapacity*` -> DiskSpace; `activeInputModes` -> ActiveKeyboards. Fail when a category is used but undeclared; warn (not fail) when declared but unused |
| 10 | Icons | `iconutil -c iconset` on `Contents/Resources/Segue.icns` must contain all ten sizes `icon_16x16` through `icon_512x512@2x`; `assetutil --info Assets.car` must have app-icon renditions at 512 and 1024 px (B-3, strict) |
| 11 | Architectures | `lipo -archs` on every Mach-O in every bundle equals exactly `arm64` (R41/A59) |
| 12 | Quarantine | `xattr -r` finds no `com.apple.quarantine` anywhere in the app (Apple requirement since 2025-02-18, research 02 section 5) |
| 13 | dSYM | `dSYMs/Segue.app.dSYM` exists in the archive and its UUIDs (`dwarfdump --uuid`) match the binary's (and the same for each appex dSYM) |

Check number 14 is reserved for WS3 (vendor keys and symbols).

**`Makefile`:** add to `.PHONY` and help:
```
archive:   ## Archive + export the App Store .pkg and run verify-archive (no upload)
	scripts/release.sh archive
validate:  ## archive, then App Store Connect validation (API key from 1Password)
	scripts/release.sh validate
upload:    ## validate, then upload the verified .pkg (tags locally, signed; never pushes)
	scripts/release.sh upload
bump:      ## Bump + commit the build number; `make bump VERSION=0.6` sets the marketing version
	scripts/bump-version.sh $(if $(VERSION),marketing $(VERSION),build)
probe-shortcuts: ## R35 probe: build the sandboxed Shortcuts Events probe app (research/shortcuts-events-probe)
	research/shortcuts-events-probe/build.sh
```
Add `plutil -lint Config/ExportOptions-AppStore.plist App/PrivacyInfo.xcprivacy App/*.entitlements` to `lint` (cheap, runs in `quick`). `check` keeps its current list; archive/validate/upload are explicit release steps, not part of `check`.

**`scripts/verify-appstore.sh`:** extend `check_no_exception` with: both the App Store and the Personal Release products' signed entitlements contain `network.client` (A61, inverted from the earlier draft so WS3 does not have to edit it); and the test-hook string check from verify-archive check 3 on the App Store Release product (sourced from `scripts/lib/verify-common.sh`). Header comment: mention the split bundle IDs. WS5 adds only its own flag strings to the shared list if they are not already `LaunchOptions` keys (I-12).

### 4.8 Readiness fixes (code)

**a. Logging (06 R4, 03 F6).**
- `Packages/SegueUI/Sources/SegueUI/Editor/SourceTextView.swift` `keyDown`: the typed character is removed from the log message in every build (not `.private`, gone). Wrap the timing (`CACurrentMediaTime`), the slow-key notice and the `onKeystrokeTimed` callback in `#if DEBUG`. The `layoutViewport()` call is behaviour, not measurement: it stays in all builds.
- `Editor/CanvasViews.swift` `keyDown` (line ~58): same treatment for its timing and callback.
- `Editor/EditorPerformance.swift`: `MainThreadHitchMonitor` and the `EditorPerformance.log` notices become `#if DEBUG` only. `KeystrokeStats` may stay (pure value type) if it is still referenced; otherwise gate it too.
- `Editor/SongEditorViewModel.swift` `recordKeystroke` (lines ~350-366) and the `hitches` property: `#if DEBUG`. Keep the E2E typing-latency instrumentation working in Debug (it is read only when `UITesting.isActive`).
- Result: the Release binary has no `slow key`/`slow keystroke`/`slow run loop turn` strings and no `_CACurrentMediaTime` import (verify-archive check 3; confirm with `nm -u`).

**b. Test-only accessibility help (03 shipping-bundle finding 1, F5; I-13: WS1's delete wins).**
- `Editor/SourceEditorController.swift:85` and `Editor/VisualEditorController.swift:65`: delete `textView.setAccessibilityHelp(EditorTextInput.report(textView))`. No UI test reads the text view's help (grep `UITests/` for `.help`: none); the E2E suite reads the input-settings report from the `UITesting`-only element in `EditorBars.swift:134-145`, which stays. If an E2E test turns out to need the help text, stop and ask (do not re-add it).

**c. Gig Mode default off (R18; 06 R5; 03 F4).**
- `Packages/SegueCore/Sources/Shows/LiveSettings.swift`: `init` defaults `startShortcut: String? = nil`, `endShortcut: String? = nil`. Rename `defaultStartShortcut` / `defaultEndShortcut` to `suggestedStartShortcut` / `suggestedEndShortcut` (values `Gig Mode On` / `Gig Mode Off`), used only by the Settings guide and the text field prompt; update the `ChecklistItem.focus` doc comment.
- `Packages/SegueUI/Sources/SegueUI/Settings/LiveSettingsView.swift` (text only, I-6): the guide says the Shortcuts are off until set up, then explains how ("Create a Shortcut named “Gig Mode On” that turns on your Performing Focus, then enter its name here."). Text field prompt: `Gig Mode On` / `Gig Mode Off` as placeholder (prompt, not value). The "Test" button runs the start Shortcut through the chosen runner and shows the real result (4.8d); on the Shortcuts Events path it is also where the Automation permission is first requested, so the prompt never first appears mid-show.
- Already-stored settings (A38 = leave them): no migration. Installs that stored "Gig Mode On/Off" keep them. (Ryan's own container is moved aside by [RYAN] step 10, so the TestFlight run starts with nothing stored.)

**d. Checklist truthfulness (R18, R35; research 09 section 3).**

Rule: the Focus row ticks only when completion was **observed** (the Shortcut returned) or the performer pressed **Done**. A URL hand-over, a timeout or an error never ticks it.

Model (`Packages/SegueUI/Sources/SegueUI/Live/PreShowChecklist.swift`):

| `FocusStatus` | When | Row detail | Ticks? |
|---|---|---|---|
| `notConfigured` | No start Shortcut set | Row **hidden** (A37); WS2b's `GigModeTip` handles discovery | - |
| `notRun` | Rehearsal (Shortcuts are off for rehearsals) | unchanged from today | no |
| `running(name)` | Request sent, awaiting the result | "Running “\(name)”..." | no |
| `ran(name)` | Observed completion: Shortcuts Events `run` returned without error | "“\(name)” ran." | **yes** |
| `unknown(name)` | Timed out (`ShortcutTiming.confirmTimeout = 30 s`, measured on the injected clock) or only a hand-over is known | "Asked Shortcuts to run “\(name)”; couldn't confirm it finished." + **Done** | no, until Done |
| `failed(name, message)` | Observed failure: not found, permission denied, the Shortcut's own error | "“\(name)” failed: \(message)." + **Retry** + **Done** | no, until Done |

- Manual Done fallback (R35): a `focusConfirmedByPerformer: Bool` next to `brightnessConfirmed`, with the same Done / Undo button pattern as the brightness row. `isDone(.focus)` is `true` when `focus` is `.ran` **or** `focusConfirmedByPerformer`. Done appears on `.unknown` and `.failed` only. Retry re-runs the start Shortcut and resets `focusConfirmedByPerformer`.
- `visibleRows` drops `.focus` when `focus == .notConfigured` (A37), so an unconfigured checklist never shows an un-tickable row; the row's accessibility value stays `done` / `not done`.
- `ShortcutRunner` (`Live/ShortcutRunner.swift`) becomes `func run(_ name: String) async -> ShortcutOutcome` with `enum ShortcutOutcome: Equatable { case completed, handedOver, failed(String) }`. `WorkspaceShortcutRunner` returns `.handedOver` (it can never return `.completed`). `AppModel+Shows.swift` maps `.completed` -> `.ran`, `.failed` -> `.failed`, `.handedOver` -> `.running` then `.unknown` after `confirmTimeout`. Update the doc comments ("hand-over is not completion") and the `PreShowChecklist` type comment.
- `confirm(_:)`: a cancelled start runs the end Shortcut whenever a start request was sent (any status except `notConfigured` / `notRun`), since the Focus may be on.
- `RecordingShortcutRunner` (Debug only, 4.8f): names starting with `fail` -> `.failed("simulated failure")`; names starting with `hang` -> `.handedOver` with no confirmation (exercises the timeout); all others -> `.completed`.

How completion is observed (the probe in section 5 step 8 confirms it, R35):

- **Path SE - Shortcuts Events via Apple events.** New `AppleEventShortcutRunner` in `Live/`: build `NSAppleEventDescriptor(eventClass: <FourCharCode "srct">, eventID: <FourCharCode "run ">, targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.shortcuts.events"), returnID: kAutoGenerateReturnID, transactionID: kAnyTransactionID)` with the direct parameter an object specifier for `shortcut` by name (form `name`, container null), and send it with `sendEvent(options: [.waitForReply], timeout: 60)` from a detached task (never on the main actor; `NSAppleScript` is not used). Before sending during a show, call `AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, false)`; if not yet granted, return `.failed("Allow Segue to control Shortcuts Events in System Settings > Privacy & Security > Automation")` without prompting. The Settings > Live "Test" button calls it with `askUserIfNeeded: true`. Error mapping: `-1728` -> "Couldn't find a Shortcut named “\(name)”"; `-1743` (`errAEEventNotPermitted`) -> the Automation message above; `-1712` (timeout) -> `.handedOver` (becomes `.unknown`); anything else -> `.failed(<localized error>)`. Entitlements, all three files: `com.apple.security.scripting-targets` = `{ "com.apple.shortcuts.events": ["com.apple.shortcuts.run"] }` and `com.apple.security.automation.apple-events = true` (hardened runtime is on). Info.plist: `"NSAppleEventsUsageDescription": "Segue runs your Gig Mode Shortcuts through Shortcuts Events so it can tell whether they finished."`. No `temporary-exception` (the access group is Apple-published; QA1888).

x-callback-url is not used (R35; research 09 section 1: `x-error` code 4 on success since macOS 26.5).

**e. E2E fallout.** Existing live tests assume the old defaults:
- `UITests/SegueLiveE2ETests.swift:28,48` and `UITests/SegueLiveE2ETests+Hardening.swift:31` assert `["Gig Mode On", ...]` ran by default. Add two Debug-only launch flags in `App/Sources/LaunchOptions.swift`: `-SegueStartShortcut <name>` and `-SegueEndShortcut <name>`, applied to the test defaults suite's `LiveSettings` at launch (test runs only, like the other flags; document them in the type's doc comment and count them in `isTestRun`). Those three tests pass them explicitly. The rehearsal test (line ~170, rehearsals skip Shortcuts) passes them too, so it still proves the rehearsal rule rather than the empty default.
- `UITests/SegueLiveE2ETests+Hardening.swift:40` hard-codes `"dev.ryandsilva.segue"` for the single-instance test: use `dev.ryandsilva.segue.personal` (the UI tests drive the Personal target).
- Any test that asserted the focus row's old "ran" text after a plain hand-over now expects the observed-completion behaviour of the recording runner (`.completed` -> "ran"), or `.unknown` for `hang` names.

**f. Test hooks out of Release (B-7, I-12).** Wrap `RecordingShortcutRunner`, the whole `LaunchOptions` type and parser, and every flag-string literal in `#if DEBUG`. Release code paths that referenced them take the real implementation unconditionally (`WorkspaceShortcutRunner` or `AppleEventShortcutRunner`, real `UserDefaults.standard`, real Application Support paths). `UITesting.isActive` must compile to `false` in Release. verify-archive check 3 and verify-appstore enforce it.

**g. Cross-flavor library lock (B-2).** With separate bundle IDs the single-instance guard (`App/SingleInstance.swift`, per bundle ID) no longer stops Personal and the App Store build opening the same library. Add `LibraryRoot.lockURL` = `<root>/.segue/library.lock` (SegueCore `Support/LibraryRoot.swift`) and a `LibraryLock` (SegueCore) that opens it and takes `flock(fd, LOCK_EX | LOCK_NB)`, holding the descriptor for the lifetime of the `LibrarySession`; the kernel releases it on exit or crash, so there is no stale-lock cleanup. If the lock is held, opening fails with a new `AppModel.NeedsLibraryReason.inUseByAnotherCopy`, and the chooser says: "This library is open in another copy of Segue. Quit it there, then choose the library again." The write is advisory and inside the user-selected folder, so it needs no new entitlement. `.segue/` is already excluded from WS2b's archive export (B-23). Test: an integration test in SegueCore that takes the lock in one `LibraryLock` and asserts a second one fails, then succeeds after the first is released (two locks in one process use two file descriptors; `flock` locks are per open file description, so this is a faithful check).

### 4.9 Docs

- `docs/decisions.md` line 8 (signing) and lines 81 and 107 (shared bundle ID and entitlements): update to the paid team, the split bundle IDs, per-flavor entitlements, and export-time manual signing, pointing at `docs/release/decisions.md` R11-R13 and B-1.
- `docs/release/research/09-shortcut-confirmation.md`: append a "Probe results (2026-10-xx)" section with the recorded results table from section 5 step 8, and the chosen path.
- Do not edit `JOURNAL.md` by hand mid-session; use the handoff skill at the end. Do not touch any auto-generated file.
- Add a short "Releasing" section to the README only if the repo already has one that lists make targets (check; do not create a README).

### 4.10 R35 probe: `research/shortcuts-events-probe/` (new, tracked)

A throwaway, minimal sandboxed app that exercises exactly the production send path, following the repo's `research/<spike>/` convention. Not part of any app target.

- `main.swift`: an `NSApplication`-less executable that takes a shortcut name and a mode (`event` = `NSAppleEventDescriptor.sendEvent` exactly as 4.8d Path SE; `permission` = only `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true)`). It prints one JSON line per run: `{ "name", "mode", "os": ProcessInfo.operatingSystemVersionString, "permission": <OSStatus>, "errorNumber": <Int or null>, "errorMessage", "result": <string description or null>, "seconds": <Double>, "frontmostBefore", "frontmostAfter" }` (front app bundle IDs from `NSWorkspace.shared.frontmostApplication`).
- `Info.plist`: `CFBundleIdentifier dev.ryandsilva.segue.shortcutsprobe`, `CFBundleExecutable ShortcutsEventsProbe`, `NSAppleEventsUsageDescription "Probe for Segue: run test Shortcuts through Shortcuts Events."`, `LSUIElement YES`.
- `probe.entitlements`: exactly `com.apple.security.app-sandbox`, `com.apple.security.scripting-targets` = `{ com.apple.shortcuts.events: [com.apple.shortcuts.run] }`, `com.apple.security.automation.apple-events`. Nothing else (no temporary exception, no network).
- `build.sh`: `swiftc -O -o .build/shortcuts-probe/ShortcutsEventsProbe.app/Contents/MacOS/ShortcutsEventsProbe main.swift`, copy `Info.plist`, then `codesign --force --options runtime --entitlements probe.entitlements --sign "Apple Development" .build/shortcuts-probe/ShortcutsEventsProbe.app` (a real development identity, the same hardened-runtime + sandbox shape as Segue), then `codesign -d --entitlements - --xml` to print what was signed.
- `run.sh <name> <mode>`: `open -W -n --stdout "$out" --stderr "$out" .build/shortcuts-probe/ShortcutsEventsProbe.app --args "<name>" <mode>` (launched via LaunchServices so TCC attributes the Automation request to the probe app, not Terminal), then prints `$out`. `$out` is a file under `.build/shortcuts-probe/results/`.
- A `README.md` is not needed; the procedure lives in section 5 step 8 and the results go into research 09.

## 5. Step order

Each step ends green on its own tests before the next starts (tier per section 6). Commit one signed commit per step (`git commit -S`); do not push. Steps 1-7 need nothing from Ryan.

1. **Bundle ID split, per-flavor entitlements, network.client, arm64** (4.2 items 1-3 and 8, 4.3, 4.8e bundle-ID line, verify-appstore `network.client` assertion). `make generate`, `make quick`, `make e2e-one TEST=SegueLiveE2ETests/testSecondLaunchHandsOverToTheRunningInstance`, `make verify-appstore`; `lipo -archs` on the Release-AppStore product prints `arm64`. Commit message notes that the Personal build now has a fresh container and points at [RYAN] step 10. Then tell Ryan step 10 is ready to run.
2. **Version xcconfig, Info.plist, resource-bundle plist, bump script, Make `bump`** (4.1, 4.2 items 4, 5 and 9, `bump-version.sh`). `make quick`; inspect the built plist with `plutil -p` (all keys from 4.2 item 4, copyright `© 2026 Ryan Rony Dsilva`, no storyboard key, icon keys present, version `0.5 (1)`) and the SegueUI resource bundle's plist. Run `bump-version.sh` with `SEGUE_VERSION_FILE` on a scratch copy and `SEGUE_BUMP_NO_COMMIT=1` to exercise build bump, marketing bump, and the refusals (lower, equal, four components, non-numeric).
3. **Privacy manifest** (4.4, 4.2 item 6). `make quick`; the file is in both products' Resources.
4. **Logging and accessibility help** (4.8a, 4.8b). `make quick`; `make e2e-one TEST=SegueEditorE2ETests` (typing latency and input-settings instrumentation still work in Debug); build Release-AppStore and confirm with `strings`/`nm -u` that the perf strings and `_CACurrentMediaTime` are gone.
5. **Test hooks out of Release** (4.8f) and the shared `verify-common.sh` test-hook list used by verify-appstore. `make quick`; `make verify-appstore`; `make e2e-one TEST=SegueLiveE2ETests` (proves Debug test hooks still work).
6. **Gig Mode default off, Focus status model, manual Done, hidden unconfigured row, launch flags, test updates** (4.8c, the path-independent parts of 4.8d, 4.8e). The runner protocol changes to `ShortcutOutcome`; `WorkspaceShortcutRunner` stays the production runner for now, so a real show reaches `.unknown` + Done (truthful in the meantime). `make quick`; `make e2e-one TEST=SegueLiveE2ETests`; the new tests in 6.3 items 1-4.
7. **Cross-flavor library lock** (4.8g). `make quick` (the SegueCore integration test); `make e2e-one TEST=SegueLiveE2ETests/testSecondLaunchHandsOverToTheRunningInstance`.
8. **R35 probe** (4.10) - needs [RYAN] step 9.
   1. Build: `make probe-shortcuts`. Confirm the printed entitlements are exactly the three in 4.10.
   2. Ask Ryan to create the two Shortcuts ([RYAN] step 9) and to be at the Mac.
   3. Run, in order, recording each JSON line: `run.sh "Segue Probe OK" permission` (Ryan answers the Automation prompt: OK); `run.sh "Segue Probe OK" event` three times; `run.sh "Segue Probe Fail" event` twice; `run.sh "Segue Probe Missing" event` once. Also run the unsandboxed control once from Terminal: `osascript -e 'tell application "Shortcuts Events" to run shortcut "Segue Probe Fail"'; echo $?`.
   4. Ask Ryan for what the JSON cannot capture: did any prompt appear on a run after the first (the CVE-2026-28993 "additional prompt for user consent"), did the Shortcuts app or anything else come to the front, did the notification from "Segue Probe OK" appear.
   5. Record a results table (run, mode, errorNumber, errorMessage, seconds, frontmost before/after, Ryan's observations) in research 09 (4.9).
   6. **Choose the path** by this rule. Path SE if **all** hold: (a) after the one-time OK, every `Segue Probe OK` run returns with no error number; (b) every `Segue Probe Fail` run returns a non-zero error number (a failing action is observed as a failure, not a normal return); (c) the missing name returns `-1728`; (d) no prompt after the first run; (e) the frontmost app is unchanged by a run; (f) each OK run finishes in under 10 s; (g) the signed entitlements needed no `temporary-exception`. Otherwise stop and ask Ryan. Write the rule outcome per letter into research 09 and the commit message. If the results are ambiguous against a letter (for example (b) holds on one run and not the other), stop and ask Ryan rather than choosing.
   7. Ask Ryan to `mv` the probe container aside like [RYAN] step 10d: `mv ~/Library/Containers/dev.ryandsilva.segue.shortcutsprobe ~/segue-backups/`.
9. **Confirmation path** (the chosen half of 4.8d): Path SE (`AppleEventShortcutRunner`, entitlements in all three files, `NSAppleEventsUsageDescription`, Settings "Test" asks for permission, verify-archive/verify-appstore allowed sets include the two keys). `make quick`; `make e2e-one TEST=SegueLiveE2ETests` plus 6.3 item 5; then a manual real-Shortcut check on the Personal build (4.8d acceptance, 6.4).
10. **Release scripts, ExportOptions, verify-archive, Make targets, .gitignore, lint** (4.5-4.7). The archive and verify-appstore need no certificates; the export step needs [RYAN] steps 1-6, so write and lint everything first, then stop and ask if `security find-identity` does not show both identities or `Segue Mac App Store` is not installed. `make lint`; `make archive`. Expect check 10 (icns) to fail until step 11; everything else must pass.
11. **Icon sizes (B-3).** Extend `scripts/gen-icon.swift` to render all ten legacy sizes (16, 16@2x, 32, 32@2x, 128, 128@2x, 256, 256@2x, 512, 512@2x) from the same artwork with `ictool` (as it already does for previews) into `design/icon/Segue.iconset/`, and wire them so the built `Segue.icns` carries all ten: first try a `Segue.appiconset` with those PNGs in an asset catalog next to `Segue.icon` (same name, so `ASSETCATALOG_COMPILER_APPICON_NAME` picks up both); if the asset compiler still emits a reduced `.icns`, stop and ask before adding a build-phase replacement. `icon-check` checks the PNG set exists at the right pixel sizes (renders may not be byte-identical, like the previews). `make icon-check`; `make archive` fully green.
12. **Validation** - needs [RYAN] steps 7-8. `make validate`. Record every validator message in the session journal. Fix and re-run until clean.
13. **Final gate:** one `make check`.
14. **First upload (B-9)** - as soon as step 12 is clean, internal TestFlight only. Needs [RYAN] step 11 (1Password unlocked). `make upload` (build 1). Then hand over [RYAN] step 12, reminding Ryan that step 10 must be done before installing. For every later upload: `make bump` (signed commit), then `make upload`.

## 6. Test plan

Follows the repo budget: `make quick` after each small change, `make e2e-one TEST=...` for the touched UI, one `make check` at the end. Prefer E2E and integration tests against real components on a reset state; unit tests only for tricky pure logic.

### 6.1 Per step (fast tier)
- `make quick` (lint incl. new `plutil -lint`, Personal build, core + UI package tests) after every step.
- Targeted E2E: steps 1 and 7 `SegueLiveE2ETests/testSecondLaunchHandsOverToTheRunningInstance`; step 4 `SegueEditorE2ETests`; steps 5, 6 and 9 `SegueLiveE2ETests`.
- `make verify-appstore` after steps 1, 3, 5 and 9 (it builds Release-AppStore).

### 6.2 New tests
- **Integration (SegueUI package, `AppHardeningTests` style):** build a `SourceEditorController` and a `VisualEditorController` and assert `textView.accessibilityHelp()` is nil or empty. (XCUITest on macOS exposes no help attribute, so this is the closest real-component check.)
- **Integration (SegueUI):** `LiveSettingsStore` on a fresh `UserDefaults` suite returns nil start/end Shortcut names; a stored JSON with names round-trips unchanged (documents A38).
- **Integration (SegueCore):** `LibraryLock` exclusivity and release (4.8g).
- **Pure logic (SegueUI):** the `ShortcutOutcome` -> `FocusStatus` mapping including the timeout on a manual test clock (`.handedOver` -> `.running` -> `.unknown` at 30 s; a confirmation before 30 s -> `.ran`), and `isDone(.focus)` across every status with and without `focusConfirmedByPerformer`. This is the tricky state logic R18 depends on, so it earns a table-driven test.
- `bump-version.sh` refusals are checked by hand in step 2 (scratch copy), not by a new test: the script runs rarely and verify-archive check 7 catches a bad version anyway.

### 6.3 E2E for R18 / R35 (new, in a new `UITests/SegueGigModeE2ETests.swift`)
All start from a reset library (`-SegueResetState YES`) and the recording runner (`-SegueShortcutLog`), without the new name flags unless stated:
1. **Off by default:** fresh launch, start a gig. Shortcut log stays empty; the checklist has **no** focus row (A37); open Settings > Live and assert both Shortcut fields are empty (placeholder only). End the show: the log is still empty.
2. **Set up through the real UI:** in Settings > Live type `Gig Mode On` / `Gig Mode Off` into the fields (`AccessibilityID.settingsStartShortcut` / `settingsEndShortcut`), close Settings, start a gig: the log has `Gig Mode On` and the focus row appears. End: the log has both names.
3. **Failure stays unticked, Done is the fallback:** start name `fail-gig` (via the launch flag): row `not done`, detail shows the failure, Retry and Done present; click Done: `done`; click Undo: `not done`.
4. **Timeout stays unticked:** start name `hang-gig` with `-SegueLiveTimeScale` so 30 s passes quickly: row goes from "Running..." to the "couldn't confirm" detail, `not done`; Done ticks it.
5. **Observed completion ticks** (step 9): Path SE - start name `Gig Mode On` (recording runner returns `.completed`): row `done` with "ran", no Done button.

### 6.4 Release and probe checks (manual, run once in the session)
- `make archive`: verify-archive all `ok`. Then negative checks against a copy of the archive in the scratchpad, each must FAIL: add `com.apple.security.temporary-exception.files.absolute-path.read-write` by re-signing a copy with an extra entitlement; change `CFBundleVersion` in the copy's plist; delete `PrivacyInfo.xcprivacy` from the copy; `lipo -create` an x86_64 slice into the copy's binary (or re-sign a universal build) to trip check 11. (Copies only; never touch the real archive.)
- `make validate`: clean validation from App Store Connect.
- Run `scripts/verify-archive.sh` on a Release-Personal archive and expect checks 1 and 2 to fail.
- After step 9, on the Personal build with Ryan: set the start Shortcut to `Segue Probe OK` (or Ryan's real "Gig Mode On"), press Settings > Live "Test", then start a gig: the row ticks only after the Shortcut finished; with `Segue Probe Fail` it shows the failure.

### 6.5 Final
- One `make check` (lint, tokens, icon, both builds, tests, full E2E, verify-appstore). Personal E2E runs under the new bundle ID.

## 7. Acceptance criteria

1. `Project.swift`: Personal is `dev.ryandsilva.segue.personal`, App Store is `dev.ryandsilva.segue`; every configuration signs automatically; the uploaded `.pkg` is signed at export with `Apple Distribution`, `Mac Installer Distribution` and `Segue Mac App Store` (plus `Segue Mac App Store QuickLook` for the extension once WS2b adds it).
2. `Config/Version.xcconfig` is the only place the version lives; the shipped plist shows `1.0` and the xcconfig build number; `make bump` and `make bump VERSION=x.y` make a signed commit and refuse to go backwards.
3. Shipped Info.plist has `ITSAppUsesNonExemptEncryption = false`, copyright `© 2026 Ryan Rony Dsilva`, category music, display name Segue, no `NSMainStoryboardFile`; the SegueUI resource bundle has the real identifier and the same copyright.
4. `PrivacyInfo.xcprivacy` ships in the app with the declared categories matching the binary.
5. App Store signed entitlements = sandbox, user-selected read-write, app-scope bookmarks, network client, the application/team identifiers, and (Path SE only) apple-events + the one Shortcuts Events scripting target. Personal has network client too. No temporary exception in any shipping product.
6. The App Store binary is arm64 only and contains no launch-option strings or `RecordingShortcutRunner`.
7. `make archive` produces `.build/archives/Segue-1.0-<n>.xcarchive` and `.build/export/Segue-1.0-<n>/Segue.pkg`; `verify-archive` passes all 13 checks; `make validate` passes App Store Connect validation.
8. `make upload` reads the API key from 1Password only at run time, leaves no key file behind (`find .build "$TMPDIR" -name 'AuthKey*'` empty after a run), refuses a reused build number, creates the signed local tag `v0.5+<n>`, and never pushes. Build 1 is in App Store Connect and available to the internal TestFlight group.
9. Release binary: no typed characters or editor perf logs (`log stream --predicate 'subsystem == "dev.ryandsilva.segue"'` while typing in a Release-AppStore build shows nothing from `editor-perf`); no accessibility help on the editor text views.
10. Fresh install: Gig Mode Shortcuts are off; starting a gig runs no Shortcut and shows no focus row. Once configured, the row ticks only on observed completion (path from step 8, recorded in research 09) or the performer's Done; never from a hand-over, timeout or error. The 6.3 E2E tests pass.
11. Personal and the App Store build cannot open the same library at once.
12. [RYAN] step 10 done: Ryan's shapes and bindings are in the Personal container, and the old container sits in `~/segue-backups/`.
13. `make check` green at the end; zero warnings.

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Export-time manual signing fails although the archive built (missing cert, profile name typo, Quick Look profile missing) | `make archive` stops at export | release.sh pre-checks identities and profiles and names the missing [RYAN] step; verify-archive checks 5-6 on the exported pkg |
| Icon: `Segue.icns` lacks 512 and 512@2x | Validation or upload rejected (research 02 risk 1) | B-3 step 11; verify-archive check 10 strict; validate before upload |
| Xcode 27.1 SDK adds warnings under warnings-as-errors | Builds fail | Baseline `make check` is already green on 27.1 (R41); keys and altool flags re-checked (section 2) |
| Personal gets a fresh container | Ryan's daily build forgets the library bookmark and Live settings | [RYAN] step 10 copies shapes and bindings; library and Shortcut names are re-chosen once |
| Container move blocked by macOS app-data protection | Step 10 fails with "Operation not permitted" | Allow the prompt, or grant Terminal Full Disk Access temporarily; `mv` only, nothing deleted, rollback by `mv` back |
| An App Store-flavor build is launched after step 10 | TestFlight inherits a non-clean container | Step 10 includes the re-check `mv` right before the TestFlight install |
| Path SE: App Review questions the Apple-events entitlement | Rejection or review delay | Apple-published access group, no temporary exception (QA1888); WS5 review notes explain it; the runner sits behind `ShortcutRunner`, so switching mechanisms is local |
| Path SE: a future macOS adds a per-run consent prompt (CVE-2026-28993 style) | Prompt mid-show | Permission is checked without prompting during a show; anything unexpected maps to `.failed`/`.unknown` with the Done fallback |
| Lock file on a network or synced library folder where `flock` is not honoured | Two flavors could still both open it | Same as today's risk for any two Macs; local folders are the supported case |
| Build-number drift | Rejected upload | `manageAppVersionAndBuildNumber = false`; verify-archive check 7; refuse reused tags |
| 1Password locked during upload, bump or tagging | Script hangs or unsigned tag/commit | Fail fast with an unlock message; never fall back to unsigned |
| API key leaks | Account compromise | Key only in a 0600 temp dir with a trap; `.gitignore` backstop; App Manager rather than Admin |
| Uploading the wrong flavor | Personal (licence-encumbered) code in the store | Separate bundle ID; verify-archive checks 1-2 |

## 9. Open questions for Ryan

Everything from the earlier draft is resolved: Q1 -> R35 (probe, then Shortcuts Events, plus manual Done); Q2 -> A38 leave; Q3 -> R40; Q4 -> B-2; Q5 -> A61; Q6 -> B-1; Q7 -> B-3; Q8 -> B-4; Q9 -> R41; Q10 -> arm64 (R41/A59); Q11 -> B-5; Q12 -> R30; Q13 -> B-6; Q14 -> B-7; Q15 -> A37 hide; Q16 -> B-8; Q17 -> B-9.

One new question; it blocks nothing, and the default applies if you do not answer:

1. **Two apps called "Segue".** After the split, the Personal build and the TestFlight/App Store build are separate apps that both show as "Segue" in the Dock, Spotlight and Launchpad. Keep "Segue" for both (default; R3 names the store build only), or give the Personal flavor `CFBundleDisplayName = "Segue Personal"` so you can tell them apart?

## 10. Implementation notes

Recorded during the steps 1-7 session (2026-10-17); orchestrator rulings, no open questions.

- **4.8b accessibility help (step 4).** Removing `setAccessibilityHelp` also removed the editor text views from the XCUITest tree (the editor E2E suite could not find them). Both views now call `setAccessibilityElement(true)` explicitly; no help text is set in any build.
- **4.8d row state in E2E (step 6).** XCUITest does not expose the accessibility value of a SwiftUI row that contains its children, so the `done` / `not done` value cannot be read there. Each checklist row adds a 1x1 element only while `UITesting.isActive` (`segue.live.checklist.row.state`, label `"<row title>: done"`), the same pattern as the editor's typing-latency instrumentation. The row keeps its accessibility value for VoiceOver.
- **4.2 item 9, B-6 (step 2).** Tuist applies no target settings to the synthesized `SegueUI_SegueUI` bundle target, and its derived plist hard-codes the placeholder copyright. A post build phase on both app targets, `scripts/stamp-resource-bundle.sh`, sets the bundle's `CFBundleIdentifier` to `dev.ryandsilva.segue.SegueUI.resources` and copies the app's `NSHumanReadableCopyright`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` into it before code signing. `check_resource_bundle` in `scripts/lib/verify-common.sh` asserts the result; verify-appstore runs it on Release-AppStore, and verify-archive (step 10) uses it for check 8.
- **4.8g library lock wiring (step 7).** `AppDependencies.libraryLock: LibraryLockPolicy` (`.exclusive` by default, `.unlocked`). `LibrarySession` takes the lock before opening any store and holds it for its lifetime; re-opening the already open library reuses that session's lock. Package integration tests that deliberately run several in-process app instances on one library set `.unlocked`; `LibraryLockAppTests` keeps the real lock and proves a second `AppModel` lands on `.needsLibrary(.inUseByAnotherCopy)` and can open the library once the first is gone.
- **Recording runner before step 9.** Names not starting with `fail` or `hang` return `.completed` (the Path SE behaviour) until step 9 picks the confirmation path.
- **4.5 installer certificate name (step 10).** `xcodebuild -exportArchive` matches `installerSigningCertificate` by the certificate's common name, which for a Mac Installer Distribution certificate is still `3rd Party Mac Developer Installer: ...`; the value `Mac Installer Distribution` fails with "No certificate ... matching". `Config/ExportOptions-AppStore.plist` uses the legacy name and `release.sh` pre-checks the keychain for exactly that identity.
- **4.5 Quick Look profile entry (step 10).** `release.sh` always exports with a temp copy of the export options that keeps only the `provisioningProfiles` entries for bundles present in the archive (and requires each of those profiles to be installed), so the tracked file names both profiles and nothing changes when WS2b embeds the extension.
- **4.7 archive reuse (step 10).** `archive` refuses to rebuild an existing `Segue-<ver>-<build>.xcarchive` (resuming only a missing export), while `validate` and `upload` reuse the existing archive and `.pkg` after re-running verify-archive, so `make archive && make validate && make upload` checks and ships one build. A sidecar `.build/archives/Segue-<ver>-<build>.provenance` records the commit and dirty-path count at archive time; `upload` signs the tag on that commit. `validate` and `upload` take `DRY_RUN=1` (everything except `op`, App Store Connect, the tag and the dSYM upload), which is how agents test them (R46).
- **4.7 dSYM upload (step 10).** `scripts/upload-dsyms.sh`, `.sentryclirc` and the `upload-dsyms` target are in place (WS3 6.5). sentry-cli 3.8.0 comes from mise's aqua backend: the github backend installs the binary as `sentry-cli-Darwin`, which mise cannot exec.
- **4.7 verify-archive Path SE (step 10).** Checks 4 and 8 read `App/SegueAppStore.entitlements`: when it declares `com.apple.security.automation.apple-events`, the app's allowed set gains the two Path SE keys and `NSAppleEventsUsageDescription` is required; otherwise all three are forbidden. Step 9 needs no verify-archive edit.
- **B-3 icon sizes (step 11).** A `Segue.appiconset` next to `Segue.icon` does not help: `actool` emits the reduced `.icns` (16, 32, 128, 256 px) even for an appiconset alone. The documented asset-compiler setting `ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR = all` (`--standalone-icon-behavior all`) writes all ten sizes from `Segue.icon` itself, so no PNGs are rendered or tracked, `gen-icon.swift` and `icon-check` are unchanged, and verify-archive check 10 is the gate.
- **4.8d Path SE (step 9).** `AEDeterminePermissionToAutomateTarget` answers -600 while Shortcuts Events is not running (it quits when idle; seen on 26.6.2), so `SystemShortcutsEvents` starts it hidden with `NSWorkspace.openApplication` and checks again before sending. -1744 (never asked) gets its own message ("press Test in Settings > Live"). The Apple-event side sits behind the `ShortcutsEvents` protocol; the Debug-only `RecordingShortcutRunner` is now the production `AppleEventShortcutRunner` over a fake `RecordingShortcutsEvents` that answers by name prefix (`fail` -1753, `missing` -1728, `denied` -1743, `hang` -1712), so the E2E suite exercises the real reply mapping. verify-appstore now asserts the exact signed entitlement set (`app_entitlements` in `scripts/lib/verify-common.sh`, ignoring only development signing's get-task-allow), and verify-archive expects the Path SE keys unconditionally.
