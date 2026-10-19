# P3-7 - Set assistant and natural-language picks

Wave 3 (after P3-2, P3-6 and P3-12). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 7, 8, 9, 16.0.5, 16.1 question 24). Rulings: `docs/release/decisions.md` R65 (lexicon first, async model chips, no model on stage), R71 (no energy; shape with tags, length, key flow, repeat avoidance), **R92** (tempo = explicit filter only; opener/closer shaping only when asked, via tags; async pass = curated MLX if installed, else FM, as suggested chips), R93 (AI toggle), R94 (load per request), R91 (lengths = `{duration}` only), R84-R86 (Arrange mode, break rows, changeover), R89 (no ⌘K palette), R102 (no repeats in a show: P3-15 owns it), R39 (design directions); `docs/decisions.md` Phase 2 (Learning / Ready / Pro) and Phase 3 (recently-played penalty global, not venue-aware). Measurements: `docs/research/phase3-spikes.md` section 4 (the v3 split: code parses numbers/keys, the model maps fuzzy words only).

**Invariant from Ryan's walkthrough:** a song appears **at most once per setlist**, enforced in the setlist model (commit 1d027df). The packer and Rebuild assume it; it is never a score term. On stage, R102 (no repeats within a show) is P3-15's.

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Before you start

Questions 3, 4 and 14 are ruled (R92). Question 24 (songs with no length when packing to a duration) is open and blocks the packer's unknown-length handling until Ryan rules (recommendation a: leave them out and say "N songs left out: no length", a button opening P3-12's missing-lengths list). The builder's Pick/Arrange UI, break rows and missing-lengths list are P3-12's: the assistant plugs into the builder, it does not redesign it. No ⌘K palette (R89).

## Deliverables

1. **SegueCore module `SetAssistant`:** `SetRequest` (target minutes, count, min proficiency, include/exclude tags, keys, tempo filter (R92: a filter only, never a score), smart filter inputs, slot tag preferences only when the request names a slot (R92), avoid-recent toggle), `SetRequestLexicon` (numbers, durations, keys, BPM, "know well"/"know cold", library tag names fold- and romanization-tolerant via `RomanNormalizer`, smart filter names, slot phrases; reports leftover words), `Scorer` (proficiency, tag match, recently-played decay, slot fit, key flow; weights in config; **per-song breakdown summing to the total**), `Packer` (greedy to target +/- 3 min, local swaps penalising same key back to back and adjacent capo/tuning changes, small related-key bonus; lengths = each song's `{duration}` plus the setlist's changeover (R86, P3-12's `SetlistTiming`); unknown lengths per question 24; never a duplicate song), `SetBuilder` (injectable seed; locks; Rebuild around locked songs and existing break rows, which stay in place).
2. **Async model pass:** `SetRequestTask` (P3-2) with the leftover words and the library's actual tags as `.anyOf`; runs after 0.8 s idle or Return, cancelled on change; results as dashed **suggested chips**. Provider (R92): curated MLX if installed, else FM, through P3-2's router; loaded per request (R94); skipped entirely when the AI toggle is off (R93). Never blocks; no model during a show.
3. **UI** (`Packages/SegueUI/Sources/SegueUI/Assistant/`): step 0 is 2-3 design directions for the request field + chips + result presentation inside the setlist builder (Ryan picks, R39 style). Then: request field, chips (edit/remove, suggested vs confirmed), Build -> draft setlist in the builder's Arrange mode (P3-12), lock toggles, Rebuild, breakdown popover reachable by hover, keyboard and VoiceOver. Emit `Segue.AI.assistantUsed` (vocabulary from P3-4).
4. **NL picks:** the library search field gains lexicon chips (instant) and async suggested chips; the stage quick search gets lexicon + text search only (no model, R65) through a hook in `QuickSearchModel` (yours); refusing a song already played or upcoming in the show is P3-15's (R102).

## Tests

Integration: seeded 300-song fixture library (tags, proficiency, tempo, keys, `{duration}` lengths with some unknown, gig history) -> lexicon + `ScriptedProvider` chips -> builder -> draft setlist written and reloaded. Property checks over many seeds: within tolerance, filters respected, Learning excluded by default, **no song twice**, locks and break rows kept, changeover counted, same seed same output, breakdown sums to total, < 2 s. Lexicon unit tests on the spike's 15 set prompts plus Hinglish requests ("kuch romantic gaane, 25 minute"). E2E `SegueAssistantE2ETests`: "30 min set, songs I know well" -> chips show Ready+ -> set within tolerance -> breakdown reachable. Suites: `SetAssistantTests`, `SetRequestLexiconTests`.

## Files owned

`Packages/SegueCore/Sources/SetAssistant/**` + target lines, `Packages/SegueUI/Sources/SegueUI/Assistant/**`, the assistant entry in the setlist builder views, library search chip additions, stage quick-search lexicon hook, `UITests/SegueAssistantE2ETests.swift`.

## Acceptance

A one-line request builds a set within tolerance in under 2 s with visible breakdowns and no repeated song; lexicon chips are instant; model chips are async and optional; nothing loads a model during a show; `make quick` + `make gate` green.
