# P3-5 - Durations: learned lengths, per-song timer, flagged estimates, Welcome lengths

Wave 1. Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 8, 14, 16.1 questions 1, 2, 5, 6). Rulings: `docs/release/decisions.md` R70 (supersedes the phase 2 "unknown song length: never made up" ruling in `docs/decisions.md`), R78. Existing code (phase 2 hooks): `Shows/DurationSamples.swift` (`DurationSample.Source.timer` reserved, `RehearsalTimingStore`, `loadAll`), `Shows/ShowRecord.swift` (`playedSongs`), `Setlists/SetlistTiming.swift` (`SongLengthSource.directive/.learned`, `≥`/`+ N unknown` notation), `SegueUI/Setlists/SetlistEntryDisplay.swift` (directive lengths only today), `Support/LibraryRoot.swift`, `Library/SongIndex*.swift`.

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

Every song's set length comes from the best source available - learned from real plays, else its `{duration}`, else an estimate from tempo and line count that is always visibly marked - and stays unknown when none exists.

## Before you start

Open question 1 (storage) and 2 (clearing samples) are for Ryan. Build to the R70 default (derived, no duplicate store) which is recommendation 1a. For clearing, build nothing until Ryan rules on question 2; leave the inspector without a Clear button. Questions 5 and 6: build to recommendations 5a and 6a.

## Deliverables

1. **Timer samples:** `TimerTimingStore` writes `timings/<ulid>.timer.json` (versioned JSON, `schemaVersion: 1`, one run per file, `source: timer`); `LibraryRoot.timerSuffix` (`LibraryRoot.swift` is shared with P3-6: additive edits only). Samples under 30 s are discarded.
2. **Learned-length derivation** (new SegueCore module `Durations`, depends on Shows, Setlists, Library): gathers show samples (`ShowRecord.playedSongs`, requests and "Play now" included), rehearsal and timer samples; outlier rule for shows (under 40% or over 200% of the current learned value); median of the last 10 retained once >= 2 samples. Results go into the **rebuildable index** (new columns: learned seconds, sample count; index rebuild path updated; incremental refresh when a show ends, a rehearsal sample lands or a timer stops).
3. **Estimator:** `LengthEstimator` per recommendation 6a (2 bars per lyric line at `{time}`, 4/4 default, repeats counted, clamped 1:30-8:00), only when `{tempo}` exists; constants in one place.
4. **Resolver:** `EffectiveLength` = learned -> directive -> estimate -> unknown; `SongLengthSource` gains `.estimated`; `SetlistTiming` gains an estimated count and notation: estimates render `~3:40`, totals `~41:20, incl. 3 estimated`, combined with the existing unknown notation (`≥38:20 + 2 unknown, incl. 3 estimated`). Update the phase 2 notation tests deliberately, and the comment in `SetlistEntryDisplay.swift`.
5. **UI:** a Start/Stop run-through timer in the song view (one click to start, one to stop, visible elapsed time, Esc cancels; `featureUsed(.runThroughTimer)` from P3-4's vocabulary once it exists); the inspector shows learned length, sample count and source mix; the builder, stage footer and setlist rows show the `~` mark wherever an estimate is used.
6. **Welcome lengths (R78):** the four Welcome songs already carry `{duration}` (4:40, 3:05, 4:05, 3:20): add a test that pins it, and note in the hand-off that WS5's screenshot-only songs need `{duration}` too when they land.

## Tests

Integration: recorded show/rehearsal/timer fixture files (with outliers) in a temp library -> real store + index -> learned medians; precedence; estimate only with tempo; unknown without; notation strings; index rebuild reproduces the same values; timer E2E `SegueTimerE2ETests` (start/stop twice -> inspector shows a learned length). Suites: `LearnedDurationTests`, `SetlistTimingTests`.

## Files owned

`Packages/SegueCore/Sources/Durations/**` + its target lines in `Package.swift`, `Shows/DurationSamples.swift` (timer store additions), `Setlists/SetlistTiming.swift`, `Library/SongIndex*.swift` length columns, `LibraryRoot.swift` (shared, additive), `SegueUI/Setlists/SetlistEntryDisplay.swift`, the song view timer and inspector length rows, `UITests/SegueTimerE2ETests.swift`.

## Acceptance

Two timed plays make the learned value win; estimates are never shown without `~` and totals count them; songs with neither stay unknown; `make quick` + `make gate` green.
