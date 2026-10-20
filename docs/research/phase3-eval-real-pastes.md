# Phase 3: Qwen3-4B and Foundation Models on Ryan's real pastes (P3-A part 2, 2026-10-19)

This is the R64 re-validation of the curated model candidate, `mlx-community/Qwen3-4B-Instruct-2507-4bit` at revision `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`. It runs on 10 real pastes Ryan copied from chord sites: 5 English, 5 romanized Hindi. The pastes, the gold data and the per-song results stay local and gitignored (they name real songs). This doc gives aggregate numbers only. Pastes are numbered P01-P10 in alphabetical order of their local file names (P01-P03, P06 and P07 are Hindi).

## Short answer

- **The >= 90% bar is not met.** The final pipeline with Qwen3-4B gets **86.1%** of section labels right and **7/10** title/artist right. Foundation Models (FM) gets 81.7% and 7/10.
- **The model is not what fails.**
  - All 15 of Qwen3-4B's label misses are on blocks where the gold answer is itself debatable: a section split in two by a blank line, a vocal tag, an un-headed tail. On every unambiguous block the model was asked about, it was right (17/17).
  - The title misses come from the deterministic layer (2) and one model mistake (1).
  - FM shows the same failure pattern, plus language rejections, and is 2-3x slower.
- **Three deterministic fixes would pass the bar on these pastes.** A "continuation" rule in code, the metadata-call skip from the spike, and two header-parsing fixes would bring label accuracy to **92.2%**, measured as a what-if on the same model outputs.
- **Recommendation: lock Qwen3-4B, then fix the pipeline and re-run.** No other candidate (Gemma 4 E2B, Qwen3.5-4B) would fix the measured failures, because they are not model failures. Ryan rules.
- **The title/artist bar is barely tested.** None of the 10 pastes contains a title or artist line: the copies start at the first section. "Correct" therefore only means "nothing invented". The pastes need a few copies that include the site header (e.g. "X Chords by Y") before title/artist can count.

## Setup

- **Pipeline.**
  - The app's real deterministic pipeline, P3-1 `IngestPipeline` as committed at `55d8701`, segments every paste. It decides headed blocks, repeats it already handles, chords-only tab blocks, and metadata/credit blocks.
  - The model is asked to label all blocks. Only its labels for **unheaded placeholder blocks** are used (the P3-2 merge rule). Title and artist come from code when code found them, otherwise from the model.
  - The key rule is: stated key, then the key detector, then a model key only when the detection is ambiguous and the model's key is in the top two.
  - The harness compiles the P3-1 sources directly; `research/phase3-spikes/sync-ingest.sh` pins them to a ref.
- **Final MLX design** (`mlxspike ... split exact ebnf retry cachelimit=512`):
  - a split labels call and metadata call, with the P3-1 hints;
  - a no-free-whitespace EBNF grammar: compact JSON, block indices fixed in order (the model chooses only the label), bounded strings;
  - one whitespace-bias retry on `incompleteOutput`;
  - greedy decoding and `Memory.cacheLimit` of 512 MB.
- **FM**: the spike's final variant (split, exact array count, hints), greedy.
- **Gold.** 115 blocks.
  - **22 blocks are marked ambiguous** and accept 2 labels, for example a verse tail that could be a pre-chorus, or a vocal tag that could be chorus or instrumental. No label was guessed where the song does not decide it.
  - Gold labels follow what the section is, not what the paste's header says. One header-labelled block in P08 (a chord-shape legend under a "[Coda]" header) is gold `other`.
  - No paste writes a title, artist or stated key, except P08, which states a key.
- **Machine.** M1 Pro, 16 GB, with 7 sibling agents building at the same time. **Latencies are upper bounds.**

## Results (P3-1 at 55d8701, metadata call skipped when there are no top/bottom candidate lines)

| | Qwen3-4B (MLX) | FM |
|---|---|---|
| Section labels, all 115 blocks | **86.1%** (EN 85.7, HI 86.5) | 81.7% (EN 76.2, HI 88.5) |
| Blocks decided by code (79) | 98.7% | 98.7% |
| Unheaded blocks left to the model (36) | 58.3% (EN 57.9, HI 58.8) | 44.4% (EN 26.3, HI 64.7) |
| Unheaded blocks that are not ambiguous (17) | **17/17** | 10/17 |
| All blocks, excluding the 22 ambiguous ones | 92/93 (98.9%) | 85/93 |
| Songs with every label right | 4/10 (EN 1, HI 3) | 3/10 |
| Title and artist right | **7/10** (EN 2, HI 5) | 7/10 |
| Key right | 10/10 | 10/10 |
| Call failures | 0 (0 retries needed, no whitespace runaway) | 1 labels call + 4 metadata calls, all `unsupportedLanguageOrLocale` |
| Labels call, p50 / p90 | 5.2 / 8.0 s | 13.6 / 24.1 s |
| Per song (labels + metadata), p50 / p90 | 8.2 / 10.7 s | 18.0 / 31.2 s |
| Peak MLX memory | 3.0 GB | n/a |

Without the metadata skip, Qwen3-4B's title score drops to **0/10**. Shown only a chord list, it copies the chord sequence into `title` on every paste. The spike already recommended skipping the call when there is no top or bottom candidate line (spike section 5.3). The pipeline must also reject a "title" made of chord tokens.

### Failures by kind (Qwen3-4B)

| Kind | Blocks | Where | Owner |
|---|---|---|---|
| Section fragment after a blank line labelled `other`, `chorus` or `outro` (the paste split one section into two blocks) | 10 | P02, P03 x2, P05 x3, P09 x2, P10 x2 | deterministic: a continuation rule (below), or a "continues Block N" hint |
| Vocal tag or short hook labelled `other` or `instrumental` | 3 | P02 x2, P03 | prompt wording (the "no chords means credits" rule pushes these to `other`) |
| Repeat of the intro labelled `chorus` | 1 | P02 | model; also see the repeat rule below |
| Header with trailing text or an unknown name not parsed (`[Chorus] (play loud)`, `[Harmonies]`), so the block is left to the model | 1 (the model got P04's four right, labelled P05's `other`) | P04 x4, P05 | P3-1 `HeaderParser` |
| Chord-shape legend under a section header taken as a section | 1 (code) | P08 | P3-1 metadata roles |
| Code title is a fret or tuning line (`G 3-5-5-4-3-3`, `E-A-D-G-B-e`) | 2 titles | P04, P08 | P3-1 `MetadataExtractor` |
| Model title is a capo line | 1 title | P05 | model; a code filter for capo/key/tuning lines |

FM additionally rejected 1 English labels call and 4 metadata calls with `unsupportedLanguageOrLocale`, three of them on chord-only metadata prompts. It also labelled two chord-legend blocks `intro` and a chords-only turnaround `chorus`.

### Variants (same model outputs, re-merged)

| Variant | Qwen3-4B labels | FM labels |
|---|---|---|
| As landed (55d8701) | 86.1% | 81.7% |
| + the "repeated block -> chorus" rule in progress (P3-2, working tree) | 87.0% (EN 85.7, HI 88.5) | 84.3% |
| + a continuation rule (what-if) | **92.2%** (EN 92.1, HI 92.3) | 89.6% |
| + both | 92.2% (EN 88.9, HI 96.2) | 91.3% |

- **The repeat rule** fixes one block, but it also labels as `chorus` two blocks that repeat an intro or a pre-chorus fragment (P02, P09). The rule should copy the label of the block being repeated when that block's label is known, and use `chorus` only when it is not.
- **The continuation rule** (what-if, implemented only in the scorer) works like this. An unheaded block with no repeat, chords-only or tab hint, directly after a block code already decided, takes that block's label. It runs in code before the model is asked. It leaves only 4-18 blocks to the model.
  - It regresses where a previous header was misparsed (P04's `[Bridge] (play loud)` / `[Verse 3] (...)` blocks, and the blocks after P08's legend). So it needs the header fixes first.

## Recommendation

1. **Lock Qwen3-4B-Instruct-2507 4-bit (R64), pending Ryan's ruling.** On the blocks a model can actually decide, it was 17/17. It was 2-3x faster than FM, made 0 call failures and needed 0 retries, and handled Hinglish as well as English. FM's language rejections and lower accuracy are unchanged from the spike. Swapping in another candidate cannot fix fragment, header or metadata failures.
2. **Before the bar is re-checked, the deterministic pipeline needs these fixes** (P3-1 / P3-2 owners):
   - parse headers with trailing text and unknown bracketed names (`[Chorus] (play loud)`, `[Harmonies]`, `[Coda]` followed by a chord legend);
   - stop taking fret, tuning and capo lines as titles;
   - skip the metadata call without top/bottom candidate lines, and reject chord-token or capo titles;
   - make the repeat rule copy the source block's label;
   - add a continuation rule, or a "continues Block N" hint.
   
   Then re-run `research/phase3-eval/run.sh`.
3. **Ask Ryan for 3-5 more pastes that include the site's title/artist header.** This lets title/artist be measured rather than assumed.
4. **Prompt.** Soften "a block with no chords in a sheet that has chords is usually title, credits or website text: other". The model applies it to sung tags.

## Reproduce

`research/phase3-eval/run.sh [ingest-ref]`. It syncs the P3-1 sources, builds `fmspike` and `mlxspike`, writes `results/ingest-<ref>.json` (code decisions, no lyric text) and the two `.jsonl` result files, then scores them. Scorer flags:

| Flag | What it does |
|---|---|
| `--gold` | the gold data file |
| `--ingest` | the code decisions to merge with the model output |
| `--variant` | a second code dump whose labels override |
| `--skip-meta` | treat the metadata call as skipped when there are no candidate lines |
| `--continuation` | apply the what-if continuation rule |
