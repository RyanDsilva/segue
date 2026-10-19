# P3-5 - Length entry: the "Time it" timer, the length field and Welcome lengths

Wave 2. **Rescoped 2026-10-19 by R91** (supersedes R70): no learned lengths, no estimates, no timing samples. What is left is the small, reusable length-entry piece that the song card (P3-10) and the missing-lengths list (P3-12) embed. Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 8 and 16.0.1). Rulings: `docs/release/decisions.md` R91, R78, R80, R17 (autosave); the phase 2 rule "Unknown song length: ... no made-up default" in `docs/decisions.md` stands again. Existing code: `SongDocument+Derived.swift` (`{duration}` parsing: `ss`, `mm:ss`, `h:mm:ss`, and `valueProblem`), `Editing/DocumentEditor.swift` (`EditOperation.setDirective`), `Setlists/SetlistTiming.swift` (unchanged phase 2 notation), `Library/WelcomeSeed.swift`.

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

A song's length is typed once as `mm:ss` or timed with one click, and lands in the song's `{duration}` directive. Nothing else feeds a length.

## Deliverables

1. **Length value type** (SegueCore, next to the existing `{duration}` parsing; extend, do not duplicate): parse `ss`, `mm:ss`, `h:mm:ss` and the forgiving inputs a person types (`4.05` and `4 05` -> 4:05; `245` stays 245 s, as today); format back as `m:ss` / `h:mm:ss`; reject zero and negative values with a reason string the field shows.
2. **`TimeItModel`** (`Packages/SegueUI/Sources/SegueUI/SongCard/TimeItModel.swift`, new): one run at a time across the app, keyed to a song id; Start, elapsed time (an injectable clock), Stop -> returns the elapsed seconds rounded to the nearest second, Cancel. Switching the selected song keeps a run alive; the run ends only by Stop, Cancel (Esc) or the song being deleted. Nothing is written to disk by the model.
3. **Length field + Time it control** (`SongCard/LengthField.swift`, new): an `mm:ss` text field with the value type's validation, and a "Time it" button that becomes Stop with a live elapsed time. Commit (Return, focus out, or Stop) calls a closure the host supplies (`(TimeInterval?) -> Void`; nil = clear). P3-10 wires it to `EditOperation.setDirective(.duration, ...)` as one undoable edit; P3-12 reuses it in the missing-lengths popover. Accessibility identifiers `segue.songCard.length` and `segue.songCard.timeIt`; VoiceOver announces start, stop and the written length.
4. **Analytics:** call `featureUsed(.timeIt)` on Stop once P3-4 has defined it; if P3-4 has not landed, leave one call site marked for it and tell the orchestrator.
5. **Welcome lengths (R78):** the four Welcome songs already carry `{duration}` (Ferry Lights 4:40, Kettle On 3:05, Kitaabon Wali Gali 4:05, Soundcheck at Seven 3:20): add a test that pins it, and note in the hand-off that WS5's screenshot-only songs need `{duration}` too when they land.
6. **Nothing learned:** confirm `SetlistTiming` and `SetlistEntryDisplay` still use `{duration}` only and the phase 2 notation (`--:--`, `≥38:20 + 2 unknown`); make no change there except comments that mention estimates. Do not add `DurationSample.Source.timer` files, index columns or a `Durations` module.

## Not yours

The song card layout and its other fields (P3-10); the missing-lengths popover, changeover and break totals (P3-12).

## Tests

In-process SegueUI integration test: the field commits through a real `DocumentEditor` on a temp library song and the reloaded `.cho` has the expected `{duration}`; Time it with a scripted clock writes 4:05; Esc writes nothing; clearing removes the directive. Unit tests only for the forgiving parser. Suites: `LengthEntryTests`, `WelcomeSeedTests` (extend). No new XCUITest here (P3-10's E2E covers the card).

## Files owned

`Packages/SegueUI/Sources/SegueUI/SongCard/TimeItModel.swift`, `SongCard/LengthField.swift`, their tests, the length value type additions in SegueCore (`ChordPro/` or `Library/` next to the existing parser; additive only), the Welcome pin test.

## Acceptance

Typing `4:05` or timing a run writes `{duration: 4:05}` through the editor path with one undo step; nothing else in the app produces a length; `make quick` + `make gate` green.
