# Research - running the XCUITest E2E suite off the owner's screen (2026-10-31)

Research ticket for `docs/test-performance.md` item C4: run the macOS XCUITest suite (`make gate`, `make e2e`, `make e2e-one`, `make e2e-smoke`) somewhere that does not take the pointer, keyboard focus and screen of Ryan's working Mac for about 30 minutes. **V** = VERIFIED (source given, or checked on this machine), **U** = UNVERIFIED (needs the spike in section 7, or no primary source was found). No tool was installed and no code was changed for this doc.

**Recommendation in one line:** primary path **Tart** (now FSL-1.1-ALv2, internal use allowed) with Cirrus's prebuilt `macos-tahoe-xcode:27.1` image as a golden VM: build on the host as today, then `test-without-building` inside a throwaway APFS clone per run, driven by a new `make e2e-vm`. Fallback **the MacBook Neo as an SSH remote runner** (a different failure domain from any VM). **Lume (MIT)** stays the licence escape hatch behind the same runner interface.

---

## 1. Facts about this repo and machine

| Fact | Where | Consequence |
|---|---|---|
| Host: M1 Pro, 10 cores, 16 GB, 639 GB free on `/`, macOS 26.6.2, Xcode 27.1 (27A9275). | `sysctl`, `df`, `xcodebuild -version` (V) | Room for a 140 GB sparse VM disk; RAM is the tight resource. |
| E2E runs as `scripts/xcodebuild.sh -scheme Segue-Personal -configuration Debug-Personal test`; `gate.sh` picks classes from `UITests/e2e-map.tsv`. Products land in `.build/DerivedData/Build/Products`, with `Segue-Personal_macosx27.0-arm64.xctestrun` next to `Debug-Personal/` (829 MB). | `Makefile:147-156`, `scripts/gate.sh`, `scripts/xcodebuild.sh` (V) | The `.xctestrun` + products pair is exactly what `test-without-building` needs; the class selection logic in `gate.sh` can be reused unchanged. |
| Debug-Personal is signed **Apple Development: Ryan Rony Dsilva (4HD4P2QLV8)**, team V6BM673U35, automatic signing, and `Segue.app/Contents` holds **no `embedded.provisionprofile`**. | `codesign -dvv`, bundle listing (V) | The built app should launch on any Mac, a VM included, without registering the VM as a device. Keys never need to enter the guest. |
| Debug entitlements: app sandbox, user-selected files, network client, Apple Events to Shortcuts Events, app group `V6BM673U35.dev.ryandsilva.segue.models`, temporary exception for `/private/tmp/segue-e2e/`. | `App/Segue-Debug.entitlements` (V) | The team-prefixed app group only works cleanly when the signing team matches, so keep dev signing rather than ad-hoc in the VM (U for the exact prompt behaviour). `/private/tmp` exists in the guest too. |
| Shortcuts are recorded by a fake runner (`-SegueShortcutLog`), never opened; no AI model is installed during E2E. | `UITests/SegueLiveE2ETests.swift:6`, `UITests/SegueAssistantE2ETests.swift:6` (V) | No Apple Events TCC grant and no MLX/Metal compute is needed in the guest. |
| Some tests drive the metronome and audio engine but assert no audio. | `UITests/SegueMetronomeE2ETests.swift`, `UITests/SegueFillE2ETests.swift:10` (V) | The guest needs an output device to exist; nobody needs to hear it. |
| The prompt that blocks unattended runs today is UI automation mode ("Timed out while enabling automation mode", AutomationModeUI). | `docs/test-performance.md` 6.5 (V) | That is Authorization Services, not TCC, and has a one-command fix (section 2.1). |
| The repo lives under `~/Desktop`, a TCC-protected folder. | path (V) | Anything the VM tool reads directly from the repo would raise a Desktop-access prompt, and a scheduled run would be silently blocked. Stage the products outside `~/Desktop`. |

---

## 2. The two macOS gates XCUITest needs (applies to every option)

### 2.1 Automation mode (the Touch ID / password "Enable UI Automation" prompt)

- The prompt "XCTest is trying to Enable UI Automation" comes from Authorization Services, not TCC; no PPPC profile affects it. Fix once per machine: `sudo /usr/bin/automationmodetool enable-automationmode-without-authentication`; check with `automationmodetool` (no arguments), the goal state being "DOES NOT REQUIRE user authentication to enable Automation Mode"; it persists across reboots. (V, [Corey Daley, "Two Gates Guard Unattended macOS UI Tests"](https://coreydaley.dev/posts/2026/06/unattended-xcuitest-self-hosted-mdm/); same command in [Bitrise docs](https://support.bitrise.io/en/articles/9676606-enabling-ui-automation-for-macos-tests) and the [Appium Mac2 driver README](https://github.com/appium/appium-mac2-driver).)
- It needs an admin password once (`sudo -n` is refused), and also DevToolsSecurity enabled and `_developer` group membership. (V, [Polymux PR #201](https://github.com/CarlvinceTan/Polymux/pull/201))
- Cirrus's base image runs it at build time through `scripts/automationmodetool.expect` ("Setting up machine to allow Automation Mode without requiring user authentication... succeeded"). (V, [`templates/base.pkr.hcl` line 144-147](https://github.com/cirruslabs/macos-image-templates/blob/main/templates/base.pkr.hcl) and [`scripts/automationmodetool.expect`](https://github.com/cirruslabs/macos-image-templates/blob/main/scripts/automationmodetool.expect))

### 2.2 TCC (privacy grants)

- XCUITest itself, once automation mode is on, needs no Accessibility grant in this suite (U in a VM; it is the case on the host today, where only the automation prompt appears).
- Sensitive PPPC payloads (Accessibility) are honoured only when delivered through MDM; a double-clicked `.mobileconfig` is ignored. So an "MDM-less profile" does **not** work for Accessibility. (V, Corey Daley above)
- `tccutil` can only **reset** grants, not add them (V, `man tccutil` on the host: `reset` is its only command).
- With SIP **off**, grants can be written straight into `TCC.db` with `sqlite3`. Cirrus's images do exactly that (`scripts/update-tcc-database.sh`, which also handles macOS 27 moving the user database into a ProtectedSystem container). (V, [script](https://github.com/cirruslabs/macos-image-templates/blob/main/scripts/update-tcc-database.sh))
- Cirrus's published images are built with `disable-sip.pkr.hcl` in the stack, so **SIP is off in the guest**. (V, [Tart discussion #1144](https://github.com/openai/tart/discussions/1144), maintainer: the official image is "the vanilla Tahoe template plus base.pkr.hcl and disable-sip.pkr.hcl"; [`disable-sip.pkr.hcl`](https://github.com/cirruslabs/macos-image-templates/blob/main/templates/disable-sip.pkr.hcl) runs `csrutil disable` from Recovery.) SIP off is acceptable in a disposable test guest; it must never be done on the host.

### 2.3 Session

- XCUITest needs the GUI (Aqua) launchd session; a plain `ssh` login is a "Background" session, so `ssh host xcodebuild test` can fail even with automation mode on. The working fix is a one-shot LaunchAgent in `gui/$UID` (Polymux's `gui-run.sh`). (V, [Polymux PR #201](https://github.com/CarlvinceTan/Polymux/pull/201))
- Tart's guest agent serves `tart exec` and is installed in Cirrus images as a global LaunchAgent (`/Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist`) plus a daemon. (V, `base.pkr.hcl`; [guest agent README](https://github.com/cirruslabs/tart-guest-agent/blob/main/README.md)) That `tart exec` commands therefore run in the Aqua session is **U** (the README does not say); spike step S1.4 checks it with `launchctl managername`.
- Auto-login on, screen lock off, screensaver idle 0, sleep off are all set by the vanilla Tahoe template (`autoLoginUser admin`, `/etc/kcpassword`, `sysadminctl -screenLock off`, `systemsetup -setsleep Off`). (V, [`vanilla-tahoe.pkr.hcl`](https://github.com/cirruslabs/macos-image-templates/blob/main/templates/vanilla-tahoe.pkr.hcl))

---

## 3. Local macOS VMs on Apple silicon (Virtualization.framework)

### 3.1 Licence and the two-guest limit

- macOS Tahoe's licence, section 2B(iii): "up to two (2) additional copies or instances ... within virtual operating system environments on each Apple-branded computer you own or control ... for purposes of: (a) software development; (b) testing during software development; ...". (V, [macOS Tahoe SLA PDF](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf), text extracted on this machine) Running the E2E suite is (b).
- The limit is also enforced: a third concurrent macOS guest fails with `VZErrorDomain` code 6, "The maximum supported number of active virtual machines has been reached". (V by consistent third-party reports: [Eclectic Light, 2022](https://eclecticlight.co/2022/08/04/virtualisation-on-apple-silicon-macs-8-how-apple-limits-vms/), [khronokernel, 2023](https://khronokernel.com/macos/2023/08/08/AS-VM.html); no Apple page names the code.) Two VMs are allowed; one is the plan, two only as an opt-in shard mode (section 5.5).

### 3.2 Candidates

| Tool | Licence (V) | Automation | Golden image | Per-run reset | Verdict |
|---|---|---|---|---|---|
| **Tart** 2.41.1 (2026-10-15), now `github.com/openai/tart` | **FSL-1.1-ALv2** since 2026-06-05 (commit "Relicense under FSL-1.1-ALv2 (#1238)"). Permitted Purpose includes "your internal use and access"; only a Competing Use (offering it as a substitute product) is barred; each release converts to Apache-2.0 on its second anniversary. ([LICENSE](https://github.com/openai/tart/blob/main/LICENSE)) | Full CLI: `clone`, `run --no-graphics`, `--dir name:path[:ro]`, `--no-audio`, `--vnc`, `exec` (guest agent), `ip`, `set --cpu --memory --display`, `delete`. ([`Run.swift`](https://github.com/openai/tart/blob/main/Sources/tart/Commands/Run.swift), [quick start](https://tart.run/quick-start/)) | **Prebuilt:** `ghcr.io/cirruslabs/macos-tahoe-xcode:27.1` exists (tags 26.x through 27.2; uploaded 2026-10-21; 69.1 GB compressed, 140 GB sparse disk). Also `macos-tahoe-base:latest` (26.4 GB, no Xcode). (V, ghcr registry API queried 2026-10-31) | `tart clone golden run-N` per run, delete after; no snapshots needed. | **Primary.** |
| **Lume** (trycua/cua `libs/lume`), nightly v0.6.2 2026-10-25 | **MIT** ([LICENSE.md](https://github.com/trycua/cua/blob/main/LICENSE.md)) | CLI plus a local HTTP API; `lume create --ipsw latest --unattended tahoe` builds a vanilla VM "with SSH and autologin ready"; `lume sip` toggles SIP via Recovery; has telemetry (`lume config telemetry disable`). ([README](https://github.com/trycua/cua/tree/main/libs/lume), [docs](https://cua.ai/docs/lume)). Clone and shared folders are documented topics but their flags were not read (U). | No Xcode image (trycua images are `macos-tahoe-cua:26.5.2`, an agent desktop, V registry). You install Xcode 27.1 yourself. | Clone per run (U). | **Licence escape hatch**, same flow, more image work. |
| **UTM** | Apache-2.0 (per C4, V) | `utmctl start --disposable`, `clone`, `ip-address`; `exec` and file push/pull "require the guest agent" ([scripting docs](https://docs.getutm.app/scripting/scripting/)). A guest agent for Apple-backend macOS guests was not found (U). | Build it yourself. | `--disposable` start. | Viable by hand, weak to script. |
| **VirtualBuddy** | BSD-2-Clause ([repo](https://github.com/insidegui/VirtualBuddy)) | GUI app; no CLI documented. Save/restore state; APFS duplicate as a "clean copy". | Build it yourself. | Manual. | Good for poking at a guest, not for `make`. |
| **macosvm** (s-u) | Not shown on the page (U) | CLI, runs headless unless `-g`; `--vol path,automount` VirtioFS; `--ephemeral` discards changes. ([repo](https://github.com/s-u/macosvm)) | Build it yourself. | `--ephemeral`. | Small and scriptable, thin ecosystem. |
| **Apple sample** "Running macOS in a virtual machine on Apple silicon" | Apple sample-code licence | A starting point, not a tool. | n/a | n/a | Reference only. |

Prior art for exactly this job (V): [chrisbanes/portico PR #96](https://github.com/chrisbanes/portico/pull/96) builds UI tests on the host, runs `test-without-building` in a fresh Tart VM from `macos-golden-gate-xcode:27`, copies the `.xcresult` to `.build/test-results/xcode-ui-vm/`, deletes the VM: "Full native UI suite in the Tart VM: 22 tests passed" after fixing two VM-only failures (a 10 s deadline too tight under VM timing, and a stale `LabeledContent` accessibility value on macOS 27). [joelmoss/workroom #274](https://github.com/joelmoss/workroom/issues/274) plans the same on a **16 GB, 10-core Mac**, concludes "can't host two ~8 GB guests next to Xcode and the dev app", one guest at a time, `--dir=products:<snapshot>:ro --dir=results:<host dir>`, keeps Apple Development signing from the host build. [novotnyllc/tart-xcode-runner](https://github.com/novotnyllc/tart-xcode-runner) (MIT) formalises golden image, clone per run, results export, watchdog timeout, keys never in the VM.

### 3.3 Per-question findings for Tart (the primary)

- **Automation mode, TCC, SIP, auto-login, screen lock:** all pre-done in the Cirrus image (section 2). The spike only confirms `automationmodetool` reports "DOES NOT REQUIRE". (V for the template, U for this exact tag until S1.)
- **Xcode in the guest:** the image ships it, run through `xcodebuild -runFirstLaunch`, plus simulator platforms (`-downloadAllPlatforms`) that inflate it; the guest needs no Metal Toolchain because nothing compiles there. (V, [`xcode.pkr.hcl`](https://github.com/cirruslabs/macos-image-templates/blob/main/templates/xcode.pkr.hcl)) Guest Xcode must match the host's 27.1 for `test-without-building`; tag `27.1` matches (V); build version equality is checked at run time.
- **Disk:** 69.1 GB download once, 140 GB sparse disk; a clone is copy-on-write and costs only what a run writes (U for the exact per-run growth, expected a few GB).
- **RAM/CPU on 16 GB while working:** give the guest 4 vCPU and 6 GB (`tart set`; defaults are 2 CPU / 4 GB, V quick start). Workroom chose 4 CPU / 8 GB on the same host class (V), but 8 GB plus Xcode plus the dev app on 16 GB swaps. The guest uses the app (no model), the runner and Finder; 6 GB is expected to be enough (U, S1.6 measures).
- **Build and run flow:** build on the host (unchanged `build-for-testing`, the warning check stays), stage the `.xctestrun` + `Debug-Personal/` outside `~/Desktop`, share read-only, copy into the guest's own disk, run there. Building inside the guest is rejected: it would need the signing identity in the guest (keys stay host-side), the Metal Toolchain, a second package cache and roughly double the CPU.
- **Shared folders:** VirtioFS under `/Volumes/My Shared Files/<name>` (V, quick start). Run the app from a local copy, not from the share: the share is a "network volume" and can raise a TCC prompt for the agent (V, discussion #1144) and LaunchServices/Services registration from a network volume is untested (U).
- **Headless:** `tart run --no-graphics`; the guest still has its virtual display, which XCUITest drives (U until S1; portico and tart-xcode-runner run this way). Set the guest display to 1920x1200 because the default is 1024x768 (V quick start) and the window tests assume room. `--vnc` lets Ryan watch a run when debugging.
- **Reset per run (fresh-state rule):** clone the powered-off golden image per run, delete it after; a trap plus a TTL sweep of `segue-e2e-run-*` at the start of each run catches killed runs.
- **Results and screenshots:** a second, writable `--dir results:<staging>/results` share; `xcodebuild -resultBundlePath "/Volumes/My Shared Files/results/run.xcresult"`; the host moves it into `.build/results` so `prune_results` and the capture scripts (`SEGUE_RESULT_BUNDLE`) keep working.
- **Signing:** host Apple Development signing, no profile embedded (V, section 1), so it runs in the guest; dev certificate chain is trusted on every macOS (V, standard Apple chain). Ad-hoc in a separate `DerivedData-vm` is the fallback only if the dev-signed runner will not launch (workroom's plan), but ad-hoc changes the code identity every build and may trip the team-prefixed app-group check (U).
- **Audio:** Tart passes guest audio to the host by default; `--no-audio` removes the device (V, `Run.swift`). Keep the device (the engine path stays exercised) and mute the guest output once in the golden image (`osascript -e 'set volume output muted true'`), so no metronome clicks come out of Ryan's speakers. (U that mute survives clones: it is per-user state on the golden disk, expected to.)
- **Sandbox and app-group containers:** created fresh inside each clone, which is the fresh-state rule for free; the test library root `/private/tmp/segue-e2e/` is guest-local.
- **Metal:** the paravirtual GPU supports Metal (V, Tart maintainer in [discussion #344](https://github.com/openai/tart/discussions/344)); SwiftUI rendering is fine. MLX is not exercised by E2E, so its VM reliability does not matter here.

---

## 4. Non-VM alternatives

| Option | Findings | Verdict |
|---|---|---|
| **MacBook Neo as a remote runner** (SSH, build copied over) | Needs Xcode 27.1 installed (same build as host), `automationmodetool enable-automationmode-without-authentication` once with Ryan's password, DevToolsSecurity, Remote Login, auto-login, screen lock off, lid open and awake (`caffeinate -dimsu` for the run: a closed lid with no external display means no display for XCUITest, U). Runs must go through a `gui/$UID` LaunchAgent, not plain ssh (V, Polymux). Products copied with `rsync`; dev-signed bundle with no profile runs there (V by the same reasoning as the VM). No snapshot reset: relies on the suite's own fresh-instance arguments plus deleting `/private/tmp/segue-e2e` and the app's containers before each run. 8 GB is plenty for the app plus runner. Bonus: real low-power hardware, the product's 8 GB target. Cost: the Neo is unusable during the run and its screen is taken. | **Fallback.** |
| **Second user with Fast User Switching** | No primary source on XCUITest in an off-console session. Reports say an off-console session stops receiving synthesised HID events after a switch ([sill #211](https://github.com/Saffsanity/sill/issues/211)), and event synthesis timeouts appear when two sessions drive one desktop ([unwired-dev #1498](https://github.com/unwired-dev/product/issues/1498)). Automation mode and the runner are per session. (U, expected not to work) | Rejected; a 10-minute check could confirm. |
| **Headless or virtual display** (dummy plug, `CGVirtualDisplay`) | Does not address the problem: XCUITest synthesises input in the one console session, so the pointer and keyboard focus are still taken even if the window sits on an invisible display. (U by test, follows from how XCUITest drives input) | Rejected. |
| **More in-process tests** | Already the B1 track in `docs/test-performance.md`; it shortens the suite but cannot remove it (E2E stays about 85% of `make check`, section 4 there). It composes with any runner. | Keep doing; not a substitute. |

---

## 5. Recommendation and setup plan

### 5.1 Primary: Tart golden VM, build on host, `test-without-building` per clone

```
make e2e-vm [TEST=Class[/test]]            # or E2E_RUNNER=vm make gate / e2e-smoke
  1. host: scripts/xcodebuild.sh ... build-for-testing        (same warning check)
  2. host: stage .xctestrun + Debug-Personal into ~/Library/Caches/segue-e2e-vm/<run>/products
  3. host: tart clone segue-e2e-golden segue-e2e-run-<run>
  4. host: tart run --no-graphics --dir products:<..>/products:ro --dir results:<..>/results  (background)
  5. host: wait (bounded, 120 s) for `tart exec <vm> true`
  6. guest: assert xcodebuild -version == host build, automationmodetool status
  7. guest: ditto "/Volumes/My Shared Files/products" ~/run
  8. guest: xcodebuild test-without-building -xctestrun ~/run/<file>.xctestrun
            -destination platform=macOS,arch=arm64 -resultBundlePath ".../results/run.xcresult"
            [-only-testing:SegueUITests/...]   (the same selection gate.sh computes)
  9. host: exit code from step 8 (host-observed), move xcresult into .build/results
 10. host: tart stop + tart delete (trap), sweep stale segue-e2e-run-* older than 6 h
```

Implementation notes for the build session (not done here):

- One `scripts/e2e-vm.sh` plus a runner choice (`E2E_RUNNER=host|vm|remote`, default host until the spike passes) so `gate.sh` and the Makefile targets call one entry point; the Lume and Neo adapters slot in behind the same choice.
- A lock directory so two runs never share the golden image; a watchdog timeout on step 8 (suite budget plus 50%).
- `scripts/e2e-vm-golden.sh` builds the golden image reproducibly from the pinned tag (section 5.3), so an Xcode bump is one command, and the run fails closed when the guest Xcode build differs from the host's.
- Pin Tart in `.mise.toml` (Ryan's version-manager rule) rather than Homebrew; the Homebrew tap is reported broken (V, portico) and has moved to `openai/tools` (V, `base.pkr.hcl` installs `openai/tools/tart-guest-agent`). Whether mise's `github:` backend handles the `tart.app` bundle (asset `tart.tar.gz`, binary at `tart.app/Contents/MacOS/tart`) is U; the binary must stay inside its signed bundle for the virtualization entitlement.

### 5.2 Ryan's manual steps (once)

1. **Approve the tool and licence** (open question 1).
2. **Install Tart** after the `.mise.toml` pin lands: in Terminal, `cd ~/Desktop/Projects/setlist && mise install`. If mise cannot handle the bundle: download `tart.tar.gz` for 2.41.1 from github.com/openai/tart/releases, check it against `tart_2.41.1_checksums.txt`, unpack to `~/.local/share/tart/`, add `tart.app/Contents/MacOS` to the project's mise `env.PATH`.
3. **Pull the image** (69 GB, about 1.5 h at 100 Mbit/s): `tart clone ghcr.io/cirruslabs/macos-tahoe-xcode:27.1 segue-e2e-golden`. Keep the Mac awake (System Settings > Battery > Options > "Prevent automatic sleeping on power adapter when the display is off" on, or run `caffeinate -i` in another tab).
4. **First boot with a window**, to check it by eye: `tart run segue-e2e-golden`. If a macOS dialog appears (Software Update, Siri, "Apple Account"), dismiss it (Later / Not Now). Log in is automatic as `admin` / `admin`.
5. **Run the golden provisioning script** (built in the implementation session; it runs over `tart exec`): sets 4 vCPU / 6 GB / 1920x1200, mutes the output, turns off Spotlight indexing (`sudo mdutil -a -i off`) and automatic updates, checks `automationmodetool`, `DevToolsSecurity -status`, `xcodebuild -version`, then shuts down. Nothing to click unless a prompt appears; if one does, click **Allow** in the VM window and tell the session what it said (it gets scripted next time).
6. **First run watched:** `make e2e-vm TEST=LaunchSmokeTests VM_VNC=1`, watch it in the Screen Sharing window that opens, close it after.
7. **Host prompts to expect:** none for System Settings if staging stays outside `~/Desktop`. If the terminal app asks "would like to find devices on your local network" (only if SSH to the VM IP is used), click **Allow**; `tart exec` avoids it.

### 5.3 Expected wall time and host impact (U until S1 measures)

| Run | Host today | In the VM (estimate) |
|---|---|---|
| Fixed overhead per run: clone, boot to login, copy 0.8 GB, teardown | 0 | 1.5-3 min |
| `make e2e-smoke` (6 tests) | about 3-6 min | about 5-9 min |
| Full suite (about 85 tests) | about 30 min | about 33-45 min |
| Two shards in two VMs (opt-in, Ryan away) | n/a | about 18-25 min |

Virtualization.framework runs guest code natively; the loss is 4 of 10 cores and paravirtual graphics, and most of an XCUITest run is waiting on the UI, so 1.0-1.4x is the expected band. The portico report shows timing-tight waits can fail only in the VM, so expect to fix a few waits once (the suite's own `E2E.waitUntil` budgets).

Host impact during a run: about 6 GB of RAM held by the guest for the whole run, up to 4 cores busy at peaks (lower on average), negligible disk. Ryan keeps the screen, pointer and keyboard. A host Xcode build during the run competes for CPU and can slow the guest's timing-sensitive tests: build first, then work.

### 5.4 Fallback: MacBook Neo remote runner

Same `E2E_RUNNER=remote` entry point: `rsync` the staged products to the Neo, run `xcodebuild test-without-building` through a `gui/$UID` one-shot LaunchAgent wrapper over SSH, `rsync` the `.xcresult` back. Manual steps: on the Neo, install Xcode 27.1 from the Mac App Store or developer.apple.com, open it once and accept the licence; in Terminal run `sudo automationmodetool enable-automationmode-without-authentication` and `sudo DevToolsSecurity -enable`; System Settings > General > Sharing > **Remote Login** on (allow only `ryan`); System Settings > Users & Groups > **Automatically log in as** `ryan`; System Settings > Lock Screen > "Require password after screen saver begins or display is turned off" **Never** and "Turn display off when inactive" **Never** while it is a runner; keep it on power with the lid open. Add the M1 Pro's SSH key to the Neo's `~/.ssh/authorized_keys`. Pick this if S1 fails in a way no VM fixes (for example XCUITest cannot drive a paravirtual display at all).

### 5.5 Lume as the licence escape hatch

If Tart's FSL terms or its new owner become a problem: `lume create --ipsw latest --unattended tahoe`, then the golden script installs Xcode 27.1 (needs Ryan's Apple Account in the guest once, or the `.xip` copied in), runs `automationmodetool`, and (optionally) `lume sip` to disable SIP for TCC writes. Disable Lume telemetry. Same `make e2e-vm` flow, different adapter.

---

## 6. Hosted options (reference only; every one needs a push, and Ryan commits locally without pushing)

| Service | Cost for this suite (V unless marked) | Notes |
|---|---|---|
| **GitHub Actions** macOS (private repo) | Included usage is now a dollar amount: **$12/month** on Free, **$18** on Pro; macOS 3/4-core M1 is **$0.062/min** (2-core Linux $0.006, so macOS burns about 10x; GitHub no longer states a multiplier). $12 is about 190 macOS minutes, about 5 full runs a month; past that a 30-40 min run is about $1.90-2.50. ([billing docs](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)) | Hosted runners can run `sudo automationmodetool ...` (V, [creative-apps PR #189](https://github.com/qbtrix/creative-apps/pull/189)). Xcode 27.1 on the runner image: U. Conflicts with "CI stays lightweight". |
| **Xcode Cloud** | **25 compute hours/month included** with the paid membership; no rollover; 100 h $49.99/month and up. ([overview](https://developer.apple.com/xcode-cloud/), [get started](https://developer.apple.com/xcode-cloud/get-started)) About 30-35 full runs a month. | Supports macOS app workflows and "automated UI tests" generally; that its test action runs **macOS** XCUITest for this scheme was not confirmed in Apple's docs (U). Source goes to Apple's builders. |
| **Codemagic** | Individuals: **500 free macOS M2 minutes/month**, 1 concurrent build, then **$0.095/min**, 120 min build limit. ([pricing](https://codemagic.io/pricing/)) | Hosted service, needs Ryan's OK. |
| **Cirrus CI** | Shut down **2026-06-01** after OpenAI acquired Cirrus Labs; Cirrus Runners ($150/month per runner) takes no new customers. ([report](https://aiforautomation.io/news/2026-04-12-cirrus-labs-joins-openai-tart-ci-shutdown), [Cirrus Runners](https://cirrus-runners.app/)) | Not available. |
| **MacStadium** | Dedicated M2 Mac mini, 8 GB, 256 GB: **$109/month**; Orka by quote. ([pricing](https://www.macstadium.com/pricing)) | A remote Mac Ryan would have to administer; strictly worse than the Neo. |

---

## 7. Spike S1 (first step of the build session, about 2 h after the pull)

1. `tart clone` the 27.1 image; boot with `--no-graphics`.
2. `automationmodetool` says "DOES NOT REQUIRE"; `DevToolsSecurity -status` enabled.
3. `xcodebuild -version` prints 27.1 / 27A9275.
4. `tart exec <vm> launchctl managername` prints `Aqua` (else switch to the LaunchAgent wrapper).
5. Run `LaunchSmokeTests`, then `make e2e-smoke`, then the full suite, from host-built products; record wall times against the host.
6. Record guest memory pressure and host free memory during the full run (`memory_pressure`, Activity Monitor) at 6 GB; drop to 5 GB or raise to 7 GB from that.
7. Check the metronome tests pass with the guest muted, and with `--no-audio` (does the engine cope with no device? a real-world case worth knowing).
8. Check Services, Finder and Quick Look classes (`SegueServicesE2ETests`, `SegueFinderE2ETests`) with the app run from `~/run`.
9. Fix any VM-only wait failures as real flakiness fixes (they will also bite on a loaded host).

---

## 8. Open questions (with recommendations)

1. **Tart under FSL-1.1-ALv2:** it is no longer "personal use only" (C4's note is out of date): internal use is permitted, it is not OSI open source, each release becomes Apache-2.0 two years later, and the project now sits under OpenAI. The tart.run licensing page still shows the old Fair Source tiers, so the LICENSE in the installed release is the one that counts. **Recommend:** adopt Tart, pin the version, keep Lume (MIT) as the named escape hatch.
2. **Golden image source:** Cirrus prebuilt `macos-tahoe-xcode:27.1` (69 GB, SIP off, automation mode and TCC pre-done) or self-built from `macos-tahoe-base` plus Xcode via `xcodes` (smaller, needs Apple Account sign-in in the guest, more script). **Recommend:** prebuilt.
3. **Default runner:** should `make gate` and `make e2e-smoke` use the VM by default once S1 passes, with `E2E_RUNNER=host` to opt back? **Recommend:** yes for `gate`, `e2e`, `e2e-smoke`; `e2e-one` stays on the host by default (fast debug loop, watch it happen), `E2E_RUNNER=vm` available.
4. **VM size:** 4 vCPU / 6 GB? **Recommend:** yes, tuned by S1.6.
5. **Audio in the guest:** muted device or `--no-audio`? **Recommend:** muted device for normal runs; one S1 check with no device.
6. **Two shards in two VMs:** offer `E2E_VM_SHARDS=2` (about 12 GB of guests) for when Ryan is away? **Recommend:** yes, opt-in only, never the default.
7. **Scheduled runs:** a nightly full suite in the VM on `main` from launchd, with missed runs re-firing on wake and a notification on failure? **Recommend:** yes, after S1; staging outside `~/Desktop` is what makes this possible.
8. **Xcode bump policy:** fail closed when guest and host Xcode builds differ, with the message naming the golden rebuild command. **Recommend:** yes (tag 27.2 is already published).
9. **Neo fallback:** OK to turn the Neo into a runner (auto-login, no screen lock) if S1 fails? **Recommend:** only on S1 failure, and only for the duration of runs it is plugged in at the desk.
10. **Phase 9 iCloud sync and E2E:** adding iCloud entitlements will embed a provisioning profile that lists devices, which the VM (and maybe the Neo) is not in. **Recommend:** keep E2E on the in-memory sync fake (the Phase 9 spec already plans a `SyncPort` fake) so the E2E build needs no iCloud profile; decide this in the Phase 9 spec, not here.
11. **Hosted fallback:** none is recommended; Xcode Cloud's included 25 h is the only free-to-Ryan option and needs pushes plus confirmation that macOS UI tests run there. **Recommend:** do not adopt; revisit only if the local paths both fail.
12. **Ticket:** file the S1 spike plus the `make e2e-vm` build as one implementation ticket linked to C4? **Recommend:** yes (needs Ryan's go-ahead for GitHub changes).
