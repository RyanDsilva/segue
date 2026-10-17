# Phase 5 audio spikes - desk research (2026-10-17)

Covers spikes 1-5, 8, 9 of `docs/phases/5-personal-modules.md` section 10, plus the 5a-5e pipeline. Spikes 6-7 (LRCLIB, chord-site pages) are out of scope here. **V** = verified at the cited primary source on 2026-10-17; **U** = unverified. Local probes ran on macOS 26.6.2 with the MacOSX26.5 SDK.

## 1. WhisperKit

- **Repo and version.** The repo is now `argmaxinc/argmax-oss-swift` (old `argmaxinc/WhisperKit` URL redirects). Latest is **v1.1.1 (2026-10-08)**, MIT licence, macOS 14+. v1.0.0 (2026-05-01) was a breaking rename into a multi-kit SDK (WhisperKit, SpeakerKit, TTSKit) **V** (`gh api repos/argmaxinc/WhisperKit/releases`, LICENSE at HEAD 9f99b5c).
- **Models.** `huggingface.co/argmaxinc/whisperkit-coreml` is MIT **V**. Download sizes (sum of folder files) **V**: tiny 77 MB, base 147 MB, small 486 MB (the `small_216MB` compressed variant also exists), medium 1.5 GB, large-v3 3.1 GB (947 MB compressed variant), `large-v3-v20240930` (= large-v3-turbo **U**) in 547/626/632 MB compressed variants. The spec's "~40 MB to ~1.5 GB" range is off. Realistic Hindi-capable candidates are about 0.5-0.65 GB.
- **Word timestamps.** `DecodingOptions.wordTimestamps = true` gives `WordTiming { word, tokens, start, end, probability }` **V** (`Sources/WhisperKit/Core/Models.swift:622`, `TranscribeTask.swift:197`).
- **Hindi.** `"hindi": "hi"` is in the language table, and `DecodingTask` has `.transcribe` / `.translate` **V** (`Models.swift:1360, 277`). With `language: "hi", task: .transcribe`, Whisper writes in the native script, which for Hindi means **Devanagari** **U** (this is standard Whisper behaviour; confirm on eval items). Auto language detection on Hinglish lyrics can drift into Urdu script or into an English translation **U**, so **pin `language`** per take and never use `.translate`.
- **Romanized-output alternative.** `Oriserve/Whisper-Hindi2Hinglish-Prime` (fine-tuned from large-v3) and `-Swift` (from base) are Apache-2.0 **V** (HF API cardData). Both are trained to emit Hinglish in Latin script directly. They could be converted with whisperkittools, but they were trained on speech, not singing, and their spelling style is uncontrolled **U**. Treat as a spike-8 contender, not the default.
- **Singing evidence.** Jam-ALT (Cífka et al., **ISMIR 2024**, arXiv 2408.06370 Table 1) **V**:
  - Whisper large-v3 WER is 35.5% on the full mix and 32.6% with the language given.
  - HTDemucs vocals *raise* WER to 48.0% (v3) and 44.5% (v2). Naive separation hurts.
  - Syed et al., *Exploiting Music Source Separation for ALT with Whisper* (**ICME 2025 Workshop AI for Music**, arXiv 2506.15514; venue from the arXiv comment) **V** get SOTA open-source Jam-ALT results only when separation is used as a **vocal-activity detector to pick segment boundaries** (plus short-segment concatenation), not as naive vocal-stem input.
  - No Hindi or Bollywood sung-lyrics benchmark was found **U**.

## 2. Apple SpeechAnalyzer / SpeechTranscriber (macOS 26 SDK)

From `MacOSX.sdk/.../Speech.swiftmodule/arm64e-apple-macos.swiftinterface` (SDK 26.5) **V**:

- **Analyzer.** `actor SpeechAnalyzer` takes modules and offers `start(inputSequence:)`, `analyzeSequence(from: AVAudioFile)`, `finalizeAndFinishThroughEndOfInput()` and `prepareToAnalyze(in:withProgressReadyHandler:)`. `Options(priority:, modelRetention: .whileInUse|.lingering|.processLifetime)`. `bestAvailableAudioFormat(compatibleWith:)`.
- **SpeechTranscriber.**
  - Presets are `.transcription`, `.transcriptionWithAlternatives`, `.timeIndexedTranscriptionWithAlternatives`, and progressive variants.
  - Options: `ResultAttributeOption` has `.audioTimeRange` and `.transcriptionConfidence`; `ReportingOption` has `.volatileResults`, `.alternativeTranscriptions` and `.fastResults`.
  - `Result` has `range: CMTimeRange`, `text: AttributedString` (timing and confidence as attributes on runs) and `alternatives`.
  - There is **no custom-vocabulary hint on SpeechTranscriber**. `AnalysisContext.contextualStrings` exists at the analyzer level.
- **DictationTranscriber.** The older dictation models, with the same `.audioTimeRange` attribute, a `timeIndexedLongDictation` preset, and `ContentHint.customizedLanguage(...)` for custom vocabulary. Apple docs say it is "compatible with older devices" and does not support network-only locales **V** (developer.apple.com docs JSON).
- **Locales (runtime probe, macOS 26.6.2)** **V**:
  - `SpeechTranscriber.supportedLocales` has 30 entries: en (9 regions incl. en-IN), de, es, fr, it, ja, ko, pt, yue, zh. **No hi-IN.** `AssetInventory.status` for `SpeechTranscriber(hi-IN)` returns **`.unsupported`**, even though `supportedLocale(equivalentTo: hi-IN)` returns hi_IN, which is misleading.
  - `DictationTranscriber` has 54 locales **including hi-IN** (status `.supported`, not installed).
  - So **Hindi on Apple is only available through DictationTranscriber**, the weaker legacy model. Its output script (Devanagari expected) is **U**.
- **Assets.** `AssetInventory.assetInstallationRequest(supporting:)` returns a `ProgressReporting` request, with `status(forModules:)` reporting unsupported/supported/downloading/installed. `reserve(locale:)` is limited by `maximumReservedLocales` (= **5** on this Mac). Assets are system-managed, shared across apps, and may be reclaimed if unused **V**. They do not count toward our download manager, but the "download speech model?" UX must wrap this request.
- **Singing quality.** No primary evidence. The SpeechTranscriber abstract says it targets "normal conversation and general purposes" **V**.

## 3. Demucs / HTDemucs on-device

- **The spec's `schism-audio/htdemucs-coreml` does not exist.** It returns 404 on both GitHub and Hugging Face (`huggingface.co/schism-audio`) **V**. Upstream `facebookresearch/demucs` is MIT and **archived** **V**.
- **Core ML.** `dexxdean/htdemucs-coreml` (MIT, updated 2026-07) **V**:
  - Real-valued STFT/iSTFT wrapper, MHA decomposed for coremltools, input `(1,2,441000)` (10 s, 44.1 kHz), output `vocals, drums, bass, other`.
  - Sizes: FP32 ~400 MB, FP16 ~200 MB. Includes a Swift chunk/overlap-add example. No runtime numbers.
  - `tsyrenov1987/demucs-coreml-ios` (MIT, Accelerate STFT) is another; all are single-author, low-star repos **V**.
- **MLX (Swift).**
  - `kylehowells/demucs-mlx-swift` (MIT) **V**: all 8 Demucs models. On a 3:19 track on an M1 Pro, `htdemucs` takes **14.8 s** (~13x realtime), `htdemucs_ft` 95.8 s, `htdemucs_6s` 17.7 s. Supports `--two-stems vocals`.
  - `ssmall256/demucs-mlx-swift` (MIT) **V**: Swift 6 actor API, MLX Swift 0.32.3, macOS 14+.
  - Both are young, single-maintainer projects. MLX's GPU memory cache needs capping (`demucs-mlx` README notes MLX keeping 16-31 GB cached on a 128 GB machine).
- **Verdict.** MLX-Swift is the more mature on-device path. It has published timings and a reusable package, and the same MLX stack serves All-In-One. Core ML stays as a fallback.

## 4. All-In-One (`mir-aidj/all-in-one`)

- **Paper.** Kim and Nam, **WASPAA 2023** (Best Student Paper) **V** (OpenAlex DOI 10.1109/WASPAA58266.2023.10248148).
- **Outputs.** `AnalysisResult { bpm: int, beats, downbeats, beat_positions, segments[label,start,end], activations?, embeddings? }` **V** (`src/allin1/typings.py`). Labels: `start, end, intro, outro, break, bridge, inst, solo, verse, chorus` **V** (`config.py`). No "pre-chorus".
- **Architecture.**
  - Input is HTDemucs 4-stem demix, giving per-stem log-filtered spectrograms at 100 fps.
  - Model: 11-layer dilated neighborhood attention (NATTEN 1D, kernel 5, 2 heads, dim 24) **V** (`config.py`, `models/dinat.py`).
  - Default `harmonix-all` is an **8-fold ensemble at ~1.4 MB per checkpoint (~11 MB total)**. Weights are on HF `taejunkim/allinone`, MIT **V**.
  - Post-processing uses **madmom** `DBNDownBeatTrackingProcessor` and madmom spectrogram code **V** (`postprocessing/metrical.py`, `spectrogram.py`). That is madmom *code*, which is BSD. The CC-BY-NC-SA licence covers only madmom's own *model files*, which All-In-One does not use **V** (madmom LICENSE). All-In-One shares the Demucs pass with our separation step.
- **Existing port.** `ssmall256/all-in-one-mlx` (MIT, Python + MLX) **V**:
  - Uses `natten-mlx` (MIT, Metal kernels).
  - Native C++ Viterbi DBN (`postprocessing/_viterbi_cpp.cpp`) and MLX spectrograms with a parity guard.
  - 5.96 s per song on an M4 Max versus 24.6 s for the MPS-patched original.
  - There is **no Swift port** (GitHub search for `allin1 swift` and `all-in-one coreml` is empty) **V**.
- **Feasibility.**
  - **MLX-Swift** is the shortest path: port the model plus natten-mlx kernels (MLX Swift supports custom Metal kernels **U**), and port the DBN Viterbi and log-filtered spectrogram to Swift/Accelerate. It is small (11 MB, about 100 lines of model code).
  - **Core ML** needs NATTEN replaced by an unfold/gather formulation with flexible sequence length (~24k frames for 4 min). That is feasible but unproven **U**.

## 5. Chord recognition

**Correction to `docs/research.md`: BTC weights are MIT, not CC-BY-NC-SA.**
- `jayg996/BTC-ISMIR19` is MIT. Weights `test/btc_model.pt` and `btc_model_large_voca.pt` (~12 MB each) sit inside the MIT repo with no separate weights licence **V**.
- Caveat: it was trained on Isophonics, Robbie Williams and UsPop annotations with audio "collected from online music service providers" **V** (README). Training-data provenance is a policy question, not a licence term.

| Option | Code / weights licence | Notes |
|---|---|---|
| BTC (ISMIR 2019) | MIT / MIT **V** | 12 MB, CQT input; majmin and large-vocab heads |
| Chordino / NNLS-Chroma | GPL-2.0-or-later **V** (`c4dm/nnls-chroma`) | Plain C++ (plus `nnls.c`); `chordextract.cpp` instantiates the plugin directly via the Vamp Host SDK (BSD-style **V**). It embeds as a SwiftPM C++ target with Swift C++ interop **U**. GPL is fine for a personal build that is never distributed. |
| consonance-ACE (Poltronieri et al., **ISMIR 2025**) | MIT, 57 MB checkpoint in repo **V** | Conformer; trained on Isophonics, Billboard, RWC, USPop; optional beat sync via Beat This! |
| lv-chordia (Jiang et al., **ISMIR 2019**, `music-x-lab`) | MIT **V** | Large-vocab, 5-model ensemble plus HMM |
| ChordMini (Phan et al., arXiv 2602.19778, no venue) | MIT, checkpoints in repo **V** | Pseudo-label distillation from a BTC teacher |
| Beat This! (ISMIR 2024) | code and weights MIT **V** | Licence-clean beat tracker; README warns its training data is partly copyrighted |

**Datasets for a licence-clean model (spike 5)** **V** unless marked:
- **AAM** (3,000 synthetic multitracks *with audio*, chords, beats, keys, segments) is **CC BY 4.0** (Zenodo 5794629; EURASIP JASMP 2023).
- **GuitarSet** (audio plus chord annotations) is **CC BY 4.0** (Zenodo 3371780).
- **McGill Billboard** annotations are **CC0**, but no audio is distributed, only NNLS-chroma features (mirdata `billboard.py`).
- **JAAH** is CC BY 4.0 (annotations only).
- **RWC-Pop** annotations are CC BY-NC 4.0, and Haydn op20 is CC BY-NC-SA (mirdata).
- **Isophonics** (Beatles, Queen): licence not found **U** (mirdata says so too).

A clean recipe is pre-training on AAM plus self-rendered synthetic progressions, then fine-tuning on GuitarSet and the user's own recordings. Billboard CC0 labels are only usable against audio the user owns.

## 6. Devanagari to casual romanization

- **Apple ICU `.toLatin` probe** **V** (local run) is ISO-15919-like:
  - `तुम ही हो` gives "tuma hī hō", `चलते` gives "calatē", `आँखें` gives "ām̐khēṁ", `क्यों` gives "kyōṁ".
  - Adding `.stripDiacritics` gives "tuma hi ho / calate / amkhem / kyom / divana".
  - It has no schwa deletion, writes च as "c" (not "ch"), writes anusvara/chandrabindu as "m", and loses vowel length (target style is "aa"/"ee": "pyaar", "deewana").
  - Verdict: not a usable base, and fixing it with post-rules is no simpler than writing our own table.
- **Libraries.**
  - `indic_transliteration` (sanscript) and `common_maps` are **MIT** **V**. They have scheme tables (ITRANS, OPTITRANS, HK, IAST) but **no schwa deletion** (grep of the source finds none). Usable as a reference for the consonant and matra table.
  - **Aksharamukha is AGPL-3.0** **V** (README) and libindic `indic-trans` is AGPL-3.0 **V**. Avoid both.
  - IndicXlit (MIT) is an ML model, excluded by the spec's "no LM" rule.
  - Google Dakshina's romanization lexicon (Hindi words with *attested casual romanizations*) is **CC BY-SA 4.0** **V** (README).
- **Override dictionary sources.** Dakshina's frequency-ranked attested spellings would be ideal for the override dictionary, but the share-alike licence would attach to the derived list. Because `HindiRomanizer` lives in core (App Store), **hand-curate the override list ourselves from Bollywood lyric words** and use Dakshina only as a local eval oracle, never shipped.
- **Approach.** A small deterministic Swift implementation is feasible (~300 lines plus a table):
  - Grapheme pass with a casual consonant map: च ch, छ chh, श/ष sh, व v/w, ज़ z, फ़ f, ड़ d.
  - Casual vowels: ा aa, ी ee/i (final i), ू oo/u, ै ai, ौ au, ए/े e, ओ/ो o.
  - Nasals: ं/ँ become n, or m before labials (प/ब/म).
  - Schwa deletion: delete word-final inherent a, and delete medial a in a VC_CV context when the following syllable has a full vowel (the classic Narasimhan et al. 2004 rule family **U** for the citation). For example, चलते gives "chalte".
  - Then the override dictionary.

## 7. Recommended pipeline per sub-milestone

- **5a.**
  - Decode with AVFoundation, then HTDemucs via `demucs-mlx-swift`. Run it once and share stems with All-In-One.
  - Lyrics: WhisperKit `large-v3-v20240930_626MB` with pinned `language`, `.transcribe` and word timestamps. Feed it the **full mix or a gently vocal-boosted mix**. Use the vocal stem only for VAD and segmentation (per Jam-ALT and ICME 2025).
  - SpeechTranscriber for English only. **Hindi on Apple goes through DictationTranscriber.**
  - Beats, tempo and sections via an All-In-One MLX-Swift port.
  - **Risks:** porting all-in-one-mlx to Swift (NATTEN kernels, DBN) is the largest unknown. As a fallback, ship sections from Beat This! (beats) plus a self-similarity segmenter.
- **5b.**
  - Start with BTC (MIT, 12 MB; convert to Core ML/MLX), using the CQT front end in Accelerate. Also try consonance-ACE (MIT) as a challenger.
  - Chordino goes in as a C++ target only if both miss 70%.
  - Key from the chord sequence.
  - **Risks:** a CQT parity mismatch with librosa (golden-test it), and stem bleed.
- **5c-5e.** No new model risk: core alignment; LRCLIB Devanagari goes through `HindiRomanizer`; URL import has no audio dependency.
- **Go/no-go gates:**
  - Hindi WER from WhisperKit versus DictationTranscriber versus the Hinglish fine-tune.
  - All-In-One Swift parity against Python on 5 songs (same beats within 10 ms).
  - BTC WCSR at or above 70% on self-recordings.
  - End-to-end time at or below 1x song length on M1-class hardware. The budget: Demucs ~15 s, All-In-One under 30 s, and Whisper turbo under 60 s for 4 min, all **U** until measured.

## Spec impacts

1. Section 1 and `docs/research.md`: **BTC weights are MIT** (fix the CC-BY-NC-SA claim). Remove BTC from the "why restricted" list; the remaining restricted reasons are Chordino GPL, LRCLIB and scraping.
2. Section 5 step 2 and section 10 spike 4: **replace `schism-audio/htdemucs-coreml` (does not exist)** with `kylehowells/` or `ssmall256/demucs-mlx-swift` (MLX) versus `dexxdean/htdemucs-coreml` (Core ML).
3. Section 5 step 3: do **not** feed the separated vocal stem to Whisper by default (it raises WER by 10-15 points on Jam-ALT). Use separation for VAD and segmentation, and keep "vocals vs mix" as an eval axis.
4. Section 5 step 3 and spike 8: **Apple SpeechTranscriber has no hi-IN.** The Apple Hindi engine is `DictationTranscriber`. `LyricsTranscriber` needs per-locale engine selection. Add `Oriserve/Whisper-Hindi2Hinglish` (Apache-2.0) as a third Hindi contender.
5. Section 4 sizes: Whisper candidates are 0.55-0.65 GB (turbo compressed), Demucs FP16 ~200 MB / MLX ~80 MB **U**, All-In-One ~11 MB, BTC 12 MB. Apple speech assets are system-managed (max 5 reserved locales).
6. Section 5 step 4: All-In-One has **no pre-chorus label**, and it needs madmom-derived DBN and spectrogram code ported (BSD). A Swift MLX port is new work; budget it as its own build unit.
7. `HindiRomanizer`: do not build on ICU `.toLatin`. Write our own table with schwa deletion, MIT sanscript tables as a reference, and a hand-curated override list. Dakshina (CC BY-SA) is for eval only and never shipped in core.
8. Spike 5 data: AAM (CC BY 4.0) plus GuitarSet (CC BY 4.0) are the licence-clean audio and chord sources. Billboard is CC0 but has no audio.
