# Ryan's walkthrough (R56)

Run this once every app workstream has passed its gate. The orchestrator builds the App Store flavour and launches it from a clean first-run state. Feedback goes into a fix round before screenshots (WS5), TestFlight and the real gig.

Items the agents could not verify headlessly:

## First run
- [ ] The Welcome sheet (design A Native): library folder, Welcome songs, consent page with two equal-weight choices and the privacy link.
- [ ] The 4 Welcome songs and the "Welcome Set" setlist appear and read well (romanized Hindi included).
- [ ] **Real open and save panels (App Store build):** on page 1, "Choose Existing Folder..." and "Create Library in Music..." both work (XCUITest cannot drive the sandboxed panels). Cancel leaves page 1 as it was.
- [ ] Quit on page 3 and relaunch: only the consent page comes back ("Step 1 of 1").
- [ ] Help > Welcome to Segue...: the cards and "Add Welcome Songs" (or the "in your library" line); Esc closes it.
- [ ] Settings > Data > Remove Welcome Songs...: edit one Welcome song first; the dialog says it is kept; the rest go to Finder's Trash with Put Back.

## Library and files
- [ ] **Real Trash (App Store build):** choose a library in `~/Music/Segue`, delete a song, then check that Finder's Trash has it, that Put Back works, and that Edit > Undo restores it.
- [ ] Drag `.cho`/`.txt` files and a folder in from Finder; open a `.cho` from Finder (it is copied in) and check the Quick Look preview.
- [ ] **Finder integration (one flavor installed):** a `.cho` shows the Taped page icon and "ChordPro Song" as its kind in icon view (16, 32, 128, 512) and list view, light and dark; double-click opens Segue; a song already in the library is selected instead of copied; Open With on a `.pdf` is refused with a banner. `mdls -name kMDItemContentType` reports `dev.ryandsilva.segue.chordpro` (or another app's exported type, which is acceptable under A30: write down which).
- [ ] **Quick Look:** space bar on a Welcome song in Finder shows the song page (title, key line, coral chords over lyrics); `pluginkit -m -p com.apple.quicklook.preview | grep segue` lists the extension.
- [ ] **Export Library Archive** from File and from Settings > Data: the save panel suggests "Segue Library <date>.zip"; the zip opens to one dated folder with songs, setlists, shows and timings, and no `.segue`.
- [ ] Autosave: type, switch songs, quit; edit the same file in another editor and check that the conflict bar appears.

## Live and Gig Mode
- [ ] **Personal build:** in Settings > Live, set the start Shortcut to a real one and press Test. Exactly one Automation prompt should appear, with the new usage text.
- [ ] Start a gig: the Focus row ticks only after the Shortcut finishes, and Shortcuts does not come to the front.
- [ ] A missing Shortcut name, a failing Shortcut, and Automation turned off (System Settings) should each show their own message; the last one should offer "Open Automation Settings...". Manual Done works.
- [ ] Page-turner pedal (or the Page Down key): it scrolls, then moves to the next song at the end; Page Up mirrors it.
- [ ] The `?` overlay on stage; any stage key closes it.

## Menus and windows
- [ ] Help menu items all open the right pages; About panel; Acknowledgements; Window > Segue Library (Cmd-0) reopens a closed main window.
- [ ] The window size and position are restored after relaunch.

## Services (WS3)
- [ ] **TelemetryDeck smoke signal (agent-sent 2026-10-18 08:23 PT):** in the dashboard, open the **Segue Personal** app (the run was a Debug-Personal build), switch on **Test Mode**, and find one request of five signals: `TelemetryDeck.Session.started`, `Segue.App.launched`, `Segue.Library.snapshot`, `Segue.Help.opened` and `Segue.Feedback.sent`. The ingest API answered HTTP 200. Check that each payload carries only `segue.*` keys plus the five context keys (OS, OS version, app version, build, region) and no song titles. Nothing should have reached the **Segue** (App Store) app.
- [ ] **Sentry smoke report (agent-sent 2026-10-18 08:23 PT):** in Sentry, **User Feedback** for `segue-macos`: one report whose message starts "SMOKE TEST - ignore", with the log attachment(s) (`segue-0.log` and older) and the `segue` context (app version, build, flavor `personal`, Mac model). The envelope endpoint answered HTTP 200. Resolve or delete it afterwards.
- [ ] Sentry > Issues shows nothing from that run (no crash was sent) and no sessions.
- [ ] First run of the App Store build: the consent prompt shows two equal choices; with `nettop -p Segue -L 1` open, nothing connects to `telemetrydeck.com` or `sentry.io` before Continue.
- [ ] Settings > Privacy: turn both off and read the captions; Copy puts the Diagnostics ID on the clipboard; turning crash reports back on says it starts next time.
- [ ] Help > Report a Problem with Wi-Fi off: "Email Instead" opens Mail with the attachments; "Save Report..." writes a folder with `report.txt`.
- [ ] Request a Feature opens `segue.ryandsilva.dev/feedback`, which redirects to `segue.featurebase.app` once the site is deployed.

## What's New, tips and review (WS2b)
- [ ] Help > What's New in Segue opens the notes (or the web changelog while the 0.5 entry is still a draft).
- [ ] Tips: the search tip on a library of 5+ songs, gone after the first search; the Start Show tip; after a first show without Gig Mode Shortcuts, the Gig Mode tip with "Open Settings" landing on Settings > Live. Never on stage. Settings > Data > Reset Tips brings them back after a restart.
- [ ] After the first real gig ends (development build), the review prompt appears a few seconds after the end-of-show flow, once; never on stage.
- [ ] Settings > Appearance: Light and Dark switch every window at once; the stage stays dark; Match System follows the system again.

## Accessibility (WS2b step 12, docs/release/accessibility-audit.md)
- [ ] **VoiceOver walk** (VO-Right through each screen, VO-Space to act, the rotor for headings) on every row of the audit's section 5 table. In particular: the Welcome title is read before "Step n of m"; a song line reads "G, D: Van door slides..."; in the visual editor the Actions rotor on a chord offers Move left/right one syllable, Edit chord and Delete chord, and they work; a set row offers Move up and Move down and they work; the stage body is reachable line by line; the editor reads "ChordPro source" and never a machine report; one TipKit tip and its close button.
- [ ] **Voice Control walk** with "Show names" and "Show numbers" on each screen: create a library, add the Welcome songs, answer both consent rows, open a song, transpose, add to a setlist, start and end a show.
- [ ] **Full Keyboard Access:** Tab reaches every control on every screen, including sheets, with visible focus.
- [ ] **Increase Contrast** on and off, light and dark, with Reduce Transparency on and off: every screen's text and control edges are clear (this decides the Sufficient Contrast claim).
- [ ] **Reduce Motion** on: Welcome pages swap without a fade, stage songs change without a fade, nothing zooms.
- [ ] **Larger Text checks:** the stage at a 48 pt minimum lyric size with zoom (Cmd +) at its limit in a 13-inch-sized window scrolls instead of clipping; the main window at 820x520 with a long title truncates with a tooltip and nothing overlaps; note what macOS 26's Text Size setting changes, if anything.
- [ ] Dark Interface: no white flash when sheets open, a window opens, or the stage opens and closes.
