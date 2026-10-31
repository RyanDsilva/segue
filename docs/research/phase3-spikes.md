# Phase 3 spikes: Foundation Models vs MLX (2026-10-17)

Spikes for phase 3 tasks 2a (FM on romanized Hindi) and 6a (curated MLX model), run on the real
hardware with a throwaway Swift package. Inputs: `docs/phases/3-ai-entry-and-assistant.md`,
`docs/research/phase3-ai.md`, `docs/decisions.md` (Phase 3 research outcomes: min macOS 26; Hindi tries
FM first and falls back to MLX).

**Short answer**

- FM works on this Mac and needs no setup, but it is the weaker and slower provider here: 72% accuracy
  on blocks without a header vs 98% for Qwen3-4B, and a median of 18 s per song vs 6.5 s. It also
  rejects 2 of 8 Hinglish songs before generating anything.
- **Curated MLX model: `mlx-community/Qwen3-4B-Instruct-2507-4bit`** (Apache-2.0, 2.28 GB, about
  3 GB peak). It is 98% on section labels, 19/19 on title and artist, and 100% on every Hinglish song
  it completed.
- The set-request parser does not reach usable quality on FM with any schema tried (47-65% of fields
  right). Numbers and keys must be parsed by code. Gemma 4 E2B is the best model at the remaining
  fuzzy fields, at 95%.
- No model meets the spec's "NL pick < 1 s" target on this machine. The pick path must be
  deterministic first.

## 1. Setup

| | |
|---|---|
| Machine | MacBook Pro, Apple M1 Pro, 16 GB, on AC power, Low Power Mode off |
| OS / tools | macOS 26.6.2 (25G83), Xcode 26.6, Swift 6.3.3, MacOSX SDK 26.5 |
| FM | `SystemLanguageModel.default.availability == .available`; Apple Intelligence was already enabled, so **no user action was needed**. `contextSize` read at runtime = **4096** |
| FM supported languages (runtime) | da, de, en (AU/GB), es (419/US), fr (CA), it, ja, ko, nb, nl, pt (PT), sv, tr, vi, zh (HK/TW). **No `hi`** |
| MLX | `ml-explore/mlx-swift-lm` **3.32.3** (latest release, 2026-09-30), `mlx-swift` 0.32.3, `swift-transformers` 1.3.x. Built with `xcodebuild`, because SwiftPM on the CLI does not build the Metal library |
| Constrained decoding | `MLXGuidedGeneration` standalone (`GrammarConstraint(jsonSchema:)` + `GuidedGenerationLoop.run`, greedy argmax). It works on macOS 26; `MLXFoundationModels` needs the 27 SDK and was not used |
| Spike code | `research/phase3-spikes/` (committed; the downloaded models in `models/`, the xcodebuild output in `dd/` and compiled binaries are not, see `.gitignore`): `Spike/` (SwiftPM: `SpikeCore`, `fmspike`, `mlxspike`), `fixtures/` (20 pastes), `gold.py`, `score.py`, `results/*.jsonl` (one JSON line per model call), `fgapp/` (a foreground AppKit latency probe) |

**SDK note.** `tokenCount(for:)` is `@available(macOS 26.4)`, and the spike package had to set its
deployment target to 26.4 to call it. With the app's macOS 26.0 floor, it needs
`if #available(macOS 26.4, *)` and a chars/3 fallback, as `phase3-ai.md` already says.

### Eval set

There are 20 original pastes. All lyrics were written for this spike; no copyrighted songs are used.

- **12 English:** UG-style with `[Verse]` headers, bare chords-over-lyrics, inline ChordPro with
  `{title}`, tabs mixed in, `Verse 1:` with `(x2)`, CRLF with smart quotes and `(Chorus)` headers,
  short unlabelled, long (15 blocks), web junk (nav, ratings, comments), edgy lyrics
  (whiskey/shotgun/"some men die"), `V1/CH/BR` abbreviations, bare lyrics with no chords.
- **8 romanized Hindi:** UG-style with chord-like words ("Main", "Bas", "Do"), bare with no headers,
  inline chords with `Mukhda:`/`Antara 1:`, long (15 blocks), Indian chord-site junk
  (`Singer: | Music: | Lyrics:`), `Scale: Am | Capo` with a tab intro, bare Hinglish lyrics with no
  chords, and code-mixed Hinglish with an English chorus.

Gold data: 133 blocks with labels (intro / verse / prechorus / chorus / bridge / instrumental / outro /
other), plus title, artist and key per song. Some cases accept more than one answer: a tab intro may be
intro or instrumental, and a key may be the relative major or minor.

A deterministic segmenter stands in for the spec's Normalizer and FormatDetector. It splits blocks on
blank lines and merges a lone header into the next block. It also computes per-block hints:
`header says chorus`, `same lyrics as Block 3`, `chords only`, `guitar tab`, and `no chords` (shown
only when the sheet has chords elsewhere). Explicit headers decide the label of 81 of the 133 blocks,
and code gets all 81 right. **The model only matters for the 52 blocks without a header.** That number
is reported as "unheaded acc" below.

The model never outputs lyric text. Label outputs are `{block: Int, label: enum}`, and metadata is
`{title, artist, key: enum}`. Lyric preservation therefore holds by construction, and chord
preservation is not at risk because the model never sees a chord field it could write to.

## 2. Apple Foundation Models

### 2.1 Prompt/schema iterations (20 songs, greedy)

| Variant | Calls ok | Label acc (ok songs) | Unheaded acc | Title ok | Artist ok | Notes |
|---|---|---|---|---|---|---|
| A. One combined call (labels+title+artist+key), `title: String?`, raw blocks | 18/20 | 74.0% | n/a | **1/18** | 4/18 (only songs with no artist) | FM **never fills `Optional` fields** under greedy decoding; block 0 always labelled "intro" |
| B. A + deterministic hints | 18/20 | 80.5% | n/a | 1/18 | 4/18 | |
| **C. Split: labels call + metadata call, non-optional `String` ("" if none), hints** | 18/20 | **90.2%** | 74.5% | 17/18 | 18/18 | Metadata sees only the top/bottom blocks plus the chord list |
| D. C with lyrics masked (`~lyric 3, 6 words~`, same text = same id) | 19/20 | 74.4% | 33.3% | 18/19 | 19/19 | Avoids the language check for labels but loses too much signal. Rejected |
| **E. C + exact array length** (`DynamicGenerationSchema(arrayOf:minimumElements:n,maximumElements:n)`), 3 runs | 54/60 | **89.4%** | **72.3%** | 51/54 | 54/54 | Final FM design. Greedy runs repeat exactly |
| F. E with chunks forced by a 250-token prompt budget (2-5 calls per song) | 19/20 | 82.9% | 54.2% | 18/19 | 19/19 | Chunking costs about 18 points on unheaded blocks |

Stated keys were 12/12 correct in E. Guessed keys default to G, so the spec rule "code-inferred key
wins" is right.

**The array-runaway risk is real.** A one-block probe with a plain `[BlockLabel]` produced block 0, 1,
2, 3, 4... until it hit `maximumResponseTokens` and then threw `decodingFailure`. A Devanagari probe did
the same: Devanagari is *not* rejected by the language check. The first set-request schema (v1) also
filled `keys` with all 28 keys. Pin array lengths with `DynamicGenerationSchema` where the count is
known, and put `.maximumCount` everywhere else.

### 2.2 Errors, guardrails and Hinglish

Across all 446 FM calls in the spike: **0 `guardrailViolation`, 0 `refusal`**, including the edgy E10
lyrics. There were 20 `unsupportedLanguageOrLocale` and 5 `decodingFailure` (runaway arrays in the v1
set-request schema).

| Hinglish song | Labels call | Metadata call |
|---|---|---|
| H01 UG-style, H02 bare, H04 long, H05 site junk, H06 scale/tab, H08 code-mixed | ok | ok |
| H03 `Mukhda:`/`Antara:` + inline chords | **unsupportedLanguageOrLocale** (every run) | ok (sees only "Safar - Kabir Sehgal" plus chords) |
| H07 bare Hinglish lyrics, no chords | **unsupportedLanguageOrLocale** (every run) | **unsupportedLanguageOrLocale** |

- The rejection is **deterministic and cheap**: it is thrown in 3-4 ms, before any generation. Chords
  and English headers seem to dilute the language detector enough for 6 of 8 songs to pass. Songs that
  are mostly Hindi words fail.
- When FM does accept a Hinglish song, quality is lower: 84.1% label accuracy and 53% unheaded vs
  92.4% and 81% for English. Typical misses: bare Hinglish choruses labelled prechorus or verse
  (H02, H05).
- FM never respelled anything, because no lyric text is in its output.
- A Hinglish *set request* ("kuch romantic hindi gaane, 25 minute") was not rejected.

### 2.3 Tokens vs context (`contextSize` = 4096)

| Call | Instructions | Schema | Prompt | Output | Total |
|---|---|---|---|---|---|
| Labels (E) | 204 | 202-204 | 133-949 (mean 491) | 39-209 | max **1,566** (15-block song) |
| Metadata | 99 | 263 | mean 87 | mean 31 | about 480 |
| Set request v3 | 212 | 365 | mean 20 | mean 61 | about 660 |

The largest fixture uses 38% of the window. With the spec's budget formula
(`contextSize - instructions - schema - maxResponse - margin`), a single call fits about 35+ blocks, so
chunking is needed only for unusually long sheets. Chunking measurably hurts quality (variant F), so
route such sheets to MLX rather than chunk them (spec routing rule 2 already allows this).

### 2.4 Latency (the problem)

| Measurement | Result |
|---|---|
| Paste, labels + metadata per song (E, 60 song runs, CLI) | median **18.4 s**, p90 30.3 s, max 69 s |
| Labels call alone | p10 4.9 s, median 11.0 s, p90 17.6 s |
| Same song x8 back to back (CLI) | labels 5.4 s, metadata 7.1 s, very steady |
| Foreground AppKit app (`fgapp`), 6 rounds | metadata 4.2-11.2 s, labels 5.6-27.5 s, set request 4.3-14.5 s |
| Set request v3 (30 calls) | median 4.5 s, p90 7.3 s |
| `prewarm()` 1.5 s before the call | no improvement (median 8.3-14 s) |
| Plain-text bench, 208 output tokens | from 3.3 s (about 63 tok/s, 0.46 s TTFT) to 74 s (about 3 tok/s, 3.5-7 s TTFT) in different runs |

Throughput on this M1 Pro swings by about 20x between runs. Being a foreground app does not help. The
GPU was idle between runs, so the cause is not visible from userspace: it could be scheduling inside
the system inference service or memory pressure on 16 GB. Re-running `fmspike` on a newer or less
loaded Mac would show whether this is specific to this machine. **Design for FM being multi-second
and unpredictable.**

## 3. MLX candidates

Same split design (labels + metadata, hints) and same 20 pastes. The JSON schema is
`JSONEncoder().encode(T.generationSchema)` of the **same `@Generable` types** FM uses, so there is no
separate hand-written schema. On the MLX side the labels schema gets `minItems = maxItems = n` and a
bounded `block` integer (`minimum 0`, `maximum n-1`), with the schema text in the system prompt. Each
model was loaded from local files, ran one warm-up call, and then the timed calls.
`Memory.cacheLimit = 512 MB`.

### 3.1 Licence and size (verified at source today)

Licences were read from the upstream model card `cardData` and the LICENSE file, not the mlx-community
card. Sizes are the summed repo blobs.

| Model (mlx-community 4-bit) | Upstream | Licence | Gated | Download | Language note (upstream card) |
|---|---|---|---|---|---|
| Qwen3-4B-Instruct-2507-4bit | Qwen/Qwen3-4B-Instruct-2507 | Apache-2.0 (LICENSE file is Apache 2.0) | no | **2.28 GB** | multilingual; non-thinking model |
| Qwen3.5-2B-MLX-4bit | Qwen/Qwen3.5-2B | Apache-2.0 | no | 1.75 GB | vision-language model; thinks by default (disabled via `enable_thinking: false`) |
| gemma-4-e2b-it-4bit | google/gemma-4-E2B-it | Apache-2.0 (license_link ai.google.dev/gemma/docs/gemma_4_license) | no | 3.58 GB | "35+ languages, pre-trained on 140+" |
| Phi-4-mini-instruct-4bit | microsoft/Phi-4-mini-instruct | MIT | no | 2.18 GB | Supported-language list has **no Hindi**; card warns "trained primarily on English" |

### 3.2 Paste results (final config: exact count, bounded int, no logit biases)

| Model | Calls ok | Label acc (ok) | Unheaded acc | Title / artist ok | Key ok | Per song (labels + meta), median / p90 | Labels tok/s* | Peak MLX mem | Load (warm disk) |
|---|---|---|---|---|---|---|---|---|---|
| **Qwen3-4B-2507** | **19/20** | **98.4%** (EN 97.5, HI 100) | **97.9%** | **19/19** | 17/19 | 6.5 s / 7.0 s | 27 | 2.98 GB | 0.6 s |
| Gemma 4 E2B | 18/20 | 82.5% (EN 89.1, HI 71.8) | 72.0% | 17/18 | 16/18 | 3.6 s / 4.3 s | 52 | 3.40 GB | 1.6 s |
| Phi-4-mini | 17/20 | 67.4% | 53.1% | 10/17 | 4/17 | 4.5 s / 5.0 s | 31 | 2.98 GB | 0.9 s |
| Qwen3.5-2B | 8/20 | 61.0% | 48.4% | 6/8 | 8/8 | 3.5 s / 3.9 s | 49 | 2.11 GB | 1.1 s |

\* Output tokens divided by call time, including prefill. Warm-up (first call: grammar compile plus
Metal kernels) took 1.2-1.7 s. Steady-state process footprint was 1.7-3.2 GB with `cacheLimit` set.
Without it, phys_footprint grew to **11.6 GB** over 40 calls (MLX buffer cache).

Failures were all `GuidedGenerationError.incompleteOutput`, caused by whitespace runaway inside the
grammar (JSON allows unlimited whitespace): Qwen3-4B on H07 metadata (newlines), Gemma on both 15-block
songs, Qwen3.5-2B on 12/20 (tabs). Turning on `ClosingTokenBias` and `WhitespaceTokenBias` (as
`MLXFoundationModels` does) made it *worse* with an unbounded integer: digit runaway such as
`"block": 71000000...` failed 20/20 for Qwen3-4B. An earlier Qwen3-4B run without exact counts or
bounds scored 97.7% (19/20). Fix: give the grammar no free whitespace (EBNF or compact-JSON grammar),
plus bounded ints and fixed counts, and retry once with a whitespace bias on `incompleteOutput`.

### 3.3 Simulated pipeline accuracy (code labels headed blocks; model labels the rest; failures fall back)

| Pipeline | All 133 blocks | 52 unheaded blocks |
|---|---|---|
| Code only (headers, `verse` placeholder) | 72.2% | 28.8% |
| FM, deterministic fallback | 88.0% | 69.2% |
| FM, then Qwen3-4B on FM failure (current spec routing) | 88.7% | 71.2% |
| **Qwen3-4B only** | **97.7%** | **94.2%** |
| Gemma 4 E2B only | 88.0% | 69.2% |

The acceptance criterion "section labels and title/artist correct on >= 90% of fixtures" is met only
when MLX Qwen3-4B does the labelling.

## 4. Natural-language set requests (15 prompts)

Each prompt's gold record has 12 fields (target minutes, count, min proficiency, opener, closer,
include/exclude tags, keys, tempo min/max, and others). The table gives field accuracy and fully
exact prompts. Before comparing, deterministic normalisation (what the app's mapper would do) turns
no-op values into "unset": 0, tempo >= 250, duplicate tags.

| Schema | FM | Qwen3-4B | Gemma 4 E2B | Qwen3.5-2B | Phi-4-mini |
|---|---|---|---|---|---|
| v1: 12 fields, `Int?` optionals | 61.9%, 0/28 exact (2 decodingFailure), median 6.8 s | 67.8%, 0/15, 4.5 s | 87.8%, 3/13 (2 runaway), 2.4 s | 44.4%, 3.0 s | 42.8%, 3.8 s |
| v2: 11 fields, no optionals (0 = unset), `.maximumCount(4)` | 47.2%, 0/30, 8.3 s | 75.0%, 0/15, 4.0 s | 93.9%, 8/15, **1.7 s** | 67.2%, 2.1 s | 42.3%, 3.3 s |
| **v3: code parses minutes/count/BPM/keys; model maps only 6 fuzzy fields** | 65.0%, 0/30, 4.5 s | 83.9%, 2/15, 2.6 s | **95.0%, 9/15, 1.7 s** | 77.8%, 1.4 s | 65.7% (6 runaway), 2.1 s |

- FM fills every enum and array with non-default values, for example `closer=crowd pleaser`,
  `excludeTags=[acoustic, ballad, ...]` or `opener=high` when nothing was asked. With v1 it also
  *omitted* `targetMinutes` even when the request stated one, because it leaves `Optional`s empty.
  None of the three schemas fixed this.
- The v3 numeric parser (regex in `SpikeCore/NumericRequest`) got all 15 prompts right. It was written
  against these prompts, so treat that as an upper bound, not a measurement.
- Most remaining model errors are invented opener values. A phrase lexicon in code
  ("know well" -> ready, "know cold" -> pro, "finish big" -> closer high, tag
  names as written) would cover nearly every prompt here.

## 5. Recommendations

### 5.1 Curated MLX model

**Qwen3-4B-Instruct-2507, 4-bit** (`mlx-community/Qwen3-4B-Instruct-2507-4bit`):

- 98% section labels and 98% on unheaded blocks; 19/19 title and artist; 100% on Hinglish songs.
- Apache-2.0, not gated. 2.28 GB download, about 3 GB peak RAM.
- About 6.5 s per song on the M1 Pro.

Gemma 4 E2B is the better set-request mapper (95%, 1.7 s) but much worse at pastes (82.5%), and it is
a larger download (3.58 GB). Qwen3.5-2B and Phi-4-mini are not viable.

### 5.2 Routing (proposed change to spec rule 1, needs sign-off)

1. **Paste enrichment:** use MLX (curated) when it is installed, else FM, else deterministic only.
   - On MLX, FM is never needed. On FM, fall back to MLX on `unsupportedLanguageOrLocale`,
     `guardrailViolation`, `refusal`, `decodingFailure`, `exceededContextWindowSize` and
     `rateLimited`/`concurrentRequests` (the last two after one spaced retry).
   - The language check costs about 3 ms, so trying FM first on Hinglish wastes nothing. A
     romanized-Hindi heuristic is unnecessary for routing, but it is useful as a stat.
2. **Over-budget sheets** (more than about 35 blocks): go to MLX directly. Chunk on FM only when MLX
   is absent, using deterministic cross-chunk hints.
3. **Set request / NL pick:**
   - Code always runs first: numbers, keys, and a phrase lexicon for proficiency,
     opener/closer and tag names. Its result fills the chips instantly, inside the < 1 s budget.
   - A model is called only when words remain unmapped, asynchronously, and its additions appear as
     suggested chips. Order: MLX if installed (v3 schema), else FM (v3 schema; expect about 65%).
   - Never block on it.

### 5.3 Prompt and schema design (validated)

- **Separate calls per task** (labels; metadata; set request), each with a fresh session.
- **No `Optional` properties** in FM `@Generable` outputs. Use `""` or 0 sentinels and normalise in
  code. Post-process `"Unknown"` to empty, and drop an artist equal to the title.
- **Pin every array**: exact count through `DynamicGenerationSchema` when known, `.maximumCount`
  otherwise. On MLX, add `minItems`/`maxItems` and bounded integers. `.anyOf` enums for labels, keys
  and tags. **Generate the MLX JSON Schema from the `@Generable` `GenerationSchema`** (it is `Codable`
  and encodes standard JSON Schema with `$defs`, `enum` and `x-order`).
- **Deterministic hints in the prompt**: header label, "same lyrics as Block N", chords-only, tab, no
  chords. They add 6-16 points. Labels from explicit headers are taken from code, never the model.
- **Metadata call input**: only the top and bottom blocks (if they have no chords) plus the chord
  sequence. If there is no top-of-sheet candidate, skip the call. Otherwise FM returned the chord "A"
  as a title on E07.
- Greedy sampling everywhere: results are repeatable (3 FM runs gave identical outputs).

### 5.4 Chunking

Rarely needed: the largest fixture used 1,566 of 4,096 tokens. When it is needed, chunk on block
boundaries, keep the deterministic hints (they carry cross-chunk repetition), and ask for metadata in
its own call. Prefer MLX over chunking because chunking cost 18 points on unheaded blocks.

### 5.5 Expected UX latency (M1 Pro 16 GB, measured)

| Path | Latency |
|---|---|
| Deterministic paste result (review sheet opens) | instant |
| AI decisions arriving in the review sheet: MLX Qwen3-4B, warm | about 4.4 s labels + 1.8 s metadata (run in parallel or stream) |
| Same, MLX cold | add about 0.6 s load + 1.7 s warm-up (grammar compile and kernels) |
| Same, FM | 5-30 s, median about 18 s |
| NL pick: code lexicon | instant |
| NL pick: model refinement | 1.7 s (Gemma) / 2.6 s (Qwen3-4B) / about 4.5 s (FM) |

The review sheet must show the deterministic result immediately and fill in AI labels as they arrive,
never behind a spinner. Load the MLX model when the paste sheet opens and unload it after it has been
idle for a set time (holding about 3 GB on a 16 GB Mac is costly).

### 5.6 Spec impacts (`docs/phases/3-ai-entry-and-assistant.md`)

1. Routing rule 1, "FM available -> FM", becomes "curated MLX installed -> MLX, else FM" for paste
   enrichment (5.2). **Needs a decision.**
2. "NL pick < 1 s on FM" is not achievable on this hardware. Make the pick deterministic-first, with
   model refinement asynchronous (5.2.3). Add `SetRequestLexicon` (code) ahead of
   `SetRequestParseTask`, and change the parse task to the v3 fuzzy-only schema.
3. "A `@Generable` output struct (FM) and a JSON schema (MLX)" becomes **one `@Generable` type per
   task**, with the MLX JSON Schema derived from `GenerationSchema`. Note the extra dynamic constraints
   (exact counts, bounded integers).
4. "MLX: JSON schema + parse-and-retry if no constrained decoding": `MLXGuidedGeneration` works on
   macOS 26, so use it (as `phase3-ai.md` spec impact 4 said). Add one retry on `incompleteOutput`, and
   use a no-free-whitespace grammar.
5. FM budget: `tokenCount` is 26.4+, so put it behind `#available` with a chars/3 fallback. The
   "~2,500 input tokens per chunk" figure is fine (measured max 949 prompt tokens). Chunking hurts
   quality, so route long sheets to MLX first.
6. MLX adapter: set `Memory.cacheLimit` (e.g. 512 MB) and unload the model after idle. Without the
   limit, footprint reached 11.6 GB.
7. Task 2a outcome: FM accepted 6/8 Hinglish fixtures, scoring 84% labels (vs 92% English).
   `unsupportedLanguageOrLocale` is deterministic per song, so the decisions.md rule "try FM first,
   fall back to MLX" works as written. No guardrail or refusal was seen in 446 calls.
8. Eval set (spec test strategy): reuse this spike's scorer metrics (label accuracy split into headed
   and unheaded, title/artist/key, failure kinds, latency p50/p90, tokens). Add a fixture with no title
   block (E07) and one that is Hindi-dominant (H07) as permanent regression cases.
9. The Settings > AI curated-model card shows: Qwen3-4B-Instruct-2507 4-bit, Apache-2.0
   (Qwen/Qwen3-4B-Instruct-2507), 2.28 GB download, about 3 GB RAM while active.

## 6. Not covered / open questions

- **Not tested:** MLX inside the App Sandbox (Metal kernel compile, model files in Application
  Support). This remains open from `phase3-ai.md` and needs a check in the real app target.
- **Not tested:** FM latency on another Mac. Run
  `fmspike paste fixtures out.jsonl mode=hints split exact repeat=3` on a newer or less loaded Mac to
  check whether the 5-30 s range is specific to this machine.
- **Open question 1:** Change paste routing to MLX-first when the curated model is installed (5.2.1)?
  Or keep FM-first and accept about 72% on unheaded blocks?
- **Open question 2:** Curated model: Qwen3-4B (best pastes, 2.3 GB) or Gemma 4 E2B (best set
  requests, faster, 3.6 GB)? This doc recommends Qwen3-4B, with set requests handled mostly by the
  code lexicon.
- **Open question 3:** Is a model call for set requests worth keeping at all, given the lexicon
  covers nearly every test prompt? The alternative is lexicon only, plus chips the user edits.
