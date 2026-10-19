# Phase 3: MLX inside the shipped app (P3-A spike, 2026-10-19)

Workstream P3-A (`docs/phases/3-workstreams/P3-A-mlx-in-shipped-app.md`), Part 1. It proves that MLX runs inside the real Segue app: built by Tuist, sandboxed, with the hardened runtime, archived as Release-AppStore, and reading its model from an app-group store that both flavours share (R67). Part 2 (re-scoring Qwen3-4B on Ryan's own pastes, R64) is waiting on the pastes; see section 8.

The experiment lives on branch `spike/p3a-mlx-in-app` (worktree `../setlist-p3a`). It is never merged as is. P3-3 applies the diff in section 6.

## Short answer

- **Yes, MLX works in the shipped app.** An archived, sandboxed, hardened Release-AppStore build compiled its Metal kernels, loaded Qwen3-4B-Instruct-2507 4-bit from the app-group container and ran a guided `SectionLabelTask`-shaped generation. Warm calls took 3.0 s each. There were no sandbox violations, and the hardened runtime needed **no** exception (no `allow-jit`, no `disable-library-validation`).
- **The shared store works without new provisioning.** Both flavours use the team-prefixed group `V6BM673U35.dev.ryandsilva.segue.models`. The Personal build wrote the model in, and the App Store build read the same files at the same container URL. The existing "Segue Mac App Store" profile has no App Groups capability, yet the manual-signing export and all 14 `verify-archive` checks passed. **Ryan does not need to regenerate any profile.** One check is still open: App Store Connect validation (`make validate`, Ryan's step under R46).
- **Cost:** the `.pkg` grows by 8.5 MB (14.8 to 23.2 MB) and the `.app` by 21 MB (22.0 to 43.0 MB). A Release archive takes about 2x as long (18 to 36-43 min on a loaded machine). Launch-to-window grows by about 0.1 s, but that measurement includes the probe loading the model during launch.
- **Things P3-3 must do differently from the CLI spike:** install Xcode's Metal Toolchain component, add Metal warning flags, call `LLMModelFactory.shared` directly, declare the DiskSpace required reason, and write its own tokenizer loader. Details are in section 5.

## 1. Setup

| | |
|---|---|
| Machine | MacBook Pro M1 Pro, 16 GB, macOS 26.6.2 (25G83) |
| Toolchain | Xcode 27.1 (27A9275), macOS 27.0 SDK, Tuist 4.212.0, **Metal Toolchain 27A266a** (downloaded component, see 5.1) |
| Packages | `mlx-swift-lm` 3.32.3 (`MLXLLM`, `MLXLMCommon`, `MLXGuidedGeneration`), `swift-transformers` 1.3.5 (`Tokenizers`). No `MLXHuggingFace` (R66) |
| Model | `mlx-community/Qwen3-4B-Instruct-2507-4bit` at revision `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`, placed by hand (section 7) |
| Load on the machine | Sibling workstreams ran builds and E2E at the same time (load average 5-30). Treat every timing as an upper bound |

The probe is a stub `Packages/SegueAI` linked by **both** app targets. At launch it calls `SegueAISpike.runIfRequested()` on a detached task. That function does the following:

1. Resolves `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` and writes a `seen-by-<bundle id>` marker.
2. When a `spike.request` file exists, it runs a GPU matmul smoke test, loads the model from `<group>/Library/Application Support/Models/<repo>/<revision>/`, and runs the label task three times. The task takes 6 blocks with exact-count, bounded-int JSON Schema output (`GrammarConstraint` + `GuidedGenerationLoop`), with `Memory.cacheLimit` set to 512 MB.
3. Logs each result field to the unified log under category `ai-spike`.

The agent shell cannot read or write app or group containers (macOS denies it with `EPERM`). So the Debug-Personal build copied the model in from the Debug-only E2E exception path `/private/tmp/segue-e2e/`. The copy was an APFS clone and took about 30 ms. Results were read with `/usr/bin/log show`.

## 2. Results per proof point

| # | Proof point | Result | Evidence |
|---|---|---|---|
| 1 | Dependencies through Tuist, stub linked by both targets | **PASS** | `Tuist/Package.swift` + `Packages/SegueAI`. Pins and licences in section 4 |
| 2 | Metal library lands in the bundle and kernels load at run time | **PASS** | Tuist turns Cmlx into a static framework plus a synthesized `mlx-swift_Cmlx` resource bundle that compiles the 10 `.metal` files. Result: `Segue.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib` (2.3 MB Release, 3.5 MB Debug). Cmlx finds it through `NSBundle` (`SWIFTPM_BUNDLE`). At run time `Device(gpu, 0)` matmul = 529536.0 (correct), the log shows "Metal Compiling Shader" for the JIT kernels, and the model ran |
| 3 | Sandboxed, hardened Release-AppStore archive runs a real guided generation | **PASS** | `make archive` from the worktree. The archived app (Apple Development, `flags=0x10000(runtime)`, sandbox) loaded the model in 1.2 s cold and 0.8 s warm. Label runs took 4.4 / 3.0 s, then 3.0 / 3.0 / 3.0 s on a second launch. Output was valid JSON with exactly 6 entries. **No** sandbox denials and no faults in the log. **No** hardened-runtime exception |
| 4 | App-group shared store, both flavours | **PASS (local), ASC validation open** | Debug-Personal (`dev.ryandsilva.segue.personal`, automatic signing) imported the model. The Release-AppStore build (`dev.ryandsilva.segue`) resolved the same `~/Library/Group Containers/V6BM673U35.dev.ryandsilva.segue.models`, listed the other flavour's `seen-by-` marker and ran on the same model files. The export, manually signed with "Segue Mac App Store" (no App Groups in the profile), succeeded. `verify-archive` check 4 passes with the new allowed set (9 keys), and all checks pass |
| 5 | Deltas | measured | Section 3 |
| 6 | Privacy manifest and notices diff | done | Section 4. One new required reason (DiskSpace); `verify-archive` check 9 caught it |
| 7 | Write-up | this doc | plus the sandbox line in `phase3-ai.md` |

**One anomaly.** In the first Release run, the third call took **1,054 s** instead of 3 s, with identical output. A second launch ran 3.0 / 3.0 / 3.0 s. The machine was under heavy contention at the time: sibling E2E and builds, 1.9 GB of swap in use and about 600k pageouts. The likely cause is GPU or memory starvation of a background, utility-QoS task, but this is not proven. P3-3 must guard against it (section 5.6).

**Mac App Store distribution signing.** A build signed with Apple Distribution cannot be launched locally (AMFI rejects it, as expected). So the runtime proof uses the Apple Development-signed Release-AppStore archive, which has the same configuration, entitlements, sandbox and hardened runtime. For the distribution-signed `.pkg` the proof is static: signed entitlements, embedded profile, and the export accepting them.

### 2.1 App group rules (checked at source)

- `com.apple.security.application-groups` accepts `group.<name>` (registered in the portal, iOS style) or **`<team id>.<name>`**. For the latter, Apple says: "You don't need to register app groups that use this format on the Apple Developer website" (developer.apple.com, BundleResources entitlement page).
- macOS 15+ group-container protection lets an app use a group container without a prompt when **any** of these holds: it is deployed through the Mac App Store; the group id is prefixed with the app's Team ID; or the group is authorised by an embedded profile (Apple release note, quoted in developer forums threads 756701 and 762639). The team-prefixed id satisfies the second rule for every build (Developer, TestFlight, App Store).
- `containerURL(forSecurityApplicationGroupIdentifier:)` always returns a URL on macOS. The app must check that the directory is accessible (the probe did).
- **Proposed id: `V6BM673U35.dev.ryandsilva.segue.models`.** Store path: `<group>/Library/Application Support/Models/<repo>/<revision>/`, as in spec 5.3.
- **Ryan's manual steps: none are needed for the profiles.** The only open item is to confirm that App Store Connect accepts the entitlement. When convenient, in Terminal.app: `cd ~/Desktop/Projects/setlist-p3a && make validate`. This validates the spike's existing 0.5 (1) archive and uploads nothing. Alternatively, defer the check to the first real `make validate` after P3-3 lands. If validation ever rejects it, the fallback is to add App Groups to the App ID and regenerate "Segue Mac App Store" (spec open question 8 covers the store fallback).

## 3. Deltas

Measured on the same machine, back to back where possible, with siblings running (load average in brackets). Baseline = commit `b874739` without SegueAI.

| Metric | Without SegueAI | With SegueAI | Delta |
|---|---|---|---|
| `Segue.pkg` (exported) | 14,757,807 B | 23,209,395 B | **+8.5 MB** |
| `Segue.app` (archive) | 22.0 MB | 43.0 MB | +21 MB |
| Main binary (stripped) | 10.8 MB | 30.3 MB | +19.6 MB |
| New resources | | `mlx-swift_Cmlx.bundle` 2.3 MB, `swift-transformers_Hub.bundle` 32 KB, `swift-crypto_Crypto.bundle` 8 KB | |
| New dylibs / frameworks embedded | | none (all static) | |
| `make archive` (always a full rebuild) | 1,091 s (load 5-8) | 2,582 s and 2,169 s (load 9-22) | **about 2x** |
| Clean Debug-Personal build | 965 s (load 5-15) | 616 s (load 15-30); an earlier run took 1,955 s at load 22 | inconclusive: contention dominates |
| Incremental Debug build after a SegueAI edit | | 7-8 s | |
| Launch to first window restored (Release-AppStore, warm) | 165 / 165 / 167 ms | 233 / 258 / 282 / 358 ms | about +0.1 s, **but** the probe was loading 2.3 GB of weights in parallel; linking alone adds no dyld work (everything is static) |
| Memory: model loaded, `cacheLimit` 512 MB | | phys_footprint 2.30 GB after load, 2.84-2.89 GB after 3 calls; MLX peak 2.78 GB; MLX cache 512 MB | matches the CLI spike (2.98 GB) |
| `make gate` | not run | not run | Running it on the spike would have collided with siblings' E2E on the same bundle ids and `/private/tmp/segue-e2e`, and the test budget allows `make gate` only at the end of a workstream. Expected delta: a cold-DerivedData gate pays the MLX compile once; a warm one is unchanged unless SegueAI changes |

The build-time numbers are noisy. A fair measurement needs a quiet machine, so P3-3 should take one when it lands the dependency. The archive doubling is consistent across runs: Cmlx compiles 212 C++/Metal units, and `MLXLMCommon`/`MLXLLM` are large WMO Swift modules.

## 4. Dependencies, licences, privacy

### 4.1 Pins (`Tuist/Package.resolved`, all new except as noted)

| Package | Version | Revision | Licence | Shipped? |
|---|---|---|---|---|
| ml-explore/mlx-swift-lm | 3.32.3 | 3b339ad6e3 | MIT | yes |
| ml-explore/mlx-swift | 0.32.3 | 19601207e9 | MIT | yes |
| huggingface/swift-transformers | 1.3.5 | 48473106a9 | Apache-2.0 | yes (`Tokenizers`, which pulls in `Hub`) |
| huggingface/swift-huggingface | 1.0.0 | c30143a461 | Apache-2.0 | yes (through `Hub`, unused at run time) |
| huggingface/swift-jinja | 2.5.2 | 1e4d0dc69f | Apache-2.0 | yes (chat templates) |
| apple/swift-crypto | 4.5.2 | da9d28d69e | Apache-2.0 | yes (through `Hub`) |
| apple/swift-asn1 | 1.7.3 | 3b6410f7de | Apache-2.0 | yes (through crypto) |
| apple/swift-collections | 1.7.3 | 35a1edcb8e | Apache-2.0 | yes |
| apple/swift-numerics | 1.1.1 | 0c0290ff6b | Apache-2.0 | yes |
| ibireme/yyjson | 0.12.0 | 8b4a38dc99 | MIT | yes |
| mattt/EventSource | 1.5.1 | 86b5096ac5 | MIT | yes (through swift-huggingface) |
| swiftlang/swift-syntax | 603.0.2 | 79e4b74a29 | Apache-2.0 | **no** (macro host for the unused `MLXHuggingFaceMacros`) |

Note: the CLI spike resolved swift-jinja 2.5.1; this resolve picked 2.5.2.

Vendored inside those packages (no pin of their own, but owed in the notices):

| Component | Where | Licence |
|---|---|---|
| MLX (C++) | mlx-swift `Source/Cmlx/mlx` | MIT |
| mlx-c | mlx-swift `Source/Cmlx/mlx-c` | MIT |
| metal-cpp | mlx-swift `Source/Cmlx/metal-cpp` | Apache-2.0 |
| {fmt} | mlx-swift `Source/Cmlx/fmt` | MIT |
| nlohmann/json | mlx-swift `Source/Cmlx/json` | MIT |
| XGrammar v0.1.30 (+ NOTICE file) | mlx-swift-lm `Libraries/MLXCXGrammar/xgrammar` | Apache-2.0 |
| DLPack (header) | XGrammar `3rdparty/dlpack` | Apache-2.0 |
| PicoJSON (header) | XGrammar `3rdparty/picojson` | BSD-2-Clause |
| Qwen3-4B-Instruct-2507 weights (downloaded, not bundled) | Qwen/Qwen3-4B-Instruct-2507 | Apache-2.0 |

**`make docs-check` rows.** `scripts/check-docs.sh` demands one `THIRD_PARTY_NOTICES.md` row per resolved pin, in the form `| <name> | <exact version> | <exact location URL> | <licence> | <licence text path> |`. That means all 12 rows above, including swift-syntax, because the check reads every pin and does not know which ones ship. The vendored rows and the model row are owed by spec section 12 but are not machine-checked. Every Apache-2.0 component needs its LICENSE text, and XGrammar its NOTICE, in the bundled notices and on the web `/acknowledgements` page.

### 4.2 Privacy manifest (required-reason APIs)

- **New: `NSPrivacyAccessedAPICategoryDiskSpace`.** `MLXLMCommon/ParoQuant/PreparedCheckpoint.swift` reads `volumeAvailableCapacityForImportantUsageKey`/`volumeAvailableCapacityKey`. `verify-archive` check 9 failed on the first archive until the app manifest declared it. Proposed reason **E174.1** (check that there is enough space before writing files), which also covers Segue's own free-space check before a download (spec 12). Added on the branch; P3-3 adds it on main with the downloader.
- FileTimestamp and UserDefaults symbols were already declared (3B52.1, CA92.1). The new code adds `_stat`/`_fstat` and `NSURLContentModificationDateKey` uses, which those declarations cover.
- Package manifests: only swift-crypto ships `PrivacyInfo.xcprivacy` files, and they are empty (no tracking, no API types). The others have none.
- **Linked but unused network code:** `Hub` and `swift-huggingface` (default endpoint `https://huggingface.co`, an `HF_TOKEN` message) are in the binary because `Tokenizers` depends on `Hub`. Nothing calls them; Segue's downloader (R66) is separate. This is worth a line in the App Review notes if asked, and a reason to prefer a future swift-transformers that splits Tokenizers from Hub.

## 5. What P3-3 must do differently from the CLI spike

1. **Metal Toolchain.** Xcode 27 ships the Metal compiler as a downloadable component. Without it the build fails with `cannot execute tool 'metal' due to missing Metal Toolchain`. Installed here with `xcodebuild -downloadComponent MetalToolchain` (839 MB, no admin needed). `make bootstrap` should check `xcodebuild -showComponent MetalToolchain` and install it, and the README toolchain line should mention it.
2. **Zero-warning gate.**
   - MLX's `.metal` kernels emit `-Wc++17-extensions` warnings, and Tuist's warning suppression does not reach the Metal compiler. A per-target setting does not reach the synthesized `mlx-swift_Cmlx` bundle target either, so the flags go into `PackageSettings.baseSettings`: `MTL_COMPILER_FLAGS = $(inherited) -Wno-c++17-extensions -Wno-c++20-extensions`. These are upstream's own flags.
   - `_NumericsShims` needs the same `-no_warning_for_no_symbols` libtool flag as sentry.
   - `SegueAI` must be in the first-party strict list. Otherwise Tuist's `-suppress-warnings` conflicts with the package's `treatAllWarnings(as: .error)`.
3. **Model loading.** `loadModelContainer(from:using:)` fails with `noModelFactoryAvailable` in the app. The registry finds `MLXLLM.TrampolineModelFactory` through `NSClassFromString`, and a statically linked, dead-stripped binary does not keep that class. Call `LLMModelFactory.shared.loadContainer(from:using:)` directly.
4. **Tokenizer loader.** Without `MLXHuggingFace`, write a `TokenizerLoader` that calls `AutoTokenizer.from(modelFolder:)` plus a 40-line bridge to `MLXLMCommon.Tokenizer`. Both are in the spike's `SegueAISpike.swift` and are copied from the macro expansion.
5. **Results are read from the unified log, not files.** Neither the agent shell nor Terminal can read the group container. The eval target (`segue-eval`, spec 4) runs outside the sandbox, so this affects only in-app diagnostics.
6. **Robustness.**
   - Run inference at `.userInitiated` (not `.utility`) while a review sheet waits.
   - Hold a `ProcessInfo` activity during the call.
   - Give every call a timeout that maps to `ProviderError.timeout` and falls through (R63). One 17-minute stall was seen under load (section 2).
7. **SwiftPM CLI tests.** `swift test` on `Packages/SegueAI` cannot build the metallib, so anything that runs MLX must go through xcodebuild or the eval target, and package tests must stay MLX-free (ScriptedProvider, as the spec already says).
8. **Free whitespace.** The guided output was `{\n  "blocks": [\n    {...` with pretty-print whitespace (the grammar allows it). This is the runaway risk from spike 3.2, so the no-free-whitespace grammar is still required.

## 6. The proven diff (for P3-3)

Branch `spike/p3a-mlx-in-app`, one commit on `b874739`. The hunks to carry over are below. Drop the probe (`SegueAISpike.swift` and the `SegueApp.swift` hook).

- `Tuist/Package.swift`:
  - add `.package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3")`, `.package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.5")` and `.package(path: "../Packages/SegueAI")`;
  - add `"SegueAI"` to the first-party strict list and `"_NumericsShims"` to the quiet-libtool list;
  - add `MTL_COMPILER_FLAGS` to the base settings (5.2).
- `Packages/SegueAI/Package.swift`: products `MLXLLM`, `MLXLMCommon`, `MLXGuidedGeneration`, `Tokenizers`, with the same exact pins and strict Swift settings.
- `Project.swift`: `.external(name: "SegueAI")` in `appTarget` (both flavours).
- `App/Segue.entitlements`, `App/SegueAppStore.entitlements` and `App/Segue-Debug.entitlements` each get the following, and the header comment in `SegueAppStore.entitlements` stays true:

  ```xml
  <key>com.apple.security.application-groups</key>
  <array>
      <string>V6BM673U35.dev.ryandsilva.segue.models</string>
  </array>
  ```

- `scripts/lib/verify-common.sh` `app_entitlements`: add `"com.apple.security.application-groups": ["V6BM673U35.dev.ryandsilva.segue.models"]`, plus the comment. This feeds both `verify-archive` check 4 and `verify-appstore`.
- `App/PrivacyInfo.xcprivacy`: `NSPrivacyAccessedAPICategoryDiskSpace` with `E174.1`.
- `THIRD_PARTY_NOTICES.md` and the licence texts: section 4.1.

## 7. Curated model pin (for P3-3's manifest)

From the Hub API (`/api/models/mlx-community/Qwen3-4B-Instruct-2507-4bit/revision/main?blobs=true`, 2026-10-19), with every file downloaded and re-hashed locally. LFS files match the Hub's SHA256, and the others match the Hub's git blob id.

- Repo `mlx-community/Qwen3-4B-Instruct-2507-4bit`
- Revision **`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`** (last modified 2026-01-02)
- Licence `apache-2.0`, not gated

| File | Size (B) | SHA256 |
|---|---|---|
| added_tokens.json | 707 | c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680 |
| chat_template.jinja | 4040 | 40c21f34cf67d8c760ef72f8ad3ae5afad514299d4b06e91dd9a8d705af7b541 |
| config.json | 938 | 574349e5a343236546fda55e4744a76e181f534182d7dc60ff1bad7e7a502849 |
| generation_config.json | 238 | 835fffe355c9438e7a25be099b3fccaa98350b83451f9fd2d99512e74f1ade48 |
| merges.txt | 1671853 | 8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5 |
| model.safetensors | 2263022417 | 2a73c6c248601ab904e035548abd8e6abb65ea27dcb5f342fb0a8910eb44173f |
| model.safetensors.index.json | 63964 | 388d811b8b7c2608dd04cce1bcb04a8bf715d19b42790894e6d3427ff429a777 |
| special_tokens_map.json | 613 | 76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd |
| tokenizer.json | 11422654 | aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4 |
| tokenizer_config.json | 5440 | 4397cc477eb6d79715ccd2000accd6b3531928f30029665832fa1b255f24d2b9 |
| vocab.json | 2776833 | ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910 |

Total: 2,278,969,697 B (2.28 GB). The Hub gives SHA256 only for the two LFS files (`model.safetensors`, `tokenizer.json`). For the rest, the manifest's SHA256 comes from this local hash of the pinned revision, which matched the Hub's git blob ids. `README.md` and `.gitattributes` are not needed. Which files the loader actually opens is for P3-3 to trim.

## 8. Part 2 status (R64 re-validation)

Waiting on Ryan's 10-20 pastes in `research/phase3-eval/pastes/` (empty except the README on 2026-10-19). Ready:

- `research/phase3-spikes/score.py` takes `--gold <json>` and `--hints <json>`, so it can score the gitignored `research/phase3-eval/gold.local.json`. It stays backwards compatible with the 20 spike fixtures.
- `fmspike dump <dir>` writes the hints, and `mlxspike`/`fmspike` already read any folder of `.txt` pastes.

Still to do when the pastes arrive:

- Build the gold data (from `.cho` files, or drafts for Ryan to confirm).
- Add the final design to `mlxspike`: a no-free-whitespace grammar and one retry with a whitespace bias on `incompleteOutput`.
- Run Qwen3-4B and FM, then report the aggregates.
