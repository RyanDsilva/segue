# Phase 3: on-device model bake-off for paste refinement (2026-10-19)

Ryan did not lock Qwen3-4B (86.1% section labels on his first 10 pastes, about 3 GB peak, 5.2 s per labels call on an M1 Pro under load). He asked for a faster model, because Segue will also run on low-power laptops such as the MacBook Neo. This bake-off ran 10 small instruct models through the same harness as `phase3-eval-real-pastes.md`, with Qwen3-4B as the baseline and Foundation Models (FM) as the comparator that needs no download. The corpus is 51 of Ryan's real pastes (25 English, 26 romanized Hindi, 669 blocks). The pastes, gold data and per-song results stay local and gitignored. This doc gives aggregate numbers only.

## Short answer

- **No small model is worth shipping for this task.**
  - On the latest pipeline (P3-2, `bfb6b45`), the deterministic tier alone gets **86.8%** of section labels right. It does this by leaving every unheaded block as a `{start_of_verse}` placeholder.
  - Every 0.6-1.7B model scores **at or below** that: Qwen3-0.6B 83.3%, LFM2.5-1.2B 84.2%, Llama 3.2 1B 84.6%, Qwen3-1.7B 86.2%. Qwen3.5-0.8B scores 87.6%, a gain of 5 blocks out of 669.
  - On the blocks the pipeline leaves to a model, the small models are right 20-42% of the time. The placeholder alone is right 38% of the time.
- **Only Qwen3-4B clears the >= 90% bar: 92.2%** (EN 93.0, HI 91.3) on the latest pipeline. Next are FM at 89.5%, Qwen3.5-2B at 88.2% and SmolLM3-3B at 87.0%.
- **The metadata call makes title/artist worse with every model.** On the latest pipeline, code alone gets title and artist right on 42/51 pastes. With any model it is 29-36/51, because models add an artist where the paste states none. This is a pipeline rule to fix, and swapping the model does not change it (see "Title and artist").
- **MacBook Neo** (verified on apple.com): A18 Pro, 6-core CPU, 5-core GPU, **8 GB only**, **60 GB/s**, Apple Intelligence supported.
  - Compared with this M1 Pro, it has about 0.3x the memory bandwidth and about 0.5x the GPU (Geekbench Metal).
  - **Estimate:** Qwen3-4B's labels call would take about 13-22 s on a Neo, against 6.7 s here. Its peak footprint can be cut to 2.8 GB with a tight MLX cache.
- **Recommendation:**
  - Keep **Qwen3-4B-Instruct-2507 4-bit as the only curated model**.
  - Turn it on by default only on Macs with **16 GB or more**.
  - On 8 GB Macs (the Neo), **default to FM**, and offer Qwen3-4B as an explicit opt-in.
  - Do not add a "fast" small model.
  - Ryan rules (see "Decisions for Ryan").

## Setup

| | |
|---|---|
| Harness | `research/phase3-eval/bakeoff.sh [ref] [model...]`. It wraps `mlxspike` and `fmspike` as in `run.sh`. Design: split labels and metadata calls with P3-1 hints, a no-free-whitespace EBNF grammar, one whitespace-bias retry, greedy decoding, `cachelimit=512`, the metadata call skipped when there are no top/bottom candidate lines, and every model on the same prompts. Aggregates: `bakeoff_table.py` |
| Pipeline refs | **`55d8701`** (P3-1 as landed). The gold block indices were recorded at this ref, so all 11 models are compared here. **`bfb6b45`** (latest main, P3-2's pipeline fixes `1bde682` and later). Segmentation is identical to 55d8701 on all 51 pastes, so the gold needed no re-index. The 8 most relevant models plus FM were re-run here. Every number below names its ref |
| Machine | MacBook Pro M1 Pro (10-core CPU, 16-core GPU, 200 GB/s), 16 GB, macOS 26.6.2. Sibling agents were building and testing throughout (load average 3-40). **Every latency is an upper bound.** The `bfb6b45` run overlapped the constrained-memory runs, so use its latencies only within that run |
| Scorer fix | `score.py` compared keys after stripping `#`, so F#m matched Fm. Keys are now compared by pitch class, with enharmonic spellings equal (`key_ok`). The earlier 10-paste key results are unaffected (none of them had a sharp key) |
| New metrics | `unheadedUnambig`: blocks left to the model whose gold label is not ambiguous. `none`: the deterministic tier alone (all model calls failed) |

### Candidates (verified on Hugging Face 2026-10-19)

| Model (mlx-community) | Revision | Licence | Disk | Arch |
|---|---|---|---|---|
| Qwen3-0.6B-8bit | 11de96878523501bcaa86104e3c186de07ff9068 | Apache-2.0 | 0.65 GB | qwen3 |
| Qwen3-1.7B-4bit | 3b1b1768f8f8cf8351c712464f906e86c2b8269e | Apache-2.0 | 0.98 GB | qwen3 |
| Qwen3.5-0.8B-MLX-4bit | 5d894f8cc4ef3e6c88537bf3746ed262f549da6a | Apache-2.0 | 0.65 GB | qwen3_5 (VL weights, text path) |
| Qwen3.5-2B-MLX-4bit | 93760be4f1f69842a46bc13dbdc0f19e291392a3 | Apache-2.0 | 1.75 GB | qwen3_5 (VL) |
| LFM2.5-1.2B-Instruct-4bit | dee2f8a2786e6648bb644a7ca40652842490034b | **LFM Open License v1.0** (not OSI; commercial-use threshold) | 0.66 GB | lfm2 |
| gemma-3-1b-it-qat-4bit | 15fed4eafb456c6fcb2a1165f19ac609670ed14b | **Gemma Terms of Use** | 0.77 GB | gemma3_text |
| Llama-3.2-1B-Instruct-4bit | 08231374eeacb049a0eade7922910865b8fce912 | **Llama 3.2 Community** (attribution + AUP) | 0.71 GB | llama |
| Llama-3.2-3B-Instruct-4bit | 7f0dc925e0d0afb0322d96f9255cfddf2ba5636e | **Llama 3.2 Community** | 1.83 GB | llama |
| SmolLM3-3B-4bit | d3a7e0594d6642dbcfb7d149bed8b0bdf49f95ce | Apache-2.0 | 1.75 GB | smollm3 |
| LFM2.5-2.6B-4bit | 72a08228cf703cd7dc0187abf4edbbd8e935f864 | LFM Open License v1.0 | 1.54 GB | lfm2: **does not load** in mlx-swift-lm 3.32.3 (`keyNotFound model.embedding_norm`) |
| Qwen3-4B-Instruct-2507-4bit (baseline) | 50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b | Apache-2.0 | 2.28 GB | qwen3 |

Not run, and why:

- Gemma 4 E2B (3.6 GB) and Phi-4-mini lost the 2026-10-17 spike.
- gemma-3n-E2B (2.5 GB) and Ministral-3-3B (2.8 GB) are larger than Qwen3-4B's weights.
- No Qwen3.6 or Gemma 4 size under 2 GB exists on mlx-community.

Weights live in `.build/bakeoff/models/` (list in `research/phase3-eval/models.tsv`) and are never in git.

## Results

### Latest pipeline (`bfb6b45`): the numbers that decide

| Model | Labels all | EN | HI | Left to model (131) | of which unambiguous (87) | Hindi left-to-model | Songs all right | Title+artist | Key | Call failures | Labels p50 / p90 | Per song p50 / p90 | MLX peak | Peak footprint |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **none (deterministic only)** | **86.8%** | 87.2 | 86.5 | 38.2% | 32/87 | 42.9% | 21 | **42/51** | 50 | n/a | 0 | 0 | 0 | 0 |
| **Qwen3-4B-2507** | **92.2%** | 93.0 | 91.3 | **65.6%** | **61/87** | **64.3%** | **28** | 34 | 50 | 0 | 9.0 / 14.1 s* | 13.0 / 18.9 s* | 3.07 GB | 3.67 GB |
| FM | 89.5% | 90.8 | 88.1 | 51.9% | 52/87 | 50.0% | 20 | 35 | 50 | 4 labels + 7 metadata (`unsupportedLanguageOrLocale`) | 15.6 / 24.5 s | 25.1 / 34.0 s | system | system |
| Qwen3.5-2B | 88.2% | 91.6 | 84.2 | 45.0% | 41/87 | 32.9% | 18 | 31 | 50 | 0 | 3.1 / 4.6 s | 6.2 / 8.2 s | 2.12 GB | 2.84 GB |
| Qwen3.5-0.8B | 87.6% | 89.7 | 85.2 | 42.0% | 36/87 | 37.1% | 21 | 31 | 50 | 0 | 2.4 / 3.5 s | 4.9 / 6.8 s | 1.41 GB | 2.03 GB |
| SmolLM3-3B | 87.0% | 89.7 | 83.9 | 38.9% | 37/87 | 31.4% | 18 | 29 | 50 | 0 | 5.8 / 7.3 s | 8.2 / 9.8 s | 2.49 GB | 3.11 GB |
| Qwen3-1.7B | 86.2% | 87.5 | 84.8 | 35.1% | 32/87 | 35.7% | 18 | 36 | 50 | 0 | 3.6 / 5.9 s* | 5.5 / 8.1 s* | 1.82 GB | 2.45 GB |
| Llama 3.2 1B | 84.6% | 89.1 | 79.4 | 26.7% | 24/87 | 11.4% | 18 | 30 | 50 | 6 metadata (retried) | 1.6 / 2.0 s | 2.9 / 4.6 s | 1.42 GB | 2.07 GB |
| LFM2.5-1.2B | 84.2% | 85.0 | 83.2 | 24.4% | 19/87 | 28.6% | 19 | 31 | 50 | 0 | 2.0 / 2.8 s | 3.0 / 4.0 s | 1.44 GB | 2.03 GB |
| Qwen3-0.6B (8-bit) | 83.3% | 85.0 | 81.3 | 19.8% | 13/87 | 20.0% | 18 | 36 | 50 | 0 | 2.3 / 3.7 s* | 4.1 / 5.1 s* | 1.47 GB | 2.08 GB |

\* These ran at the same time as a constrained-memory run of another model, so they are slower than the 55d8701 figures below. Use the 55d8701 table for latency.

### Pinned comparison (`55d8701`, all models, same gold)

| Model | Labels all | EN | HI | Left to model (152) | unambiguous (103) | Hindi left-to-model | Title+artist | Call failures | Load | Warm-up | Labels p50 / p90 | Per song p50 / p90 | MLX peak | Peak footprint |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| none (deterministic only) | 74.4% | 77.7 | 70.6 | 23.7% | 19/103 | 24.3% | 26 | n/a | | | | | | |
| **Qwen3-4B-2507** | **84.2%** | 87.5 | 80.3 | **66.4%** | **74/103** | **67.1%** | 26 | 0 | 2.5 s | 2.1 s | 6.7 / 9.5 s | 9.8 / 12.6 s | 3.06 GB | 3.69 GB |
| Qwen3.5-2B | 81.9% | 86.9 | 76.1 | 56.6% | 61/103 | 48.6% | 25 | 0 | 1.4 s | 1.4 s | 3.2 / 4.3 s | 5.5 / 7.8 s | 2.12 GB | 2.83 GB |
| FM | 80.3% | 83.8 | 76.1 | 49.3% | 55/103 | 48.6% | 26 | 5 labels + 7 metadata | | | 15.4 / 21.3 s | 23.3 / 33.1 s | | |
| SmolLM3-3B | 78.9% | 83.6 | 73.5 | 43.4% | 50/103 | 37.1% | 25 | 0 | 0.9 s | 1.7 s | 4.8 / 6.1 s | 6.7 / 8.4 s | 2.49 GB | 3.10 GB |
| Qwen3-1.7B | 78.0% | 81.3 | 74.2 | 39.5% | 43/103 | 40.0% | 26 | 0 | 0.6 s | 0.9 s | 3.2 / 4.4 s | 5.0 / 6.3 s | 1.82 GB | 2.43 GB |
| Qwen3.5-0.8B | 77.0% | 80.2 | 73.2 | 34.9% | 32/103 | 35.7% | 25 | 0 | 2.3 s | 7.0 s | 1.7 / 2.2 s | 3.6 / 5.2 s | 1.41 GB | 2.12 GB |
| Llama 3.2 1B | 76.8% | 83.3 | 69.4 | 34.2% | 37/103 | 18.6% | 25 | 4 metadata (retried) | 1.1 s | 1.0 s | 1.5 / 2.0 s | 2.6 / 4.0 s | 1.42 GB | 2.06 GB |
| Qwen3-0.6B (8-bit) | 76.2% | 78.6 | 73.5 | 31.6% | 33/103 | 37.1% | 26 | 0 | 0.6 s | 1.2 s | 1.4 / 2.1 s | 2.6 / 3.6 s | 1.42 GB | 2.07 GB |
| LFM2.5-1.2B | 76.1% | 78.8 | 72.9 | 30.9% | 30/103 | 34.3% | 25 | 0 | 0.3 s | 1.1 s | 2.0 / 3.0 s | 3.0 / 4.2 s | 1.44 GB | 2.02 GB |
| Llama 3.2 3B | 75.3% | 78.3 | 71.9 | 27.6% | 29/103 | 30.0% | 25 | 0 | 0.9 s | 1.4 s | 3.9 / 5.2 s | 5.3 / 6.8 s | 2.58 GB | 3.25 GB |
| Gemma 3 1B (QAT) | 74.6% | 77.7 | 71.0 | 24.3% | 20/103 | 25.7% | 26 | 0 | 1.8 s | 5.8 s | 7.8 / 10.9 s | 10.0 / 13.1 s | 1.27 GB | 2.06 GB |

Notes:

- **Key is 47/51 for every model and for code alone**, and 50/51 on bfb6b45. The key comes from code (stated key, then the detector). The model is consulted only on ambiguous detections, and it never changed a result.
- **Gemma 3 1B is slow despite its size.** Its labels call takes 7.8 s for about 126 output tokens. The likely cause is the per-token grammar mask over its 262k-token vocabulary, but this is not proven. It also hit whitespace runaway on the warm-up call.
- **The model ranking is the same on both refs.** On the new pipeline, P3-2 decides 21 more blocks in code, which lifts every row. It lifts the small models less: their wrong labels on blocks that are still unheaded now cost more than the placeholder did.
- **Hindi is where the small models break down.** Llama 3.2 1B gets 11-19% of Hindi blocks left to the model; Qwen3.5-2B gets 33-49%. Qwen3-4B gets 64-67%.

### Title and artist (bfb6b45)

- Code finds a title on 36/51 pastes and an artist on 19/51.
- Code alone gets title and artist both right on 42/51. With a model's metadata call, the result is 29-36/51.
- Of Qwen3-4B's 9 regressions:
  - 7 are "title right from code, model adds an artist the paste does not state" (UG "Misc Soundtrack"-style pages, or an uploader line);
  - 2 are a model title on a paste with no title.
- A what-if guard that keeps a model title or artist only when it appears verbatim in the paste recovers little (Qwen3-4B 36/51). The strings are in the text; they are just not the artist.
- **The fix belongs to the pipeline (P3-2 / P3-3), not to model choice.**
  - Do not take an artist from the model when code found the site heading. Or require the artist to appear in a "by X" or "Artist:" position.
  - Skip the metadata call entirely when code found both title and artist.

### Constrained memory (55d8701, `cachelimit=32` plus an MLX `memoryLimit`)

| Model | memoryLimit | Peak footprint (default, then tight) | MLX peak (tight) | Accuracy | Labels p50 (tight) |
|---|---|---|---|---|---|
| LFM2.5-1.2B | 1 GB | 2.02 GB, then **1.17 GB** | 1.08 GB | identical | 2.2 s |
| Qwen3-0.6B (8-bit) | 1 GB | 2.07 GB, then **1.32 GB** | 1.16 GB | identical | 1.7 s |
| Qwen3.5-0.8B | 1 GB | 2.12 GB, then **1.42 GB** | 1.25 GB | identical | 2.8 s |
| Qwen3-1.7B | 1 GB | 2.43 GB, then **1.43 GB** | 1.31 GB | identical | (overlapped) |
| Qwen3.5-2B | 1.5 GB | 2.83 GB, then **2.02 GB** | 1.76 GB | identical | 3.1 s |
| Qwen3-4B | 2 GB | 3.69 GB, then **2.77 GB** | 2.64 GB | identical | (overlapped) |

- Greedy decoding is deterministic, so the outputs were byte-for-byte the same. Only memory changed.
- **MLX's `memoryLimit` is a soft limit.** Qwen3.5-2B went 260 MB over it and no call failed. It does not force a model into a budget. It only makes MLX free its cache sooner.
- The real lever is `cacheLimit`. 32 MB cost no measurable latency on the runs that did not overlap. P3-3 should use a small cache limit (for example 64 MB) instead of 512 MB.
- Only the 0.6-1.7B models fit the roughly 1.5 GB budget, and those are the models that do not beat the placeholder.

## MacBook Neo

| | Spec | Source |
|---|---|---|
| Chip | A18 Pro: 6-core CPU (2P + 4E), **5-core GPU**, 16-core Neural Engine | apple.com/macbook-neo/specs (verified 2026-10-19) |
| Memory | **8 GB unified, no other option**; **60 GB/s** | apple.com specs (verified) |
| Cooling | fanless | press coverage of the launch (Tom's Guide, The Daily Star / Reuters), not on the specs page |
| Price / release | $599 ($499 education), on sale 2026-03-11 | press (Tom's Guide, Gigazine); **not checked on apple.com** |
| Apple Intelligence / FM | supported: the specs page lists Apple Intelligence language availability | apple.com specs (verified). FM availability follows Apple Intelligence; **not tested on a Neo** |
| macOS | ships with macOS Tahoe 26.3.x | Appleosophy (press); **unverified at Apple** |
| GPU | Geekbench 6 Metal about 30,800-31,300, about 5.6% below the 6-core iPhone 16 Pro | wccftech, IT之家 (press) |
| M1 Pro 16-core GPU (this Mac) | Geekbench Metal about 63,000 | Notebookcheck (press; the Geekbench version is **unverified**) |

**Estimate, not measured.** No MLX or llama.cpp benchmark of the A18 Pro was found.

- Token generation is bound by memory bandwidth (60 vs 200 GB/s, so 3.3x slower). Prefill of the roughly 1,250-token label prompt is bound by GPU compute (about 2x slower).
- A labels call should therefore take **2-3.3x** the M1 Pro time:

| Model | M1 Pro labels p50 (55d8701, loaded) | Neo estimate |
|---|---|---|
| Qwen3-0.6B | 1.4 s | 3-5 s |
| Qwen3.5-0.8B | 1.7 s | 3.5-6 s |
| Qwen3.5-2B | 3.2 s | 6-10 s |
| Qwen3-4B | 6.7 s | **13-22 s** (per song with metadata: 20-32 s) |
| FM | 15.4 s | unknown (the system model's speed on A18 Pro is unpublished) |

- The M1 Pro figures are themselves upper bounds, so the estimate leans pessimistic.
- A single paste is a burst of 10-30 s, so fanless throttling should not matter. A bulk import of many pastes could throttle, which is unmeasured.

**Memory headroom on 8 GB (estimate).**

- macOS plus a browser and Segue typically leave about 3-4 GB free.
- Metal's `recommendedMaxWorkingSetSize` on 8 GB Macs is reported at about 5.3-6 GB. That is a press/forum figure, **unverified**; Apple's documentation gives no number.
- Qwen3-4B with a tight cache (2.8 GB peak) probably fits when the Mac is otherwise idle. It will push other apps to swap when Safari is heavy.
- Apple Intelligence's own model memory is managed by the OS and is not counted against Segue. That is an advantage of FM on 8 GB, though not a measured one.
- We have no 8 GB Mac to verify any of this. P3-3's eval target should be run on one before the 8 GB default is final.

## Recommendation

1. **Curated model: keep Qwen3-4B-Instruct-2507 4-bit (R64).** It is the only model above 90% (92.2% on the latest pipeline, Hindi 91.3%), with zero call failures. Ship it with `cacheLimit` around 64 MB, giving a peak footprint of about 2.8 GB.
2. **No small "fast" model.**
   - Within the roughly 1.5 GB budget, every candidate is at or below the deterministic tier on labels (83.3-87.6% vs 86.8%) and below it on title/artist.
   - Shipping one would cost a download and memory for no gain. On a Neo it would also cost 3-6 s per paste.
   - Qwen3.5-2B, the best below 4B, scores 88.2% and is weak on Hindi (33% of the Hindi blocks left to it). It is not a "quality" tier either, because Qwen3-4B already fits 16 GB Macs comfortably.
3. **8 GB Macs (the Neo): default to FM, offer Qwen3-4B as an opt-in.**
   - FM scores 89.5%, with no download and OS-managed memory.
   - FM is slow (15.6 s per labels call here) and rejects some Hindi calls. When it rejects a call, the deterministic tier still applies, so the result is never worse than 86.8%.
   - An opt-in Qwen3-4B on a Neo would take an estimated 13-22 s per labels call and 2.8 GB of RAM.
   - Routing becomes: MLX if installed (on 8 GB only when the user opted in), then FM, then deterministic. The phase 3 spec already routes this way, except for the RAM gate.
4. **Fix the metadata step before the next re-check** (P3-2 / P3-3). The model must not override a code title, and must not supply an artist when the paste has a site heading or a code title. With that fix, title/artist goes back to at least the deterministic 42/51.
5. **Where the remaining label misses are:** 26 of the 87 unambiguous blocks left to Qwen3-4B are wrong on the latest pipeline. The next lever is more deterministic coverage (the continuation rule, a "continues Block N" hint) and prompt wording, not a different model.

## Decisions for Ryan

- **Model:** keep Qwen3-4B as the single curated model? Or make Qwen3.5-2B the curated model (88.2%, below the bar, about 2x faster, 2.0 GB tight), trading accuracy for speed?
- **8 GB Macs:**
  - (a) FM by default with Qwen3-4B opt-in (recommended);
  - (b) Qwen3-4B by default everywhere;
  - (c) deterministic only on 8 GB;
  - (d) make this a research ticket: measure on a real 8 GB Mac or a Neo first.
- **Licences:** if a small model is ever reconsidered, LFM2.5 (LFM Open License), Gemma and Llama 3.2 are not Apache/MIT. All the Qwen and SmolLM3 candidates are Apache-2.0.

## Reproduce

- `research/phase3-eval/bakeoff.sh <ref> [model... fm]` writes `results/bakeoff-<ref>/` (gitignored). The folder holds the per-model `.jsonl` and `.log` files, `ingest.json`, `none.jsonl` (the deterministic tier) and the table.
- `BAKEOFF_ARGS` passes extra `mlxspike` options. Note that `opt()` takes the first match, so to run a tight cache, call `mlxspike` directly with `cachelimit=32 memlimit=<MB>`.
- `research/phase3-eval/remap_gold.py` re-indexes the gold labels if a future pipeline changes segmentation. It matches blocks by text between two `fmspike render` outputs; unmappable blocks become `null` and are not scored.
- `mlxspike` now prints the lifetime peak `phys_footprint` and accepts `memlimit=`.
