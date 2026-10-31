# Phase 8 workstreams

From the 2026-10-30 review round. Rulings: [`docs/release/decisions.md`](../../release/decisions.md), **R147-R167** (the last entries in that file). Each spec below is standalone; its "Closed questions" section lists the R158 (and, for P8-4b, R161; for P8-4b and P8-6, R162) answers it is built on. P8-1 to P8-6 have no open questions; **P8-7 has open questions (its section 21) to close before P8-7a starts.**

## Specs

- [P8-1 - Fix round](P8-1-fix-round.md): pedal safety, crash class, robustness, the near-duplicate import warning (a title, artist and content similarity score), and custom section names offered again in the editor (R154, R159).
- [P8-2 - Stage map and passes](P8-2-stage-map-and-passes.md): every repeat written out on stage, the section map, per-pass show modes, section jump and rehearsal loop, metronome pips above the footer, single-song sessions (R147-R151).
- [P8-3 - Arrangement sequence strip](P8-3-arrangement-sequence-strip.md): the Arrange Sections sheet rebuilt as a lane of pass chips, with "Rehearse this" playing the slot as arranged (R149, R156).
- [P8-4 - Bass](P8-4-bass.md): P8-4a, the profile, the bass-note view for anyone, Nashville roots, the stage mini neck and the "Bass chart" PDF option; P8-4b, the editor fretboard strip and walk-ups: ranked candidates with passing notes from the departing chord, a per-song feel, picks saved in the sidecar (schema 5) and shown on stage, beats from bar lines or `{time}`, and a golden-corpus plus property-test evaluation, with walk-ups judged by ear in P8-6a (R152, R160, R161, R162).
- [P8-5 - Set composer](P8-5-set-composer.md): type a set into a text row at the end of the set list, with short-word romanized Hindi tolerance in `RomanNormalizer` (R153, R157).
- [P8-6 - Audio](P8-6-audio.md): one shared audio engine with bass and chord samplers beside the rehearsal click; hear a chord at sounding pitch, audition and pick walk-ups (A/B), and a play-along loop (bass, chords, click) in the editor, library and Rehearsal, never Live; Settings > Audio with an output picker and a USB note; the sound bank picked by a listening A/B; Ryan's by-ear walk-up check. Three sessions, P8-6a/b/c (R161, R162). Its play-along timing is amended by P8-7: `PlayAlongTimeline` is a slice of P8-7a's `SongTimeline` (R167).
- [P8-7 - Time model and bass fills](P8-7-time-model-and-fills.md): one `SongTimeline` layered over the `.cho` (rule, chart marks including grids and mid-song `{key}` / `{time}` / `{tempo}`, user corrections with `ticks` and `push`, tap capture as an input) that walk-ups, play-along and fills all read, fixing the first-`{key}`-only bug; the chord-length lane, Tap Timing with review, the "looks like a key change" chip and explicit directive inserts; instrument-neutral `Part`s in sidecar schema 6; `Fill.candidates` (four plus More, one per corpus pattern family, templates from the fill corpus, a per-song scale); the fill editor (click then shift-click, A/B audition, fretboard + step grid or piano roll, mini tab); fills on stage as names or tab with `t`, the mini neck's fill path, and the bass chart PDF hook. Six sessions, P8-7a-f (R166, R167). Amends P8-4b (its section 8.14) and P8-6 (section 7).

## Build order and dependencies (R155, R161, R167)

All of Phase 8 ships **before the v0.5 submission**.

1. **P8-1** first.
2. **P8-2 -> P8-3**: P8-3 consumes P8-2's pass model and shared stage request, and starts once P8-2's model and layout steps have landed.
3. **P8-4a** and **P8-5** in parallel (with each other and with P8-2 / P8-3), after P8-1. P8-4a's stage-layout step waits for P8-2's layout step.
4. **P8-4b -> P8-6**: P8-4b starts after P8-4a has landed (and after P8-2's layout step, for its stage hook on the played passes). P8-6a starts after P8-4b (it builds on `WalkUp.candidates`, the pick storage and the walk-up popover); P8-6b (play-along) follows P8-6a and needs P8-2's passes and loop; P8-6c (output routing) follows P8-6a and may run beside P8-6b.
5. **P8-7** (R167 Q15, all before v0.5): **P8-7a** (time core) follows P8-4b and **must land before P8-6b** (it may run beside P8-6a); **P8-7b** (timing UI, tap capture) follows P8-6b, whose lane it extends; **P8-7c** (parts, generator) follows P8-7a **and the fill corpus research** (`docs/research/phase8-fill-corpus.md` and its `fill-corpus.json`, R167 Q16); **P8-7d** (fill editor) follows P8-7c, P8-6a and P8-7b; **P8-7e** (stage, PDF hook) follows P8-7d; **P8-7f** (the one E2E test, guide pages, Ryan's by-ear fill check) closes it.

**Phase 4 PDF export first (R161):** P8-4a's "Bass chart" PDF step (P8-4 section 7.4, step 3c) needs the phase 4 PDF export ([`docs/phases/4-export.md`](../4-export.md)) to be built first. If it is not built when P8-4a reaches that step, the step goes back to the orchestrator and the toggle moves into the phase 4 build.

The R160 research is done, and so is the R166 time-model research (`docs/research/phase8-time-model-and-fills.md`, closed by R167, feeding P8-7); the fill corpus research (R167 Q16) is in progress and blocks P8-7c. Earlier: [`docs/research/phase8-bass-patterns.md`](../../research/phase8-bass-patterns.md) feeds P8-4b and [`docs/research/phase8-audio-engine.md`](../../research/phase8-audio-engine.md) feeds P8-6; R161 closed their open questions, and R162 closed the P8-4b and P8-6 spec questions.

```
P8-1 ─┬─> P8-2 ──> P8-3
      │     └─(layout step)─> P8-4a step 2, P8-4b stage hook
      ├─> P8-4a ──> P8-4b ──> P8-6a ─┬─> P8-6b (also needs P8-2 and P8-7a)
      │               │              └─> P8-6c
      │               └─> P8-7a (before P8-6b)
      └─> P8-5  (in parallel with P8-2 / P8-3 / P8-4a)
P8-6b ────────────────> P8-7b ─┐
fill corpus + P8-7a ──> P8-7c ─┼─> P8-7d ──> P8-7e ──> P8-7f
P8-6a ─────────────────────────┘
phase 4 PDF export ──> P8-4a step 3c (bass chart PDF; now in the phase 4 build), P8-7e's fill PDF hook
```
