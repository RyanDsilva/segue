# Ryan's walkthrough (R56)

Run this once every app workstream has passed its gate. The orchestrator builds the App Store flavour and launches it from a clean first-run state. Feedback goes into a fix round before screenshots (WS5), TestFlight and the real gig.

Items the agents could not verify headlessly:

## First run
- [ ] The Welcome sheet (design A Native): library folder, Welcome songs, consent page with two equal-weight choices and the privacy link.
- [ ] The 4 Welcome songs and the "Welcome Set" setlist appear and read well (romanized Hindi included).

## Library and files
- [ ] **Real Trash (App Store build):** choose a library in `~/Music/Segue`, delete a song, then check that Finder's Trash has it, that Put Back works, and that Edit > Undo restores it.
- [ ] Drag `.cho`/`.txt` files and a folder in from Finder; open a `.cho` from Finder (it is copied in) and check the Quick Look preview.
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
