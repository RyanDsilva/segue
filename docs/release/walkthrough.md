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
