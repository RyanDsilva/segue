# Phase 2 - Setlists & Live Mode

> Canonical parent: `docs/00-vision.md`. Depends on phase 0 (skeleton: library, index, basic live view) and phase 1 (rendered chart with transpose/capo/Nashville). Outcome: **gig-ready**.

## Goal

Run a whole solo/duo gig from a MacBook on a stand. That means building setlists, performing them in a dark stage mode where each song reads at a glance, and handling requests and skips mid-show without fumbling. Afterwards a gig log records what was played.

## Scope

- A setlist builder: create, rename, duplicate and delete setlists, and add, remove and drag-reorder songs.
- A full live mode:
  - auto-fit layout and auto-scroll
  - next-song footer and dark stage theme
  - per-song zoom memory and section highlighting
  - keeping the display awake
- Show operations: quick library search overlay, request queue, skip and mark played, live reorder.
- A gig log written automatically from a show, and editable afterwards.
- Per-song notes and cues shown in live mode.
- Basic tags and proficiency rating: editing, display and simple filtering. Smart filters come in phase 3.
- A command layer that the keyboard (including keystroke pedals) and MIDI (phase 6) all map onto.
- Crash-safe show state.

## Non-goals

- Break rows and per-part timed totals (phase 3, R85)
- Backing tracks
- MIDI input itself (phase 6)
- AI set building (phase 3)
- PDF export (phase 4)
- Smart or saved filters (phase 3)

## Data model

Files stay canonical (see vision section 2). The SQLite index projects setlists and the gig log for search, but is never written as the source of truth.

**Setlist** - `Setlists/<ulid>.json`
```json
{
  "id": "01J...", "name": "Friday - The Anchor", "createdAt": "...", "updatedAt": "...",
  "venue": "The Anchor", "date": "2026-10-23",
  "items": [
    { "itemId": "01J...", "songId": "wonderwall", "overrides": { "transpose": 0, "capo": 2 }, "note": "start soft" }
  ]
}
```
- `songId` is the song's stable id from its sidecar, not its filename, so renames don't break setlists.
- `itemId` identifies a slot (and the matching show item). A song appears at most once per setlist: every add path skips a song already in it, and Save at show end leaves out a request that repeats one. A setlist saved with a repeat before that rule loads as saved, the repeat marked in the builder ("Also at #n") so it can be removed.
- `overrides` holds per-setlist key and capo without editing the song.

**Show** - `Shows/<ulid>.json`, written continuously during a gig.
```json
{
  "id": "01J...", "setlistId": "01J...", "startedAt": "...", "endedAt": null,
  "order": ["itemId", "..."],
  "states": { "itemId": "pending|current|played|skipped" },
  "currentItemId": "...", "scrollPosition": 0.42,
  "requests": [ { "requestId": "01J...", "songId": "...", "addedAt": "...", "note": "table 4", "state": "queued|played|dropped" } ],
  "events": [ { "at": "...", "kind": "started|advanced|skipped|reordered|requestAdded|requestPlayed|jumped", "itemId": "..." } ]
}
```
- A show is a run of a setlist. Reordering during a show changes `order` only. When the show ends, if `order` differs from the setlist, the app always asks: a diff sheet (planned vs played order, inserted requests marked) with **Save to setlist** / **Discard**, no preselected default. Ending with no reorder skips the sheet.
- Played and skipped state lives on the show, not the setlist, so a setlist stays reusable.

**Gig log entry** - a finished show is its own gig log record: `endedAt` set, plus optional `venue`, `notes` and `rating`.
- The "played" list is derived from the events: each song's start and end times, and whether it came from a request. `advanced`/`jumped` events must carry accurate timestamps from the injected clock.
- Gig log fields are fixed at venue, date, notes, rating. No pay/tips or per-song crowd notes.
- Library views show "last played" and "times played" per song from the index projection.

**Song sidecar additions** (`<song>.json`):
- `tags: [String]`
- `proficiency: "learning" | "ready" | "pro"` - three named levels, stored as strings (not numbers) so the scale reads the same in the file and the UI
- `notes: String` - shown in live mode
- `cues: [{ section, text }]` - pinned to a section
- `display: { zoom, columns?, autoScrollSpeed?, collapseRepeats? }` - per-song memory; `collapseRepeats` defaults to `true` when absent

App-level setting (not per song): `live.minLyricFont` (default 22pt), editable in Settings > Live.

## Live mode UX

**Entry:** pick a setlist, then "Start show".
1. The app goes full screen with `presentationOptions` set to hide the Dock and menu bar.
2. It applies the stage theme and takes the keep-awake assertion.

**Auto-fit layout.** The goal is the whole song visible without scrolling at the largest legible size. The algorithm is deterministic, pure and unit-tested:
1. Lay out the song from the rendered model built in phase 1: sections, lines, chord runs.
2. Collapse repeated sections, if the song's `collapseRepeats` is on (default). The first occurrence always renders in full. A later section whose content equals an earlier one (normalized lyrics and chords) becomes a one-line reference, `Chorus (x2)`, plus any differing lines. With the toggle off, every section renders in full. The toggle is in the live view's per-song menu and saved to the sidecar.
3. For columns = 1...3 (limited by the minimum column width), binary-search the largest font size, between `minFont` (the user's `live.minLyricFont`) and `maxFont`, at which the content fits the viewport height. Columns break at section boundaries, never mid-section.
4. Pick the candidate with the largest font. Ties go to fewer columns.
5. If nothing fits at `minFont`, the font is never shrunk below it: fall back to one or two columns at `minFont` and scroll (auto-scroll or manual page down).
6. The per-song zoom offset (from the sidecar) then scales the result. If the user pinches or uses Cmd +/-, the new offset is saved to that song.

**Auto-scroll:**
- **Speed** comes from the song's time: its tempo times the bars played, from its timeline (R172, P8-8). The overflow height scrolls over that time minus an intro offset. With no time but a tempo, it's estimated from `tempo` and `time` (beats per line). Otherwise a default speed is used, adjusted with [ and ].
- **Controls:** pause/resume, nudge faster or slower (saved per song), and restart from the top.
- **Start:** never moves until the user starts it, or until the first advance if "auto-start" is set per song.

**Next-song footer:** shows the next item's title, key (after overrides), capo and the first line or section label. If a request is queued, the footer shows "Request: <title>" instead.

**Section highlighting:** sections get distinct, low-luminance background tints by type. Labels are bold, and chords use one accent color. Cues render as callouts at the section edge.

**Stage theme:**
- Near-black background, text above a high contrast ratio, no bright chrome.
- Status (song n/m, elapsed time, auto-scroll indicator) fades in only on mouse move.

**Keep awake:** use `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep)`, or `ProcessInfo.beginActivity(options: .idleDisplaySleepDisabled)`, held for the show's lifetime. This is believed to work in the sandbox. Verify it in the phase 0 sandbox build.

**Notification suppression.** A sandboxed app has no public API to turn on Focus or Do Not Disturb, so the app delegates to a Shortcut the user owns:
- **Shortcut hooks:** Settings > Live has two optional fields, "Shortcut on show start" and "Shortcut on show end" (defaults: `Gig Mode On` / `Gig Mode Off`). The app runs them via `shortcuts://run-shortcut?name=...` and immediately re-asserts full screen and key focus so live mode isn't left behind the Shortcuts app. Settings has a "Test" button per field and a one-paragraph guide on creating a Shortcut that sets a Focus.
- **Pre-show checklist:** shown on "Start show" before entering live mode: Focus on (ticked automatically only if the Shortcut ran without error), charger connected (read from IOKit power source), screen brightness up. Each row can be dismissed; "Don't show again" per row.
- **Not adopted:** a Focus Filter integration (app reacting to a Focus). Can be revisited later.

**Quick search overlay (Cmd-K or `/`):**
- Fuzzy search over title, artist, first line and tags, from the index. It must never block the live view.
- Tolerant of romanized Hindi spelling variants through phase 0's normalized index ("pyar" finds "Pyaar", "hai" finds "hain"); results show the song's original spelling.
- Results show key, capo and proficiency (Learning / Ready / Pro badge).
- Actions: "Play now" (jump; the selected song becomes `current` and the interrupted song goes back to `pending` at its original position, so you can return to it later), "Add to requests", "Insert next".
- Esc returns to the live view at the same scroll position.

**Reorder and skip:** a sidebar drawer (toggle `S`) lists the show order with states. You can drag to reorder, skip, or un-skip. Skipped items are dimmed and stay in the list.

## Command layer

Every action is a `ShowCommand` enum case, dispatched through one `ShowController`:
- `next`, `previous`
- `scrollPageDown`, `scrollPageUp`, `toggleAutoScroll`, `scrollFaster`, `scrollSlower`
- `skipCurrent`, `openSearch`, `playNextRequest`, `toggleSidebar`
- `zoomIn`, `zoomOut`, `resetZoom`
- `endShow`

Input sources map raw events to commands through a binding table (`Bindings.json`, with defaults in code). Phase 6 adds MIDI sources without touching `ShowController`.

Default keys:

| Key | Command |
|---|---|
| Right, Space | next |
| Left | previous |
| PgDn, Down | scrollPageDown |
| PgUp, Up | scrollPageUp |
| A | toggleAutoScroll |
| [ and ] | slower / faster |
| Cmd-K or / | openSearch |
| R | playNextRequest |
| X | skipCurrent |
| S | toggleSidebar |
| Cmd +, Cmd -, Cmd 0 | zoomIn, zoomOut, resetZoom |
| Cmd-. | endShow (asks for confirmation) |

Pedals usually send PgUp/PgDn or arrow keys, so they work by default.

## Crash safety

- Show state is written atomically (temp file plus rename) on every command. Scroll position is debounced to 1 second.
- On launch, any show with `endedAt == null` and an update less than 12 hours old triggers "Resume show?". The default button resumes into live mode at the same song and scroll position.
- The live view renders from an in-memory snapshot of the song. File, index or AI activity can't stall it, and an external edit to the current song applies only on the next advance.
- If the song file goes missing mid-show, the last snapshot stays displayed.

## Test strategy

Integration-first: tests drive real components (real ChordPro parser, real file store on a temp library folder, real GRDB index, real `ShowController`) and real UI flows. Every run starts from a freshly reset temp library seeded with fixtures. Unit tests only where logic is pure and tricky.

- **Integration tests (Swift Testing, no UI):** drive `ShowController` with command sequences against a real temp library and assert on the files it writes:
  - show JSON on disk after each command (atomic write, debounced scroll), reloaded through the real store
  - finished show -> gig log entry -> index projection ("last played", "times played") queried through GRDB
  - resume detection: write a stale/fresh unfinished show, relaunch the controller with an injected clock
  - external edit to the current song's file mid-show applies only on next advance; deleted file keeps the snapshot
  - end-of-show reorder flow: diff produced, Save writes the setlist file, Discard leaves it byte-identical
  - property test over random command sequences: `order` stays a permutation of setlist items plus inserted requests, exactly one item is `current`, and every file written reloads cleanly
- **Unit tests (pure logic only):** the auto-fit algorithm (fixed fonts and fake text metrics, golden layouts, min-font scroll fallback, `collapseRepeats` on/off) and scroll-speed derivation.
- **Snapshot tests:** the live view at 13" and 16" MacBook sizes, in the stage theme, with short, long and very-long songs.
- **E2E (XCUITest)** - the primary suite:
  1. **Friday gig:** start a 10-song set and advance through 3. Skip song 4. Cmd-K for a song not in the set, add it to requests, play it (R), continue. End the show. The gig log shows 9 played, 1 skipped and 1 request in order, and the library shows "last played" updated.
  2. **Crash resume:** start a show, advance to song 5, scroll halfway, kill the process, relaunch. The app offers resume and lands on song 5 at the same scroll position.
  3. **Auto-scroll:** a long song whose timeline lasts 3:00 scrolls to the bottom in about 3 minutes (injected clock), and pause holds the position.
  4. **Zoom memory:** zoom song A, advance to song B, then go back. A keeps its zoom and B is unaffected.
  5. **Live reorder:** drag song 8 to next. The footer updates. On ending the show the diff sheet appears; Discard leaves the setlist file unchanged, and a second run with Save persists the new order.
  6. **Play now:** mid-song 3, Cmd-K "Play now" on song 7. Song 7 becomes current, song 3 is back to pending in its slot and is reachable later.
  7. **Min font:** set `live.minLyricFont` to 30pt; a 40-line song no longer fits, renders at 30pt and scrolls instead of shrinking.
  8. **Romanized Hindi request:** mid-show, Cmd-K and type "pyar"; the song titled "Pyaar" (fixture) is in the top results; add it to requests and play it.
  9. **Shortcut hooks:** with a fake Shortcut runner injected (the real `shortcuts://` call is verified manually), start and end a show and assert both hooks fired and live mode kept focus.

## Acceptance criteria

- Every fixture song up to 40 lines fits on one screen without scrolling at 13" at the default minimum of 22pt for lyrics. Longer songs scroll; lyrics never render below the user's minimum.
- With the Shortcut hooks configured, starting a show turns on the user's Focus and live mode stays frontmost (manual check).
- Mid-show search finds songs by romanized Hindi spelling variants as reliably as by exact title.
- Advancing renders the next song within 100ms. The quick search overlay opens within 100ms and returns results within 50ms for a 2,000-song index.
- No display sleep during a 3-hour show (manual check, plus an assertion test).
- Kill -9 at any point loses at most 1 second of scroll position and no command state.
- All commands are reachable from the keyboard. Live mode needs no mouse.
- All tests above pass in CI, and the E2E suite runs against a freshly reset library each run.

## Design gate

Before building the live UI, present **2-3 distinct visual directions** for the live view, setlist builder and search overlay (mockups or screenshots) and let the user pick. Build only after a direction is chosen.

## Resolved decisions

See `docs/decisions.md` (Phase 2).

1. **Notification suppression:** run the user's "Gig Mode" Shortcut on show start/end plus a pre-show checklist. Implication: two Shortcut-name settings, a fake runner for tests, no Focus Filter.
2. **Minimum font:** user-set `live.minLyricFont`, default 22pt; below it the song scrolls. Implication: auto-fit never shrinks past the setting.
3. **Repeated chorus:** per-song `collapseRepeats` toggle, default on (first occurrence full, later repeats collapsed). Implication: one new sidecar display field.
4. **Live reorder:** always ask at show end via a diff sheet with Save/Discard. Implication: no silent default either way.
5. **"Play now":** the interrupted song goes back to pending. Implication: jumping never marks a song played.
6. **Gig log fields:** venue, date, notes, rating only.
7. **Proficiency:** three levels, Learning / Ready / Pro, stored as strings in the sidecar. Implication: phase 3 scoring and filters use the same three levels.
8. **Unfinished show older than 12 hours:** auto-closed into the gig log on next launch, and the reorder diff (Save/Discard) is offered then. Implication: no show data is ever silently discarded.
9. **Shortcut focus behaviour from full screen** is a verification task in phase 0 (see `0-walking-skeleton.md`); this phase follows its result.
10. **Rehearse-setlist run (from phase 3 round 2):** a rehearsal mode that runs a setlist through the live view without creating a show or gig-log entry. Implication: the show-state machine gets a `rehearsal` flavor that writes nothing.

## Open questions

None open.
