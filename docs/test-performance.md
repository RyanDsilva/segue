# Test and build performance

Where the time in `make check` goes, why, and what to cut. Written 2026-10-18 from read-only
evidence (no builds or tests were run for this analysis).

## Evidence used

- `.build/gate-phase2.log` (the `make check` in progress, started 00:18:21; stage times from
  the log's birth time, the xcresult bundle names, `Test Suite ... at` lines and
  `Build complete!` lines).
- The 10 retained `.build/results/*.xcresult` bundles, read with `xcresulttool get
  test-results summary|tests|activities`. The full E2E run is
  `20261017-235144-43860.xcresult` (41 tests, 1075 s wall, 1063 s of test time). Per-step
  activity timing was extracted for all 41 tests.
- `.build/DerivedData*/Logs/Build/LogStoreManifest.plist` (per-build start/stop times; the
  verify DerivedData still holds the last verify-appstore run).
- Earlier full runs kept in the session scratchpad: `check.log` (a full `make check` on
  2026-10-17, E2E 16:27:07 to 16:38:58, verify-appstore 16:38:58 to 16:41:21), `quick1.log`,
  `quick2.log`, `build1.log` (a 344-file Debug build in about 20 s).
- `gate-phase1.log` and `baseline-xcode27.log` were not present in `.build/` (already
  discarded), so the scratchpad logs above stand in for them.

Note: the suite now has 48 UI tests; the measured full run had 41. The 7 newer tests
(`SegueGigModeE2ETests` x4, `SegueCoreUXE2ETests+Window` x2, `SegueSetlistLibraryE2ETests`
x1) are projected from `check.log` and from their code.

## 1. Time breakdown of `make check`

Projected for the current 48-test suite, incremental build after a typical source change.

| Stage | Time | Share | Source |
|---|---|---|---|
| generate + lint + repo-check + tokens/icon/site checks | 0.5 min (28 s) | 2% | gate-phase2: 00:18:21 to first xcodebuild 00:18:49; Tuist alone 1.5 s, swiftformat 0.2 s, html-validate 0.5 s |
| build Personal (Debug-Personal) | 0.1 min no-op, up to 0.4 min after a core change | 0.3-1.5% | 2.2 s no-op today; 344 files in about 20 s (`build1.log`) |
| build AppStore (Debug-AppStore) | 0.2-0.5 min | 1-2% | 9.8 s for 132 files today; 207 files in `check.log` |
| swift test SegueCore | 0.35 min | 1.4% | build 1.2 s + 353 tests in 16.8 s |
| swift test SegueVendorServices | 0.15 min | 0.6% | build 2.9 s + 22 tests in 5.5 s |
| swift test SegueUI (swiftbuild) | 0.25 min | 1% | build 3.7 s + 121 tests in 10.0 s |
| **E2E (XCUITest, serial)** | **about 21.5 min** | **84%** | 1063 s measured for 41 tests + about 230 s for the 7 newer ones; 4 s xcodebuild overhead |
| **verify-appstore** | **2.4 min** | **9.5%** | Release-AppStore 50 s, Debug-AppStore 29 s, Release-Personal 49 s, plus checks |
| **Total** | **about 25.5 min** | | |

Everything except E2E and verify-appstore is under 1.5 minutes combined. Builds are not the
problem: Debug compiles are fast (about 17 files/s) and `make generate` does not force a
rebuild (the build right after it was a 2.2 s no-op).

### Duplicate compilation

Per SegueCore source change, `make check` compiles SegueCore (and its dependents) up to 8
times:

1. Xcode Debug-Personal (`.build/DerivedData`)
2. Xcode Debug-AppStore (`.build/DerivedData`; another configuration means another full set
   of package intermediates, GRDB and Sentry included)
3. SwiftPM `Packages/SegueCore/.build`
4. SwiftPM `Packages/SegueVendorServices/.build` (SegueCore again, plus Sentry from source)
5. SwiftPM `Packages/SegueUI/.build` with `--build-system swiftbuild` (SegueCore, GRDB, Tonic
   again)
6. verify Release-AppStore (`.build/DerivedData-verify`, WMO -O)
7. verify Debug-AppStore (`.build/DerivedData-verify`): **an exact duplicate of 2** (207 vs
   208 SwiftCompile tasks in `check.log`)
8. verify Release-Personal (WMO -O), built only to read its signed entitlements

The `xcodebuild test` step reuses build 1 (no recompile). In steady state the SwiftPM copies
cost seconds (incremental builds of 1-4 s); their real cost is cold builds (33 s for a fresh
SegueUI build) and 8.2 GB of disk across the four package `.build` dirs, plus 6.1 GB across
the two DerivedData dirs. `Packages/SeguePersonalModules/.build` (542 MB) is not used by any
make target.

### E2E by class

| Class | Tests | Time | Avg/test |
|---|---|---|---|
| SegueCoreUXE2ETests (+Window x2, projected) | 22 | 7.1 min | 19 s |
| SegueLiveE2ETests | 10 | 3.8 min | 23 s |
| SegueEditorE2ETests | 6 | 3.2 min | 32 s |
| SegueSetlistBuilderE2ETests | 1 | 1.8 min | 109 s |
| SegueGigModeE2ETests (projected) | 4 | about 1.7 min | about 25 s |
| SegueE2ETests | 2 | 1.6 min | 49 s |
| SegueSetlistLibraryE2ETests (`check.log`) | 1 | 1.5 min | 89 s |
| SegueSetlistGigLogE2ETests | 1 | 0.6 min | 37 s |
| LaunchSmokeTests | 1 | 0.2 min | 8-11 s |

### Slowest 15 E2E tests (measured run)

| s | Test |
|---|---|
| 108.9 | SegueSetlistBuilderE2ETests/testBuildSetlistFromTheLibrary |
| 93.2 | SegueEditorE2ETests/testEditorFlow |
| 88.9 | SegueSetlistLibraryE2ETests/testMetadataEditingAndFiltering (`check.log`) |
| 85.5 | SegueE2ETests/testSongToSetlistToLiveView |
| 42.0 | SegueCoreUXE2ETests/testHelpMenu (42-49 s in every run) |
| 40.2 | SegueLiveE2ETests/testFridayGig |
| 37.5 | SegueCoreUXE2ETests/testAddSelectedSongToSetlist (one 15.5 s "Friday" submenu click) |
| 36.9 | SegueSetlistGigLogE2ETests/testGigLogAndReorderReview |
| 31.2 | SegueLiveE2ETests/testRehearsalTimesSongsAndAutoScrollReachesTheEnd |
| 30.9 | SegueEditorE2ETests/testKeystrokeLatencyOn200LineSong |
| 29.5 | SegueLiveE2ETests/testZoomMemoryAndMinimumLyricSize |
| 28.8 | SegueLiveE2ETests/testPageTurnerCrossesSongs |
| 28.8 | SegueCoreUXE2ETests/testRestoresSectionAndSongAcrossLaunches |
| 27.7 | SegueCoreUXE2ETests/testExternalEditConflict |
| 27.6 | SegueCoreUXE2ETests/testSetlistBuilderUndoRedo |

### Where E2E time goes inside the tests

From the xcresult activity log of the 41-test run (1020 s of activity time):

| Kind | Time | Share | Notes |
|---|---|---|---|
| Synthesized input (click, type, key, drag) | 454 s | 44% | 676 actions. A plain click costs 0.6-0.7 s (event + wait for app idle). Menu item clicks cost 2.3-2.6 s each (22 of them, 57 s). |
| Waits for an element to (not) exist | 367 s | 36% | 305 waits, excluding launch window waits. **84% of them took 1.0-1.2 s and another 6% took 2.1-2.6 s.** |
| App launch + first window + terminate | 98 s | 10% | about 48 launches at about 2 s each |
| Element queries (`exists`, counts, finds) | 78 s | 8% | `descendants(matching: .any)` queries over the whole tree |
| Fixed sleeps | about 13 s | 1% | `Thread.sleep` in Live, Undo, Keys |
| Screenshots | 4 s | 0.4% | 93 attachments |

## 2. Root causes

1. **The 1-second polling quantum (biggest single cause).** `waitForExistence` is implemented
   as an `XCTNSPredicateExpectation` on `existsNoRetry` (visible in the activity log), and
   `XCTNSPredicateExpectation` re-evaluates about once per second. If the element is not
   there on the first check, the wait costs at least 1 s even when the UI updated 100 ms
   later. The histogram is unambiguous: 287 waits landed in 1.0-1.4 s, 19 in 2.1-2.6 s, and
   only 27 succeeded immediately. The repo's own helpers have the same problem: `wait {}`,
   `waitForStatus`, `waitForValue`, `waitForFile` (CoreUX, Editor, E2E) and
   `SetlistE2E.waitUntil` all use `XCTNSPredicateExpectation` (about 140 call sites). Only
   `SegueLiveE2ETests.waitFor` and `SegueGigModeE2ETests.waitFor` poll at 0.1 s.
   Estimated waste: 4.5-5.5 min per full run.
2. **Animations and app-idle waits.** `-SegueUITesting` changes nothing about animation
   (`UITesting.isActive` is read in only three views). Every synthesized event waits for the
   app to go idle, so SwiftUI transitions and AppKit menu and window animations are paid on
   every click; menu item clicks are about 1.7 s dearer than other clicks.
3. **A fresh app and a fresh library per test.** Every test creates a temp library, launches,
   waits for the window and terminates (about 2 s, plus the first-row wait). This is cheap
   per test (10% overall), and several tests relaunch on purpose (restore, crash resume,
   quit flushes), so it is a secondary cost, not the main one.
4. **Logic checks done through the UI.** Some E2E steps re-check what in-process tests
   already cover: `testHelpMenu` clicks 9 menu items (about 25 s) to prove URL wiring that
   `SegueLinksTests` checks for the URL table; `LaunchSmokeTests` and `testHelpMenu` both open
   Acknowledgements; `testAutosaveRealDebounce` and the undo tests overlap `AutosaveTests` and
   `EditorUndoTests` in SegueUI.
5. **Real-time waits.** `testUnconfirmedShortcutTimesOutUnticked` runs at
   `-SegueLiveTimeScale 3`, so it waits about 10 s of real time for a 30 s timeout;
   Live rehearsal uses 8.5 s of fixed sleeps; Undo sleeps 3 s for a 0.5 s debounce.
6. **Serial execution.** E2E is serial and must stay so on one desktop (see below). The
   three `swift test` runs and verify-appstore also run serially although they use separate
   build dirs and could overlap.
7. **Duplicate builds** (section 1): Debug-AppStore twice, Release-Personal built only for an
   entitlement read, three SwiftPM copies of SegueCore.
8. **Index-while-building is on** for CLI builds (`Index.noindex` is 101 MB in DerivedData and
   93 MB in DerivedData-verify) and SwiftPM's index store is on by default for debug builds on
   macOS. Nothing reads these indexes (Xcode the IDE uses its own DerivedData). Typical cost is
   10-20% of compile time on non-no-op builds.

Checked and not a problem:

- `swift test --parallel`: all package tests are Swift Testing (the XCTest pass reports 0
  tests), which already runs in parallel by default. `--parallel` only affects XCTest. The
  wall time is bound by single long tests: "quick search over 2000 tagged songs stays under
  50 ms" (13.9 s, mostly building the 2000-song library) and "random command sequences keep
  the show consistent" (10.3 s).
- `xcodebuild -parallel-testing-enabled` for UI tests: not safe here. On macOS the clones run
  on the same desktop and fight over key window and keyboard focus, which is exactly the
  failure `E2E.bringToFront` exists to prevent.
- `make generate` does not invalidate the build; `lint` and `tokens-check` run once even though
  both `check` and `repo-check` depend on them (make deduplicates).
- Debug settings are already right: Debug is `-Onone`, `singlefile`, `dwarf`; WMO and
  `dwarf-with-dsym` are Release only. No heavy-generic hot spots showed up.
- `-allowProvisioningUpdates` adds about 1-2 s per xcodebuild call; not worth touching.

## 3. Proposals, ranked

Savings are per full `make check` on the 48-test suite unless noted. Measure each one with a
before/after run of the affected classes (`make e2e-one`) before rolling it out.

### (A) Quick wins, no coverage loss

| # | Change | Files | Saves | Risk |
|---|---|---|---|---|
| A1 | One fast-poll wait for the whole suite: `E2E.waitUntil(timeout:_:)` polling every 0.1 s, plus `XCUIElement.appears(timeout:)` / `disappears(timeout:)` built on `exists`. Replace every `waitForExistence`, `waitForNonExistence` and `XCTNSPredicateExpectation`-based helper, and delete the per-class copies. | `UITests/E2ESupport.swift`, all `*Support.swift` helpers, mechanical edits in every `*E2ETests*.swift` | **4.5-5.5 min** | Low. Slightly more AX queries (each `exists` is 0.07-0.2 s). Prove on one class first. |
| A2 | Under `-SegueUITesting`, switch animations off: a root `.transaction { $0.disablesAnimations = true }`, `NSAnimationContext` duration 0 and window `animationBehavior = .none`, and launch with `-NSAutomaticWindowAnimationsEnabled NO`. | `Packages/SegueUI/Sources/SegueUI/App/UITesting.swift`, the root scene in `App/Sources`, `UITests/E2ESupport.swift` (`freshInstanceArguments`) | 1-2 min (uncertain; measure) | Low. Animations are never asserted. Debug-only, so verify-appstore's test-hook check still covers Release. |
| A3 | Replace fixed sleeps with waits on observable state (scroll position settled, sidecar or file written, save status), and run the GigMode timeout test at `-SegueLiveTimeScale 30`. | `SegueLiveE2ETests.swift` (lines 89, 182-191), `SegueCoreUXE2ETests+Undo.swift` (127, 135), `SegueLiveE2ETests+Keys.swift` (75, 94), `SegueGigModeE2ETests.swift` | 0.3-0.5 min | Low |
| A4 | Stop building Debug-AppStore twice: drop `build-appstore` from `check` (verify-appstore builds and checks Debug-AppStore anyway), keeping `make build-appstore` as a standalone target. | `Makefile` | 0.2-0.5 min (about 1 min cold) | None |
| A5 | No index store in CLI builds: pass `COMPILER_INDEX_STORE_ENABLE=NO` in `scripts/xcodebuild.sh` and `--disable-index-store` to every `swift test`. | `scripts/xcodebuild.sh`, `Makefile` | 0.1-0.5 min per build-heavy run; more on cold builds | None (Xcode the IDE keeps its own index) |
| A6 | Run the three `swift test` packages concurrently (they have separate `.build` dirs) and tag the two long perf/property tests `.tags(.slow)` so `make quick` skips them (`--skip-tags`/filter) while `check` runs them. | `Makefile`, the two test files in `Packages/SegueCore/Tests` | 0.3-0.5 min | Low. Perf-budget tests must not share the CPU with a build, so they run in `check` only. |
| A7 | Run verify-appstore's Release builds concurrently with the package tests, before E2E starts (never during E2E: `testKeystrokeLatencyOn200LineSong` measures latency). | `Makefile` (a `check` recipe or small `scripts/check.sh`) | 1.5-2 min | Medium: CPU contention could trip the SegueCore perf budgets, so pair with A6's tag and run the tagged tests after. |

A total: about **7-9 min** off `make check`.

### (B) Restructuring E2E

| # | Change | Files | Saves | Gives up |
|---|---|---|---|---|
| B1 | Move logic checks down to in-process SegueUI tests and keep one real-UI path per feature: in `testHelpMenu` keep the menu titles and one link click, check the rest of the link wiring in `SegueLinksTests`; drop the Acknowledgements repeat from `LaunchSmokeTests`; move `testAutosaveRealDebounce`, `testDeleteShortcutNeverFiresInText`, the numeric part of `testZoomMemoryAndMinimumLyricSize` and the undo-stack detail of the Undo tests into `AutosaveTests`, `EditorUndoTests`, `StageLayoutRenderTests`. | `UITests/SegueCoreUXE2ETests+Menus.swift`, `+Undo.swift`, `LaunchSmokeTests.swift`, `SegueLiveE2ETests.swift`; `Packages/SegueUI/Tests/SegueThemeTests/*` | 2-3 min | The real-UI wiring for those specific checks (the menu item to action binding, real keystrokes into the real text view). Conflicts with the integration-first preference: see open question 1. |
| B2 | Merge tests that share a seeded library and do not need a fresh process into scenario flows: Menus (`testHelpMenu` + `testKeyboardShortcutsWindow` + `testSetlistMenuShortcuts` + `testReopenMainWindow`), Library (import, show in Finder, delete and undo), editor gestures (`testPillGestures` + `testNashvilleNumberEntry` + `testDarkAppearance`). | `SegueCoreUXE2ETests*.swift`, `SegueEditorE2ETests.swift` | 1-1.5 min | Failure isolation: with `continueAfterFailure = false` the first failure hides the later steps, and `e2e-one` gets coarser. |
| B3 | Use the keyboard shortcut (or toolbar button) instead of a menu click where the menu is not what the test is about. Menu tests keep clicking menus. | `SegueCoreUXE2ETests*.swift`, `SegueSetlistBuilderE2ETests.swift` | 0.5 min | None, provided every menu item is still clicked once somewhere. |
| B4 | One app launch per class with an in-app reset hook (`-SegueUITesting` exposes a "reopen library at path, reset state" command). Tests that check launch, quit, restore or crash resume keep relaunching. | `App/Sources/LaunchOptions.swift`, `SegueUI/App/UITesting.swift`, every class `setUp` | 1-1.5 min | Each test no longer starts from a fresh process, so state can leak between tests (open windows, undo stacks, caches); a new test-only code path that verify-appstore must keep out of Release. Highest risk in this group; do it last, if at all. |

B total: about **4-6 min** on top of A.

### (C) Tiering

| # | Change | Files | Effect |
|---|---|---|---|
| C1 | New `make gate` for workstream gates: generate, lint, repo-check, generated-file checks, both builds, package tests, the E2E smoke set, plus the E2E classes mapped from the paths changed since the gate's base ref. A mapping file (`UITests/e2e-map.tsv`: path glob to classes, for example `Packages/SegueUI/Sources/SegueUI/Live/**` to `SegueLiveE2ETests SegueGigModeE2ETests`) drives it; any unmapped path runs the full suite. verify-appstore only when `Project.swift`, `Tuist/**`, `App/*.entitlements`, `App/Sources/LaunchOptions.swift`, `Packages/*/Package.swift`, `Packages/SeguePersonalModules/**` or `scripts/verify-*.sh` changed. | `Makefile`, `scripts/gate.sh` (new), `UITests/e2e-map.tsv` (new) | Typical gate 4-8 min instead of 25. Gives up: untouched areas are not re-run at every gate (a regression through shared code that the map misses surfaces at the next `make check`). |
| C2 | `make check` becomes the release gate: before `make archive`/`validate`, and once at the end of each phase. | `Makefile` help text, `docs/release/README.md` section 3 | Full coverage still runs before anything ships. |
| C3 | `make e2e-smoke` (`-only-testing` list): `LaunchSmokeTests`, `testSongToSetlistToLiveView`, `testEditorFlow`, `testFridayGig`, `testBuildSetlistFromTheLibrary`, `testAutosaveWritesWithoutSave`. | `Makefile` | About 6 min today, about 3.5 min after A. Covers the primary path: library to editor to setlist to live. |
| C4 | Run E2E in a local macOS VM so it stops holding the desktop (R180, [research](research/e2e-off-screen.md)). **Done:** `make e2e`, `e2e-smoke`, `gate` and `check` build on the host and test in a throwaway clone of a Tart golden VM (`scripts/e2e-run.sh`, `E2E_RUNNER=vm`, the default for those targets); `e2e-one` stays on the screen. `E2E_RUNNER=host` opts back, `E2E_RUNNER=lume` is the MIT escape hatch, `E2E_VM_SHARDS=2` splits a run over two guests when the Mac is otherwise idle. `make e2e-vm-golden` (re)creates the golden for the host's Xcode; a mismatch fails closed. About 45 s fixed overhead per run, test time about the host's. | `scripts/e2e-run.sh`, `scripts/e2e-vm.sh`, `scripts/e2e-vm-golden.sh`, `scripts/lib/e2e-*.sh`, `Makefile` | Ryan keeps the screen, pointer and keyboard while E2E runs; costs about 6 GB of RAM and 2 cores for the run. |

## 4. Targets

| Command | Now | After A | After A + B |
|---|---|---|---|
| `make quick` (incremental) | 0.7-1.7 min (`quick1.log` 42 s, `quick2.log` 99 s) | 0.5-1 min | 0.5-1 min |
| `make check` | about 25.5 min (E2E 21.5, verify 2.4) | about 16-18 min (E2E 14-15) | **about 11-13 min** (E2E 10-11, verify mostly overlapped) |
| `make gate` (C1, typical) | n/a | 5-8 min | 4-6 min |
| `make e2e-smoke` (C3) | about 6 min | about 3.5 min | about 3 min |

E2E stays about 85% of `make check` after all of this; going below about 10 minutes means
fewer UI tests (B1 taken further), which is a coverage decision, not a speed fix.

## 5. Open questions for Ryan

1. **B1 (moving checks to in-process tests):** acceptable for the listed logic checks, given
   the integration-first preference? Options: move all listed, move only the Help-menu and
   Acknowledgements duplicates, or move none.
2. **B4 (one launch per class):** worth its state-leak risk for about 1-1.5 min, or skip?
3. **A2 (animations off under `-SegueUITesting`):** acceptable that E2E no longer exercises
   animated transitions?
4. **C1/C2:** `make check` as the release and phase-end gate only, with `make gate` at
   workstream gates?
5. **verify-appstore Release-Personal build:** keep (49 s, proves the signed Release-Personal
   entitlements) or replace with a static check of `CODE_SIGN_ENTITLEMENTS` for that
   configuration plus `App/Segue.entitlements`, leaving the signed proof to `make archive`?
6. **C4 (E2E in a VM):** make it a research ticket?

## 6. Results (R58, implemented 2026-10-18)

Groups A, B and C are in (commits `e756b61` A; `3a3ccc0`, `bac4ff1`, `8b290c8`, `51a3ac0`
B; `5f577f5` C; waits fixed after the final runs in `49b5617` and `503d296`). Two items came out differently from the proposal; see 6.4.

### 6.1 Timings, before and after

Before: a fresh full `make e2e` on 2026-10-18 (48 tests, the suite as it was) and the
stage times of section 1. After: the final `make check` below (51 tests: the sibling Gig
Mode work added three) and the runs noted.

| Stage | Before | After | How |
|---|---|---|---|
| generate + lint + repo-check + generated-file checks | 0.5 min | about 0.3 min | unchanged |
| build Personal | 0.1-0.4 min | under 0.1 min (incremental) | no index store (A5) |
| build AppStore (Debug-AppStore) | 0.2-0.5 min | 0 (dropped) | verify-appstore builds it (A4) |
| package tests (3 packages) | 0.75 min serial | 0.3 min side by side | A6 |
| verify-appstore | 2.4 min | 0.3 min incremental, 1.2-1.3 min after a rebuild; beside the package tests | A7 (tests + verify side by side: 20 s incremental, 74-78 s rebuilt) |
| timing-budget package tests | (inside the above) | 0.15 min, alone | A6 |
| E2E (XCUITest) | 21.5 min (`make e2e` 21:33, tests 1277 s) | about 12.1 min (tests 694-711 s, 42 tests) | A1, A3, B |
| **`make check`** | **about 25.5 min** | **12:47 and 13:27 (two runs, see 6.5)** | |
| `make quick` | 0.7-1.7 min | about 0.5-0.8 min (package tests 31 s incl. budgets) | A5, A6 |
| `make test` | about 0.75 min | 0.5 min (31.6 s) | A6 |
| `make gate` (a Live change: Live class + smoke set) | n/a | 5:51 | C1 |
| `make e2e-smoke` | about 6 min | about 2.5 min (smoke part of the gate run) | C3 |

E2E by class, before (fresh baseline) -> after A -> after A + B:

| Class | Before | After A | After A + B |
|---|---|---|---|
| LaunchSmokeTests (1) | 7.7 s | 4.7 s | 3.7 s |
| SegueCoreUXE2ETests | 430 s (22 tests) | 232 s | 188 s (14 tests) |
| SegueE2ETests (2) | 99 s | 55 s | 55 s |
| SegueEditorE2ETests | 190 s (6) | 97 s | 94 s (5) |
| SegueGigModeE2ETests (sibling; 4 then 7) | 81 s | 117 s (7) | unchanged by this work |
| SegueLiveE2ETests (10) | 235 s | 144-150 s | 141 s |
| SegueSetlistBuilderE2ETests (1) | 108 s | 47.5 s | 47.5 s |
| SegueSetlistGigLogE2ETests (1) | 36 s | 20.7 s | 20.7 s |
| SegueSetlistLibraryE2ETests (1) | 91 s | 39 s | 39 s |
| **All** | **1277 s** | **762 s** | **694-711 s** |

A1 (fast polling) is nearly all of A's E2E gain. A2 (animations off) measured as noise:
CoreUX 220.5 s with animations vs 221.4 s without, Editor 97.4 vs 99.3, Builder 47.2 vs
47.5, so it was taken out again (6.4).

### 6.2 What changed

- A1: `E2E.waitUntil` / `E2E.expect` (0.05 s polls) and `appears`, `disappears`,
  `hasValue`, `reaches` on the elements and app replace every `waitForExistence`,
  `waitForNonExistence`, `XCUIApplication.wait(for:)` and `XCTNSPredicateExpectation`
  helper (except in the sibling-owned `SegueGigModeE2ETests.swift`, which still has its own
  0.1 s poll and a few `waitForExistence`). Lists that re-render while polled are read from
  one snapshot (`E2E.snapshots`), and `settles` waits for a sliding panel to stop.
- A3: the crash test waits for the scroll position in the show file instead of 2 s; the
  rehearsal waits on the scroll status ("Scrolling", "Scroll paused") with 0.5 s holds only
  for "nothing moves" checks; the page-turner loop waits for each press instead of 0.4 s.
  Kept: the two 1.5 s sleeps in `testRestoresSectionAndSongAcrossLaunches` (the restore
  write lands in the app's sandboxed defaults, which the sandboxed runner cannot read).
  Not done: `-SegueLiveTimeScale 30` for the Gig Mode timeout test (sibling-owned file).
- A4-A7: `make check` no longer builds Debug-AppStore twice; `COMPILER_INDEX_STORE_ENABLE=NO`
  and `--disable-index-store`; `scripts/parallel.sh` runs the three package test runs side
  by side and verify-appstore beside them; the timing-budget tests (`*PerformanceTests`,
  the 2,000-song search) run alone afterwards (`make test-perf`); `make quick` also skips
  the long property tests. DerivedData: the Personal build, every E2E target and the gate
  share `.build/DerivedData`; verify-appstore keeps `.build/DerivedData-verify` (its checks
  read that build graph, so sharing would be unsafe); each SwiftPM package keeps its own
  `.build` (SwiftPM scratch paths are per root package).
- B1/B2: see the mapping in 6.3.
- C: `make gate`, `make e2e-smoke`, `UITests/e2e-map.tsv`, `scripts/gate.sh`;
  `make check` is the release and phase-end gate (README, CONTRIBUTING, release README 3).

### 6.3 Coverage mapping (old test and assertion -> new location)

Counts: 5 E2E tests' assertions moved (wholly or in part) to 4 new in-process tests plus
one new test in `AutosaveTests`; 12 tests merged into 4 scenarios; 1 duplicate check
(Acknowledgements credits) merged into a scenario; everything else kept as it was. E2E
tests: 51 -> 42 (CoreUX 22 -> 14, Editor 6 -> 5).

| Old test: assertion | New location |
|---|---|
| CoreUX `testAutosaveRealDebounce`: nothing on disk right after typing; written within 5 s; not before 0.8 s | `AutosaveTests` `the shipped debounce writes after a one second pause in real time` (real clock, real app session, real file); E2E test removed |
| CoreUX `testHelpMenu`: What's New, Request a Feature, Privacy Policy, Terms of Use open their pages; Report a Problem opens a support mail | `HelpMenuTests` `each help link opens its page and report a problem mails support` (the menu now renders `HelpMenu.items`; URLs through `RecordingWorkspaceActions`, the URL table in `SegueLinksTests`) |
| CoreUX `testHelpMenu`: titles in order; Segue Help opens its page; Keyboard Shortcuts and Acknowledgements windows open; Export hidden; About panel | kept in `testMenus` (plus in process: `HelpMenuTests` titles, window items, hidden items) |
| CoreUX `testKeyboardShortcutsWindow`, `testSetlistMenuShortcuts`, `testReopenMainWindow`: all assertions | kept, merged into `testMenus` (the Shortcuts window now opens from the Help menu; Cmd-/ is still pressed in `testNewSurfacesInLightAppearance`) |
| `LaunchSmokeTests`: Acknowledgements credits Schibsted Grotesk, GRDB, Tonic and the OFL text | kept, moved into `testMenus` (the Acknowledgements step); removed 2026-10-18 with the window itself: `testMenus` now asserts About names no third-party software, and `AboutPanelTests` checks the licence texts still ship |
| CoreUX `testShowInFinder`, `testDeleteSongToTrashAndUndo`, `testImportFromMenu`, `testDeleteShortcutNeverFiresInText`: all assertions | kept, merged into `testLibraryFileActions` ("trash is empty" became "trash unchanged", the import's "4 in the trash" became "4 more") |
| CoreUX `testCleanEditorPicksUpExternalEdit`, `testExternalEditConflict`: all assertions | kept, merged into `testExternalEdits` |
| CoreUX `testSetlistBuilderUndoRedo`: Undo Rename, Undo Add, Redo Add, Redo Rename, each on disk | `UndoWalkTests` `builder add rename and remove undo one by one and redo in order` (also checks every action name); the E2E keeps the UI edits, Cmd-Z (Undo Remove), Shift-Cmd-Z and the external-edit check |
| CoreUX `testSongMetadataUndo`: Undo tag, Redo tag | `UndoWalkTests` `song tag and proficiency undo one by one and redo in order`; the E2E keeps the UI edits, Cmd-Z and Shift-Cmd-Z |
| Editor `testPillGestures`, `testNashvilleNumberEntry`: all assertions | kept, merged into `testVisualEditorGestures` |
| Live `testZoomMemoryAndMinimumLyricSize`: zoom kept per song across navigation, second column step and its memory, the indicator goes away, the long song at 30pt scrolls at the minimum | `LiveStageZoomTests` (real app model, stage, layout engine and stores; values read from the stage body's accessibility value as the E2E reads them); the E2E keeps the Settings stepper, fitted size >= 30, Cmd-= and C on the real stage |

### 6.4 Open questions: what was decided, and what is still open

1. B1: taken for the listed checks, except `testDeleteShortcutNeverFiresInText`, which stays
   an E2E check (merged): it is about the real key equivalent reaching the real text view,
   which no in-process test can reproduce.
2. **B4 (one app launch per class): not done; needs Ryan's call.** It was built (a Debug-only
   reset channel) and dropped on two platform facts found on the way: XCTest terminates
   the app under test at the end of every test once an `XCUIApplication` has launched or
   driven it (also when launched from class set-up or a test observer), and a sandboxed
   runner cannot pass launch arguments through Launch Services. The only way left is a
   Debug-only "launch arguments from a file" bootstrap that rewrites the app's argument
   domain at startup, for a gain of about 1 s per test (a launch now costs about 1.1 s):
   about 30-45 s per full run. Options: build that bootstrap, or skip B4.
3. A2: implemented and measured; no measurable effect (6.1), so removed rather than kept
   as a no-op. Options: leave it out (current), or keep it anyway for future animations.
4. Taken: `make check` is the release and phase-end gate, `make gate` the workstream gate.
5. Kept the Release-Personal build in verify-appstore (no coverage change); it now runs
   beside the package tests, so it costs little wall time.
6. C4 (E2E in a VM): recommended as a research ticket; not filed (GitHub changes need
   Ryan's go-ahead).

### 6.5 The final runs

- `make check` (13:27): green apart from one failure, `testFridayGig` reading the Shortcut
  log before the end Shortcut was written; fixed in `49b5617`.
- `make check` again (12:47): green apart from one failure, `testExternalEdits` writing the
  external edit while the editor's own save was still finishing (its bytes were on disk, the
  editor not yet clean); fixed in `503d296` by waiting for "Saved". Both were waits the old one-second
  polling had hidden.
- The re-run of that test could not start: the Mac stopped granting UI automation
  ("Timed out while enabling automation mode", AutomationModeUI waiting). The last fix is
  therefore not yet proven by a full `make check`; the next run needs Ryan at an unlocked
  Mac.
- `make gate` (a Live-only change since its base: Live class + smoke set, package tests,
  App Store build): 5:51. It found the two Live waits fixed in `51a3ac0`.
