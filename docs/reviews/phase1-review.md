# Phase 1 adversarial review (2026-10-17)

Independent read-only review of 7ac80ca..9a522ab, findings reproduced with probe tests. Phase 0 review fixes re-verified (all hold; #10 partially - see 5).

| # | Sev | Finding | Fix |
|---|---|---|---|
| 1 | high | Chord inside a grapheme cluster (Devanagari conjunct, combining mark, ZWJ): canvas and model count lyric offsets differently; edits land on the wrong character and can delete lyric text | one offset definition end to end (Character offsets into joined lyrics, or UTF-16 throughout); Hindi/combining-mark tests driving editLyrics from RenderLine offsets |
| 2 | high | Transpose by n and back does not restore spelling for out-of-key chords (Ab in C -> G#); non-canonical keys renamed | ruling: out-of-key chords keep the author's accidental family; keys keep their spelling; property test 12 keys x 22 intervals with borrowed chords |
| 3 | med | Chord popover commit with unchanged text respells the source chord | no-op when text unchanged; inverse-map only edited text |
| 4 | low | Visual lyric edits can turn a lyric line into a comment/directive or create a chord from typed `[Am]` | reject (beep) or escape |
| 5 | low | `originalSource` not reset after a save that keeps the editor open; editor not locked while saving | reset baseline on save; lock or document |
| 6 | nit | Test instrumentation elements visible to VoiceOver in production | gate on UI-testing flag |
| - | flake | EditorPerformanceTests wall-clock p95 < 16 ms in debug unit tests; AppHardeningTests busy-wait without timeout | generous guard / serial suite; bounded wait |
