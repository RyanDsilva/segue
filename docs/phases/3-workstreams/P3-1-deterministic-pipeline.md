# P3-1 - Deterministic paste pipeline in Core

Wave 1. Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 3, 6.1, 14). Rulings: `docs/release/decisions.md` R61-R79 (R63, R76); `docs/decisions.md` Language section (lyric preservation, no transliteration) and Phase 1 build rulings (strict chord parsing: "Do" is never a chord).

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

A pure, platform-neutral pipeline that turns any messy paste, `.txt` or `.crd` into a valid ChordPro song with no model at all, and exposes the blocks, hints and "open questions" (unheaded blocks, missing metadata, unknown lines) that a model may later refine. The deterministic result must be good enough to accept on its own.

## Deliverables

New SegueCore module **`Ingest`** (add to `Packages/SegueCore/Package.swift`, depends on ChordPro, MusicTheory, Library, Support):

1. **Normalizer:** CRLF/CR -> LF, tabs -> spaces (tab stops of 8 unless the line is tab notation), NBSP and zero-width chars, HTML entities and tag residue, smart quotes only in non-lyric lines, trailing whitespace; junk-line removal (ratings, "Tabbed by", nav/ads, "Print", comment sections) by a rule table with tests. Never alters a lyric character beyond whitespace.
2. **FormatDetector:** whole-text format (ChordPro / chords-over-lyrics / bare lyrics / mixed) and per-line class (chordLine, lyricLine, headerLine, directive, tab, blank, unknown). Chord line = most tokens parse as chords (strict MusicTheory) and none is on the **stop list** (romanized Hindi + English common words: Main, Bas, Do, Hai, Na, Tu, Me, A, Am-in-lyric context, ...; the list is data with its own tests). Header detection: `[Verse]`, `Chorus:`, `(Chorus)`, `V1/CH/BR`, `Verse 1:`, `Mukhda:` (-> chorus hint), `Antara N:` (-> verse hint), `x2`/`(x2)` repeat marks.
3. **Segmenter + hints** (port the spike's `SpikeCore/Segmenter.swift` behaviour): blocks on blank lines, a lone header merged into the next block; hints per block: header label, "same lyrics as block N" (normalised comparison), chords only, guitar tab, no chords (when the sheet has chords elsewhere).
4. **Converter:** chords-over-lyrics -> ChordPro by column alignment (chord at col N inserted before the lyric char at col N; chords past the line end appended); headers -> `{start_of_<kind>: <original header text>}`; unheaded blocks -> `{start_of_verse}` placeholders flagged "unlabelled"; tabs -> `{start_of_tab}`; inline ChordPro passes through untouched.
5. **Validator:** every chord token parses; collects unknown lines and unparseable tokens for the review sheet.
6. **MetadataExtractor:** `{title}`/`{artist}`/`{key}`/`{capo}`/`{tempo}`, "Title - Artist" / "Title by Artist" header lines, chord-site lines (`Singer: | Music: | Lyrics:`), `Key: G`, `Scale: Am`, `Capo 2`/`Capo: 2nd fret`. Also picks the **metadata candidates** for a model (top/bottom chord-free blocks + the chord list), or none.
7. **LyricGuard:** lyric token sequence comparison between the converter output and any refined document; reports the first differing block.
8. **KeyInference:** stated key wins; else `KeyDetector` (phase 1); expose `isAmbiguous` + top-two so P3-2 can accept a model key only then.
9. **`.crd` reader:** `.crd` is usually chords-over-lyrics or ChordPro-ish text; route it through the detector like `.txt`. (Adding `crd` to `SongFileTypes.importExtensions` is P3-4's.)
10. **`IngestPipeline`**: `func ingest(_ text: String, origin: IngestOrigin) -> IngestResult` with the deterministic `SongDocument` text, blocks + hints, the refinement questions (`unheadedBlocks`, `metadataCandidates`, `unknownLines`), diagnostics for the review sheet, and an `isAlreadyChordPro` flag (A29: such files skip review). P3-2 adds the refinement-merge step; leave a clear seam (`apply(_ refinements: Refinements) -> IngestResult` signature agreed in this doc: labels by block index, metadata fields, line classes by line index).

## Fixtures

`Packages/SegueCore/Tests/Fixtures/paste/`: **30+ original pastes** (no copyrighted lyrics; write new ones), **8+ romanized Hindi**, each `<id>.txt` + expected deterministic `<id>.cho`. Start from the 20 spike fixtures in `research/phase3-spikes/fixtures/` (original text; E07 no title block and H07 Hindi-dominant stay as permanent regression cases) and add: CRLF + BOM, Windows-1252 quotes, `.crd` samples (2+), capo notes, `x2` repeats, inline ChordPro mixed with chords-over-lyrics, a 40-block sheet (over FM budget), a sheet with only a tab, lyric lines full of chord-like words ("Main Am bas Do pal"), a paste with a `{title}` but junk around it. Gold section labels and metadata for the eval target go in a `gold.json` next to them (same shape as the spike's `gold.py`).

## Tests

Integration: each fixture -> `IngestPipeline` -> `ChordProParser` round trip -> equals expected `.cho`; zero chord loss (every chord token in the source appears in order in the output); zero lyric change (LyricGuard against the raw lyric lines). Unit tests only for chord-line classification and column alignment edge cases. Suites: `IngestFixtureTests`, `IngestClassificationTests`.

## Files owned

`Packages/SegueCore/Sources/Ingest/**`, `Packages/SegueCore/Tests/IngestTests/**`, `Packages/SegueCore/Tests/Fixtures/paste/**`, the `Ingest` target lines in `Packages/SegueCore/Package.swift`.

## Acceptance

All fixtures pass with no provider; deterministic label accuracy on the gold set reported (spike baseline: 72% of all blocks, 100% of headed blocks); `make quick` + `make gate` green.
