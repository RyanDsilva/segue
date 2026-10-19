# P3-14 - Visual metronome on stage

Wave 3 (new, 2026-10-19; after P3-12's live-side break rows). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 16.0.7, 14, and 16.1 question 25). Rulings: `docs/release/decisions.md` R90 (a small corner overlay on stage pulsing at the song's tempo and time signature; toggled per show and by a key; **sound only in rehearsal mode, never during a show**), R45 (page-turner keys), R39 (design directions), R79 (accessibility walk); WS2b TipKit rule (no tips during a show).

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Before you start

**Question 25 blocks step 1's details** until Ryan rules. Recommendation a: a song without `{tempo}` hides the overlay; the per-show toggle remembers the last choice as the next show's default; rehearsal sound is off by default behind its own toggle.

## Goal

On stage, a quiet pulse in a corner shows the current song's beat so the band can count in and hold tempo, without ever making a sound in a gig.

## Existing code

`SegueCore/Shows/LiveCommand.swift`, `InputBindings.swift` (`defaults`: `m` is free today; `/`, `a`, `[`, `]`, `r`, `q`, `x`, `s`, `c`, `o`, `?` are taken), `KeyHelp.swift`, `LiveSettings.swift`, `ShowTypes.swift` (session kind gig vs rehearsal), `SegueUI/Live/LiveView.swift`, `StageChrome.swift`, `StagePanels.swift`, `StageSongBody.swift`, `KeysOverlay.swift` (the `?` overlay), `PreShowChecklist*.swift`, `LiveSession*.swift`, `Settings/LiveSettingsView.swift` + `LiveSettingsStore.swift`. Song `{tempo}` and `{time}` via `SongDocument+Derived`.

## Steps

0. **Design directions (R39 style):** 2-3 renders of the overlay (corner, size, beat dots vs a single pulse, accent on beat 1, light and dark stage themes, the Reduce Motion variant) placed clear of the stage chrome, footer, sidebar and cue callouts. Ryan picks before step 2.
1. **Beat model (Core or SegueUI, pure):** given tempo (BPM) and time signature (`{time}`, 4/4 when absent), an injectable clock and a song-start instant, produce the current beat index and phase; restart on song change; handle tempo changes when the song changes; no drift over a 10-minute song (computed from the start instant, never accumulated). Unit tests are justified here (pure timing logic).
2. **Overlay:** a small corner view on stage pulsing per beat with beat 1 accented; Reduce Motion shows a stepping beat counter instead; hidden while the stage shows a break interstitial (P3-12) or a song without a tempo (question 25); never steals key focus; never on the main thread's critical path (drive it from the display link / `TimelineView`, no timers that block).
3. **Toggles:** a per-show toggle in the pre-show checklist / start sheet; `LiveCommand.toggleMetronome` with default key **`M`** (verify it is still free in `InputBindings.defaults` and the bindings clash checks), rebindable like other live commands, listed in the `?` overlay; a Settings > Live default if question 25 is ruled (a).
4. **Rehearsal sound:** only when the session kind is rehearsal: a click per beat (accent on 1) behind its own toggle (default off) and a key (`⇧M`, verify free). In a gig the audio path is **not created at all** (no audio engine, no player), so no state can make it sound; assert it in a test. The click respects the system output and stops immediately on pause, song change and End.
5. **Menus:** if a menu item is wanted for the toggle (Live menu), ask P3-4 (the wave 3 owner of `MenuShortcuts.swift`) to add it; do not edit that file yourself.

## Tests

Beat model unit tests (tempo, 3/4, 6/8, song change, no drift with a scripted clock). In-process SegueUI tests: the overlay appears only with a tempo and the toggle on; `M` toggles; a gig session never constructs the audio path; a rehearsal with sound on schedules clicks on the scripted clock. Suites: `MetronomeBeatTests`, `StageMetronomeTests`. E2E `SegueMetronomeE2ETests`: start a rehearsal of the Welcome Set with the metronome on, see the overlay, press `M`, it hides.

## Files owned

New metronome files (beat model, overlay view, rehearsal click player), `LiveCommand.swift` + `InputBindings.swift` defaults + `KeyHelp.swift` (the new command only), the overlay slot in `LiveView.swift`/`StageChrome.swift`, the toggle row in `PreShowChecklistView.swift`, `Settings/LiveSettingsView.swift` + `LiveSettingsStore.swift` (only if question 25 adds a default), `UITests/SegueMetronomeE2ETests.swift`, the tests above.

## Acceptance

The overlay pulses at the song's tempo and time signature, toggles per show and by `M`, respects Reduce Motion, never sounds during a show (structurally), and clicks only in a rehearsal when asked; the live view never stalls; `make quick` + `make gate` green.
