# 09 - Confirming that a Gig Mode Shortcut actually ran

Date: 2026-10-17. Scope: R18 ("A checklist row ticks only when its Shortcut actually ran successfully", `docs/release/decisions.md:38`) and WS1 spec 4.8d / Q1 (`docs/release/specs/WS1-release-pipeline.md:258-271, 364`). Question: how can a sandboxed Mac App Store app run a user's Shortcut and truthfully learn whether it succeeded, and is the reported macOS 26.5 x-callback-url regression real?

Legend: **UNVERIFIED** = not confirmed against a primary source or a local probe in this session. `SegueUI/` is short for `Packages/SegueUI/Sources/SegueUI/`.

---

## 0. Summary

- **The x-callback regression is real as a reported, dated, developer-attributed bug tied to a named Apple security fix.** Greg Pierce (Drafts developer) reported on 2026-05-15 that since iOS 26.5 / macOS 26.5 (and the 15.7.7 / 14.8.7 security updates) `shortcuts://x-callback-url/run-shortcut` runs the shortcut but always calls `x-error` with `errorCode=4, errorDomain=WFOutOfProcessWorkflowControllerErrorDomain`, filed as FB22785648 and linked to CVE-2026-28993. Apple's macOS 26.5 security notes confirm a Shortcuts fix CVE-2026-28993 "addressed by adding an additional prompt for user consent". **No source found says 26.5.2, 26.6.x, 26.7.x or macOS 27 (Golden Gate) fixed it**; the thread has no post after 2026-05-29. Fix status on 26.6.2 (this Mac) and 27: **UNVERIFIED**. I could not probe locally: this Mac's Shortcuts library is empty (section 1.3).
- **Recommendation:** run the Shortcut through **Shortcuts Events via Apple events** using the permanent `com.apple.security.scripting-targets` entitlement for the access group `com.apple.shortcuts.run`. That access group is declared in Shortcuts Events' own scripting dictionary on this Mac (verified, section 2.4), so no temporary exception is needed. The `run` command is synchronous and returns the result or throws, which gives a real succeeded / failed answer with no user setup beyond one Automation consent prompt. Add a **Segue Focus filter** (`SetFocusFilterIntent`) as an optional outcome check that the Gig Focus actually turned on, and keep a manual "Done" as the last fallback. x-callback-url is not usable as the success signal while the regression is unresolved.
- Before building, run the 15-minute probe in section 4 on 26.6.2 (and 27 if available). It needs Ryan to create one Shortcut by hand.

---

## 1. Is the x-callback-url x-error regression real?

### 1.1 Primary report

Drafts Community, "Problems running Shortcuts on latest OS (26.5 and other) updates", https://forums.getdrafts.com/t/problems-running-shortcuts-on-latest-os-26-5-and-other-updates/16754 (read via the forum's JSON API, `https://forums.getdrafts.com/t/16754.json`, 8 posts, last 2026-05-29):

- 2026-05-15, `agiletortoise` (Greg Pierce, Drafts' developer): "In the latest round of security updates to iOS and macOS, Apple has broken the ability to call Shortcuts and get results from other apps ... any other apps or automations that call shortcuts using its shortcuts://run-shortcut URL scheme with x-callback-url x-success parameters. Apple Folks: See FB22785648. It looks like this change is part of the latest round of security patches in iOS 26.5/18.7.9 and macOS 26.5/15.7.7/14.8.7. It is likely part of changes to address CVE-2026-28993." Behaviour: the shortcut still runs, x-success is never called, x-error is always called with `errorCode=4`, `errorDomain=WFOutOfProcessWorkflowControllerErrorDomain`. Workaround: do not wait for a response.
- 2026-05-15, `P-D`: a working workflow "stopped working" right after updating to macOS Tahoe 26.5 (25F71). Independent reproduction on macOS.
- 2026-05-29, `agiletortoise`: with "Wait for response" off, the after-success steps "will always run, because there's no way to know if your Shortcuts completed successfully." This is exactly the R18 problem.
- 2026-05-29, `Hexperimental`: "If the shortcut has a 'return' action, even empty or 'do nothing', will continue to fail regardless of the 'wait for response'." Suggests the failure path is tied to returning output. Whether a shortcut with no output still gets x-success: **UNVERIFIED**.

### 1.2 Apple sources

- macOS Tahoe 26.5 security notes, https://support.apple.com/en-us/127115 : "Shortcuts. Impact: An app may be able to access user-sensitive data. Description: This issue was addressed by adding an additional prompt for user consent. CVE-2026-28993: Doron Assness." That the x-callback change is this fix is Pierce's inference, not Apple's statement (**UNVERIFIED** link).
- Security notes after 26.5 (fetched and grepped for Shortcuts entries): 26.5.2 https://support.apple.com/en-us/127595 (none), 26.6 https://support.apple.com/en-us/128067 (none), 26.6.1 https://support.apple.com/en-us/148170 (none), 26.6.2 https://support.apple.com/en-us/148281 (none), 26.7 https://support.apple.com/en-us/149042 (acknowledgement only), 26.7.1 https://support.apple.com/en-us/149228 (none), macOS Golden Gate 27 https://support.apple.com/en-us/149035 (CVE-2026-84600, "A malicious shortcut may be able to send messages without user confirmation", unrelated). Release index: https://support.apple.com/en-us/100100 . Security notes do not list functional bug fixes, so absence there proves nothing either way.
- Apple's documented contract (unchanged): `x-success` "opens when the interaction is successful (such as after a shortcut finishes running)", `x-error` gets `errorMessage`. https://support.apple.com/guide/shortcuts-mac/use-x-callback-url-apdcd7f20a6f/mac
- FB22785648 is not public; web search finds no copy. No Apple Developer Forums thread on this specific regression was found.

### 1.3 Local observation (this Mac, macOS 26.6.2, build 25G83)

Observed, not faked:

- `shortcuts list` prints nothing (exit 0), both from the agent shell and outside its sandbox. `osascript -e 'tell application "Shortcuts Events" to get name of every shortcut'` also returns an empty list. **This Mac has no Shortcuts in its library** (or none synced), so "Segue Focus Probe" does not exist.
- `shortcuts run "Segue Focus Probe"` -> `Error: The operation couldn't be completed. Couldn't find shortcut`, exit 1. Same for `"Gig Mode On"`.
- `osascript -e 'tell application "Shortcuts Events" to run shortcut "Segue Focus Probe"'` -> `execution error: Shortcuts Events got an error: Can't get shortcut "Segue Focus Probe". (-1728)`, exit 1. So the Apple-events path reports a missing shortcut as an error.
- I did not open any `shortcuts://x-callback-url/...` URL: without an existing shortcut it would only exercise the "not found" path, and it pops UI on Ryan's Mac while sibling agents run E2E. **The regression is not confirmed or refuted on 26.6.2.** Section 4 is the probe that settles it.

Unrelated note seen in the unified log while probing: some process launched `shortcuts` runs every ~6 s around 19:23 (likely sibling E2E work). Not investigated.

---

## 2. Mechanisms available to a sandboxed MAS app

Current code: `SegueUI/Live/ShortcutRunner.swift` opens `shortcuts://run-shortcut?name=` via `NSWorkspace.open` and reports only hand-over; `SegueUI/App/AppModel+Shows.swift:375-380` maps hand-over to `.ran(name)`; `SegueUI/Live/PreShowChecklistView.swift:171` then shows "“name” ran." which overstates what is known (WS1 4.8d already plans `.requested`). Entitlements today (`App/Segue.entitlements`): app-sandbox, user-selected read-write, app-scope bookmarks only.

### 2.1 x-callback-url (x-success / x-error / x-cancel)

- How: open `shortcuts://x-callback-url/run-shortcut?name=..&x-success=segue://..&x-error=..&x-cancel=..`, register a `segue` URL scheme, handle in `.onOpenURL`.
- Entitlements: none. Review: none.
- Truthfulness: on 26.5+ (and possibly later) x-error code 4 fires on success, so x-error cannot mean "failed". A received x-success would still be a true positive. Also, x-success callbacks bring Segue (and may bring Shortcuts) to the front, which is bad mid-show; `LiveFocus` already re-asserts the key window for this reason.
- Verdict: not usable as the R18 signal unless the probe shows it fixed. If kept at all, map `x-success` -> ran, `x-error` with `errorCode=4` -> unknown, other `x-error` -> failed, `x-cancel` -> failed (cancelled), no callback in N s -> unknown.

### 2.2 NSUserUnixTask / NSUserScriptTask running `/usr/bin/shortcuts`

- Apple: `NSUserUnixTask` "is intended to execute user-supplied scripts, and will execute them outside of the application's sandbox ... If the application is sandboxed, then the script must be in the applicationScriptsDirectory folder. A sandboxed application may read from, but not write to, this folder." https://developer.apple.com/documentation/foundation/nsuserunixtask ; folder is `~/Library/Application Scripts/<code-signing-id>` https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/applicationscriptsdirectory
- How: ship a two-line script (`exec /usr/bin/shortcuts run "$1"`); the user installs it, usually by Segue presenting an `NSSavePanel` pre-pointed at that folder (user-selected write). The task's completion handler gives the exit status; `shortcuts run` exits 1 on "Couldn't find shortcut" (observed). Exit status on an action that fails mid-shortcut: **UNVERIFIED**.
- Entitlements: none beyond sandbox. Review: this is Apple's sanctioned design for user scripts; low risk.
- Cost: an extra install step that is easy to get wrong, and invisible breakage if the user deletes the script. Truthful once installed.

### 2.3 `Process` launching `/usr/bin/shortcuts` directly

- Probe run here: a Swift CLI ad-hoc signed with only `com.apple.security.app-sandbox` (container `dev.ryandsilva.segueshortcutprobe`, `APP_SANDBOX_CONTAINER_ID` set) launched `/usr/bin/shortcuts list` (exit 0, empty, same as unsandboxed) and `/usr/bin/shortcuts run "Segue Focus Probe"` (exit 1, "Couldn't find shortcut", same as unsandboxed). No kernel sandbox denial was logged for the `shortcuts` child. The child inherits the sandbox but the work happens out of process (`siriactionsd`, `BackgroundShortcutRunner`) over XPC, which plausibly explains why it is not blocked.
- Not proven: that a sandboxed child can see and run a real shortcut (the library is empty, so "empty list" and "not found" cannot distinguish "sandbox hides it" from "nothing there"). **UNVERIFIED** until section 4.
- Review: executing a system binary is not downloading code (2.5.2), but it is undocumented behaviour of a CLI with private entitlements (`/usr/bin/shortcuts` carries `com.apple.private.*` keys) and could break in any update. App Review acceptance: **UNVERIFIED**. Guidelines: https://developer.apple.com/app-store/review/guidelines/ (2.4.5, 2.5.1, 2.5.2).
- Verdict: works as a fallback probe target, weak as a shipping mechanism.

### 2.4 Apple events to Shortcuts Events (scripting-targets)

- Verified on this Mac: `/System/Library/CoreServices/Shortcuts Events.app` (bundle id `com.apple.shortcuts.events`) ships `Shortcuts.sdef` with access groups `com.apple.shortcuts.run` (read shortcuts, `run` command) and `com.apple.shortcuts.organize`. The `run` command: "Run a shortcut. To run a shortcut in the background, without opening the Shortcuts app, tell 'Shortcuts Events' instead of 'Shortcuts'." It has `with input` and returns `the result of the shortcut`. Missing shortcut -> AppleScript error -1728 (observed).
- Entitlements: `com.apple.security.scripting-targets` = `{ "com.apple.shortcuts.events": ["com.apple.shortcuts.run"] }` plus, under the hardened runtime, `com.apple.security.automation.apple-events` and `NSAppleEventsUsageDescription`. Apple QA1888 "Sandboxing and Automation in OS X" says scripting-targets is the preferred way for sandboxed apps to script apps that publish access groups: https://developer.apple.com/library/content/qa/qa1888/_index.html ; Apple Events entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events . Because the access group exists, no `temporary-exception.apple-events` is needed (temporary exceptions are what App Review pushes back on: https://developer.apple.com/library/mac/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html ).
- User cost: one TCC prompt "Segue wants to control Shortcuts Events" (first run; deny is reportable as "failed: not allowed"). Do it from Settings > Live "Test" so it never first appears mid-show.
- Truthfulness: `run` blocks until the shortcut finishes and either returns or throws, so success and failure are both observed directly. Whether an action failing inside the shortcut surfaces as an Apple-event error (versus a normal return): **UNVERIFIED**. Whether CVE-2026-28993's "additional prompt for user consent" also applies to this path: **UNVERIFIED**. Whether the scripting-targets entitlement is honoured for Shortcuts Events from a real sandboxed app (vs. the access group being declared but not enforced/allowed): **UNVERIFIED**, section 4 probe.
- Implementation note: send via `NSAppleEventDescriptor`/`AESendMessage` or ScriptingBridge on a background queue with a timeout (NSAppleScript is main-thread only), so a hung shortcut cannot freeze the show UI.
- Review: scripting-targets with an Apple-declared access group is the documented MAS path. App Review acceptance for this specific target: **UNVERIFIED** (no rejection or approval report found either way).

### 2.5 App Intent in reverse ("Confirm Gig Mode in Segue")

- How: Segue ships an `AppIntent` (`openAppWhenRun = false`) the user appends as the last action of their Gig Mode On / Off Shortcut. It marks the pending checklist row confirmed. Optionally a parameter (`on` / `off`) and a run token are unnecessary: Segue only accepts it while a start/end request is pending.
- Entitlements: none. Review: standard. Truthful by construction: the action only runs if every earlier action ran without stopping the shortcut.
- Cost: one more setup step; existing Shortcuts never auto-tick; Shortcuts may open Segue if it is not running (it is, during a show). Needs App Intents in the app target.

### 2.6 Checking the Focus outcome directly

- `INFocusStatusCenter` exists on macOS 12+ (https://developer.apple.com/documentation/intents/infocusstatuscenter), needs `NSFocusStatusUsageDescription` (https://developer.apple.com/documentation/bundleresources/information-property-list/nsfocusstatususagedescription) and a user permission prompt. It needs the **Communication Notifications** capability (`com.apple.developer.usernotifications.communication`): without it macOS returns `DNDErrorDomain Code=1004: App is missing Communication Notifications entitlement` (Home Assistant issue on macOS 27, 2026-09-25: https://github.com/home-assistant/iOS/issues/5904 ; capability described at https://developer.apple.com/documentation/usernotifications/implementing-communication-notifications ). `isFocused` says only that *some* Focus is on, and only if the user enabled "Share Focus status" for that Focus (https://support.apple.com/guide/mac-help/mchlff5da36d/mac). Review risk: claiming a communication-app capability in a setlist app could be questioned (**UNVERIFIED**). Weak signal: a Sleep or Work Focus already on would read as "confirmed".
- Better: a **Focus filter** (`SetFocusFilterIntent`, macOS 13+, https://developer.apple.com/documentation/appintents/setfocusfilterintent ; overview https://developer.apple.com/documentation/appintents/focus ). The user adds Segue's filter to their "Performing" Focus in System Settings; the system runs Segue's intent when that Focus turns on ("When someone engages a Focus, the system executes your app's custom SetFocusFilterIntent"). This tells Segue that *the specific* Focus activated, with no entitlement and no communication capability. Called again on deactivation with default values: from WWDC22 "Meet Focus filters" (session 10121), **UNVERIFIED** by probe. It verifies the outcome, not the shortcut, so it also works if Ryan turns the Focus on by hand.

### 2.7 Other options considered

- "Open URL `segue://gigmode/ok`" as the shortcut's last action: same idea as 2.5 with a URL scheme instead of an intent; cruder (brings Segue forward, user types a URL). 2.5 is better.
- Reading `~/Library/DoNotDisturb/DB/*.json` or private DND/WorkflowKit APIs: blocked by the sandbox and by 2.5.1 (public APIs only). Rejected.
- There is no public in-process API for a third-party app to run a user Shortcut by name on macOS (Intents' `INVoiceShortcutCenter` only covers the app's own donated shortcuts). **UNVERIFIED** that nothing new landed in the macOS 27 SDK.
- Manual "Done" (WS1 option C): always truthful, no automation.

### 2.8 Comparison

| Mechanism | Learns success? | Learns failure? | Entitlement | User setup | MAS risk |
|---|---|---|---|---|---|
| x-callback-url | Only via x-success (regressed 26.5+) | No (code 4 on success) | none | none | none |
| NSUserUnixTask + CLI | Exit 0 | Exit != 0 (action-failure mapping UNVERIFIED) | none | install script | low |
| Process + CLI | Exit 0 (real run UNVERIFIED) | Exit != 0 | none | none | medium, UNVERIFIED |
| Apple events to Shortcuts Events | Returns | Throws (action-failure mapping UNVERIFIED) | scripting-targets `com.apple.shortcuts.run` + apple-events | one TCC prompt | low-medium, UNVERIFIED |
| App Intent callback | Intent runs | Silence (timeout -> unknown) | none | add action | low |
| Focus filter | Focus actually on | Silence (timeout -> unknown) | none | add filter to Focus | low |
| INFocusStatus | Some Focus on | No | Communication Notifications | permission + share status | medium |
| Manual Done | Performer says so | n/a | none | tap | none |

---

## 3. Recommendation

Primary: **Apple events to Shortcuts Events** (2.4) as the runner, replacing the `shortcuts://run-shortcut` hand-over. It is the only zero-setup mechanism that observes both success and failure, it uses an access group Apple publishes for exactly this, and it is synchronous, so the row state comes from the result, not a guess.

Optional outcome check: **Segue Focus filter** (2.6). If the user has added it, the row can say the Focus is actually on, which is what the performer cares about.

Fallback: **manual "Done"** on any row that ends in `unknown`, as WS1 already plans for brightness.

If the section 4 probe shows the scripting-targets path is blocked in a real sandboxed build, use the **App Intent callback** (2.5) instead, with manual Done as the fallback (WS1 Q1 option "b + c").

Row states (`PreShowChecklist.FocusStatus`), what the row shows, and whether it ticks:

| State | When | Row detail | Ticks? |
|---|---|---|---|
| `notConfigured` | no Shortcut set | "Gig Mode Shortcuts are off. Set them up in Settings > Live." | no |
| `running(name)` | request sent, awaiting result | "Running “Gig Mode On”..." | no |
| `ran(name)` | Shortcuts Events `run` returned without error (or App Intent callback received) | "“Gig Mode On” ran." | **yes** (meets R18) |
| `confirmed(name)` | ran, and Segue's Focus filter fired | "“Gig Mode On” ran. Focus is on." | **yes** |
| `unknown(name)` | timed out (e.g. 30 s), or only a hand-over/x-error code 4 is known | "Asked Shortcuts to run “Gig Mode On”; couldn't confirm it finished." + Done button | no, until Done |
| `failed(name, message)` | Apple-event error: not found (-1728), permission denied, shortcut error | "“Gig Mode On” failed: <message>." + Retry | no |

Note this splits WS1's planned `.requested` into `running` (in flight) and `unknown` (gave up waiting), and keeps `ran` as a tick only because, under this recommendation, `ran` is an observed completion rather than a hand-over. If x-callback or plain URL hand-over is kept anywhere, it may only ever produce `running` / `unknown`, never `ran`.

---

## 4. Probe to run before building (needs Ryan)

Manual step for Ryan: in Shortcuts, create **"Segue Focus Probe"** with one harmless action (e.g. "Show Notification: probe"), and a second **"Segue Focus Probe Fail"** whose only action fails (e.g. "Get Contents of URL" `https://invalid.invalid`). Then, on 26.6.2 (and 27 if available):

1. `shortcuts run "Segue Focus Probe"; echo $?` and the Fail variant: confirms the CLI exit codes (2.2, 2.3).
2. `osascript -e 'tell application "Shortcuts Events" to run shortcut "Segue Focus Probe"'` and the Fail variant: does an action failure throw? (2.4)
3. x-callback: `open 'shortcuts://x-callback-url/run-shortcut?name=Segue%20Focus%20Probe&x-success=segue-probe://ok&x-error=segue-probe://err'` with a tiny URL-scheme handler (or the Debug Segue build once it registers `segue`), with and without a "Stop and Output" action: does x-error code 4 still fire on success? (1)
4. Re-run 1 and 2 from a real sandboxed build (a scratch target or Segue Debug with the scripting-targets entitlement added locally): does the sandbox allow it, and does the TCC prompt appear?

Record results in this doc. Cleanup note: my sandbox probe left an empty container at `~/Library/Containers/dev.ryandsilva.segueshortcutprobe`; a guard hook blocked me from deleting it, so Ryan can remove it by hand.
