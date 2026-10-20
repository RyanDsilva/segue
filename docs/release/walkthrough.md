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
- [ ] Help menu items all open the right pages; About panel; Window > Segue Library (Cmd-0) reopens a closed main window. (Acknowledgements left the app 2026-10-18: no Help item or About credits; the notices are on the website, linked from Privacy and Terms.)
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

## Phase 3 (R79): run on the App Store build from a clean first run, then repeat the marked items on the Personal build
Everything new in 0.5's phase 3, in the order a gig day uses it. Notes on what feels wrong go straight into the fix round.

### Paste and import
- [ ] **Paste from a real site:** copy a song from a chord site (a UG page and one other, one Hinglish), File > New Song from Clipboard (Option-Command-V). The review sheet shows the original and the result; section labels are right; title and artist are right (the converter wins, R121); a sparkle marks only AI-decided labels or fields (R117); Accept saves; Cancel saves nothing.
- [ ] **Swap Title/Artist:** a paste whose heading is "Artist - Title" offers the one-click swap.
- [ ] **New Song:** the paste flow opens first; "Start blank" opens a blank editor with the song card (R83).
- [ ] **Three-file batch:** drag two `.txt` chord sheets and one `.crd` together: ONE review sheet lists all three with a preview each; untick one; "Import 2 Songs" imports only the ticked ones (R96); one Edit > Undo takes the import back.
- [ ] **`.crd` import** on its own goes through the converter and the sheet (R76).
- [ ] **During a show** (start one, switch back to the library window): Option-Command-V, the empty-state button and `.txt`/`.crd` drops are disabled or refused with a clear message; a `.cho` drop still imports; New Song opens blank (R95, R109).
- [ ] **Question:** the paste review's draft card puts the cursor in Title with the text selected. Keep that, or leave nothing focused?

### AI
- [ ] **Settings > AI (App Store build):** Apple Intelligence status with its note; the one toggle "Use AI to refine pastes and set requests" (on); the local model card shows Qwen3 4B Instruct, 2.27 GB, memory need, free disk, the Apache-2.0 licence link; no Advanced section (Personal only, R62).
- [ ] **Model download on the App Store build:** click Download; progress, Cancel, then Download again resumes; it finishes, checks its files and says Downloaded; a paste is now refined by the local model (sparkles). The Personal build sees the same model without a second download (R100). Delete... asks once, then removes it at once, for both apps (R99).
- [ ] **Apple Intelligence unavailable note:** with Apple Intelligence turned off in System Settings, Settings > AI shows the reason-specific note and "Open System Settings" opens Apple Intelligence & Siri (R69; the link was checked headlessly on 2026-10-20). No nag prompts anywhere.
- [ ] **AI toggle off:** pastes and set requests still work with Segue's own rules, with no sparkles and no "Refining with..." status.
- [ ] **Low memory (if a Mac under 16 GB is at hand):** Apple Intelligence is the default and the model card carries the speed and memory note (R120).
- [ ] **Reset All Settings** (Settings > Data) resets the AI toggle but keeps the downloaded model (R73).
- [ ] **Welcome card:** "Paste any chord sheet" with the "AI settings and the local model" link; it opens Settings > AI.

### Song card and editor
- [ ] **Song card fields:** title, artist, key, tempo (Tap: four taps give a sensible BPM, R111), length, capo, time signature, proficiency, tags; each writes the file (check in Text mode); the set-essentials dots disappear as key, length and tempo are filled (R80).
- [ ] **Time it:** start, stop, the length field fills; Undo is named "Set Length".
- [ ] **Question:** in the library heading, title and artist are edited by double-click with no visible affordance. OK as is, or add a hint?
- [ ] **Slash menu:** in Text mode type `/`: plain names, a section entry wraps the selected lines, value pickers for key, tempo and length (R81).
- [ ] **`{key: Hm}`** is flagged with a fix that writes `{key: Bm}`.
- [ ] **Section band:** select lines in the visual editor, press V / C / B / I or click a chip; drag a band edge to resize; the band menu's Section Notes... (R82).
- [ ] **Section notes:** add a note to a chorus with "Show on stage only" on: it shows on stage as a callout and never in the `.cho`; turn it off: it becomes a `{comment}` in Text mode (R87, R106).

### Set building
- [ ] **A 20-song set in Pick mode by keyboard only:** type to filter, Return, Space to tick (tick order = set order), Down, Command-A ticks the filtered list; nothing is added twice (R84).
- [ ] **Arrange:** Option-Up / Option-Down and drag; Command-click selects several.
- [ ] **Library multi-select:** Command-click and Shift-click in the main Library, then Add to Setlist.
- [ ] **Break rows:** Insert Break (Shift-Command-B); each part shows its own total; a break length counts in the whole-set total only (R85, R105); the changeover time (setlist and the global default in Settings) is added to the totals (R86).
- [ ] **Missing lengths:** "N unknown" is a button listing exactly the songs without a length; typing a length in a row fills the song (R88).
- [ ] **Set assistant:** in Arrange type "45 min, songs I know well, upbeat start", Build fills the open setlist as one undo step; a row's breakdown (select it, Space); lock a song, Rebuild keeps it, and it survives reopening (R114, R115); "N songs left out: no length" opens the missing-lengths list (R107); with the local model downloaded, extra "Suggested" chips may appear and are applied only on click (R116).
- [ ] **Question:** the assistant lands slightly over the target (22:07 for a 20:00 request). Keep "fill to at least the target", or aim for the closest total either side?
- [ ] **Smart filters:** create one, apply it, use it in a request ("from <filter>"); the built-in "Missing essentials" filter (R110).
- [ ] **Arrange Sections:** from a slot's popover Arrangement row, the slot context menu and the Setlist menu; skip a section, play one twice, drag one; the live preview follows; a slot length is asked for; Reset to full song (R122, R123). Edit the song so a section disappears: the slot is marked out of date, the pre-show checklist has a row with Edit, and the stage plays the full song with a quiet "Full song" note.
- [ ] **Question:** an out-of-date arranged slot shows a "Full song" header on stage, and the builder row's mark is a scissors icon. Both OK?

### On stage
- [ ] **Metronome on stage:** the checklist's Metronome switch, then the pulsing dot plus BPM bottom right, beat 1 red; 6/8 pulses twice per bar; M toggles it for this show only; it is hidden for a song without a tempo (R90, R108, R118).
- [ ] **Metronome sound in a rehearsal:** K toggles the click (off at the start of every rehearsal); a show never makes a sound.
- [ ] **Question:** Live > Metronome in the menu bar shows no key equivalent, although M works on stage. Show "M" in the menu?
- [ ] **No repeats:** during a show, Insert Next (or a request, or Play Now) of a song already played is refused with a clear message; an upcoming song offers "Move to Next" instead; a skipped song may be added back (R102, R112). The quick search result says its standing ("played", "up next").
- [ ] **Break interstitial:** a break row on stage shows "Break - Set 2 starts with <song>"; Next continues; the show clock keeps running (R104).

### About and the website
- [ ] **About panel in dark mode:** the one row of links (Website, Help, Support, Privacy Policy) stays legible; each opens the right page (R103).
- [ ] **Website (live):** /privacy has "AI features and the optional model" and the Hugging Face row; /support answers "Does Segue use AI?"; /acknowledgements lists MLX, XGrammar, swift-transformers and the Qwen3 model; the browser console shows no CSP error for the Web Analytics beacon after the next deploy (P3-9).

### Accessibility of the new screens (R79; claims stay off until these pass)
The automated audit (`AccessibilityAuditE2ETests/testPhase3ScreensLight`, docs/release/accessibility-audit.md section 6) covers what a machine can see. These walks decide the VoiceOver, Voice Control and keyboard claims.

| Screen | VoiceOver (VO-Right through it, VO-Space to act) | Voice Control ("Show names", "Show numbers") | Full Keyboard Access (Tab, Space, arrows) |
|---|---|---|---|
| Paste review sheet, single | [ ] original and result are reachable; each section label is read with its sparkle as "suggested by AI"; Accept and Cancel are named | [ ] "Click Accept", "Click Cancel"; the Title field takes dictation | [ ] Tab reaches the title, artist, every label menu, Accept; Return accepts, Esc cancels |
| Paste review sheet, batch | [ ] each file row reads its name and checkbox state | [ ] "Click <number>" ticks and unticks a row | [ ] Space ticks the focused row |
| Settings > AI | [ ] status note, toggle, model card values (size, memory, licence link), Download / Cancel / Delete | [ ] "Click Download", "Click Delete" | [ ] every control reachable, with visible focus |
| Song card and Time it | [ ] each field reads its name and value; the missing-essential dots are read ("key missing"); Tap and Time it are named | [ ] "Click Tap", "Click Time it", type a length by voice | [ ] Tab order runs title to tags; Space starts and stops Time it |
| Slash menu | [ ] the menu items are read as a list; the value pickers are reachable | [ ] "Show numbers" picks an item | [ ] arrows and Return choose an item |
| Section band | [ ] each band is read with its label; the chip bar's V / C / B / I chips are named | [ ] "Click Chorus" on the chip bar | [ ] the band menu opens from the keyboard (Control-Return or the context-menu key) |
| Section notes sheet | [ ] each note's text and "Show on stage only" checkbox; Add and Done | [ ] "Click Show on stage only" | [ ] Tab through notes; Space toggles the checkbox |
| Set builder Pick | [ ] each library row says whether it is in the set ("already in set") | [ ] "Click <number>" ticks a row | [ ] Space ticks, Command-A ticks all, focus visible |
| Set builder Arrange, break rows, totals | [ ] rows read position, title, length; a break reads its label and part total; the total reads "N unknown"; Move up / Move down actions | [ ] "Click Insert Break", "Click <n> unknown" | [ ] Option-Up / Down move the focused row; Shift-Command-B inserts a break |
| Missing-lengths list | [ ] each row reads the song and its empty length field | [ ] dictate a length into a row | [ ] Tab moves row to row |
| Set assistant bar and chips | [ ] the field, each chip ("45 min", "Suggested ..."), Build and Rebuild; the "left out" note | [ ] "Click Build", "Click Suggested <chip>" | [ ] Tab reaches each chip and its remove button |
| Score breakdown popover | [ ] each factor and its weight is read | [ ] n/a (opened by Space or hover) | [ ] Space opens it, Esc closes it |
| Smart filter editor | [ ] each condition row and its pop-up menus | [ ] add and remove a condition by voice ("Show names") | [ ] every pop-up reachable |
| Arrange Sections sheet | [ ] each row reads label, play count and skipped state; Reset to full song; the slot length field | [ ] "Click <number>" toggles a row; "Click Done" | [ ] Space skips the focused row; plus and minus change the count |
| Metronome overlay (stage) | [ ] read as "Metronome, <n> beats per minute"; it never steals VoiceOver focus from the song while pulsing | [ ] n/a (M key) | [ ] M toggles it; K toggles the rehearsal click |
| Live repeat message | [ ] the refusal and "Move to Next" are announced and reachable | [ ] "Click Move to Next" | [ ] Return and Esc answer it |
| About panel links (dark) | [ ] each link is read with its name | [ ] "Click Website" | [ ] Tab reaches each link |
