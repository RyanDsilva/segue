# Research findings (2026-10-16)

Gathered by research subagents, then adversarially fact-checked. Only items marked **verified** are safe to build on; everything else must be re-checked at source in the phase that depends on it.

## On-device AI

- **Apple Foundation Models** - shipped with macOS/iOS 26 (Sept 2025). On-device model context ~**4,096 tokens** shared by instructions + input + output (Apple forums thread 791026; `contextSize` / `tokenCount()` added in 26.4). `@Generable` guided generation and tool calling exist. Requires Apple Intelligence enabled on an eligible device. *Verified (version, context). Unverified: WWDC26 additions (bigger context, PCC for third-party apps, MLX backend behind the FM protocol) - re-check before phase 3.*
- **MLX-Swift** (`ml-explore/mlx-swift`, `mlx-swift-lm`) runs quantized open models on Apple Silicon. Constrained/JSON decoding exists via third-party work (not verified). Sandboxed App Store use not confirmed. Licences: Qwen (Apache 2.0), Gemma (Gemma terms), Llama (community licence), Phi (MIT) - verify per model before bundling.
- Implication: chunk long songs or route to MLX; keep prompts tiny; structured output via `@Generable`.

## Audio-to-chart (restricted module, phase 5)

| Component | Option | Licence | Status |
|---|---|---|---|
| Lyrics transcription | WhisperKit | **MIT** | verified (prior claim "Apache 2.0" was wrong) |
| Lyrics transcription | Apple SpeechAnalyzer/SpeechTranscriber | Apple | word timestamps verified; singing quality unknown |
| Vocal separation | Demucs / HTDemucs (Core ML: `schism-audio/htdemucs-coreml`; MLX port) | MIT | verified |
| Sections, beats, tempo | All-In-One (`mir-aidj/all-in-one`), PyTorch only | MIT code + weights | verified; needs Core ML/MLX conversion |
| Chords | BTC transformer (ISMIR 2019, ~71.8% WCSR sevenths) | weights CC-BY-NC-SA | verified; personal only |
| Chords | Chordino/NNLS-Chroma | GPL | verified; personal only |
| Key/BPM | Essentia (AGPL), libKeyFinder (GPLv3), aubio (**GPLv3**, not ISC), madmom models (CC-BY-NC-SA) | copyleft/NC | verified; personal only |
| BPM | spfk-tempo | MIT | claimed, not deeply verified |

- Accuracy on sung lyrics: Whisper-large ~28-36% WER on full mix, ~20% best open pipeline with separation (Jam-ALT, arXiv 2506.15514 - arXiv only, no venue found).
- No permissively licensed SOTA chord-recognition weights found - an App Store version would need our own model.

## Storage & sync

- **Files + bookmarks + rebuildable index** (chosen): sandbox-safe via `com.apple.security.files.user-selected.read-write` + security-scoped bookmarks; iCloud Drive conflicts via `NSFileVersion`; dataless/evicted files on iOS must be handled.
- Rejected: SwiftData/Core Data + CloudKit (opaque sync, last-write-wins, migration pain); document packages (macOS 26.2 iCloud Drive package-sync regression, forums thread 810671 - verified issue exists); CRDT/git/Syncthing (iOS story weak).
- Fallback for later: CKSyncEngine + GRDB (works; must persist engine state; tombstone replay noted by mjtsai 2026-04-01, verified). Sandboxed macOS 26 apps hit a `com.apple.cloudd` mach-lookup issue outside Xcode (forums 842234, verified; workaround exists).
- Comparable apps: OnSong (Dropbox/Drive/WebDAV), SongbookPro (OneDrive/Dropbox/WebDAV), forScore (custom iCloud sync).

## ChordPro & music theory

- ChordPro spec: chordpro.org (directives: title, artist, key, capo, tempo, time, duration, sections `start_of_verse`/`chorus`/`bridge`/`tab`/`grid`, `define`, `transpose`, meta).
- Chord Provider (desbeers) - SwiftUI ChordPro app, **GPL-3.0**, parser not a reusable package: reference only, don't copy code.
- ChordSheetJS (MIT, JS) - good reference for chords-over-lyrics -> ChordPro conversion heuristics.
- Tonic (AudioKit, MIT) - chord/key/transposition theory in Swift; candidate dependency.
- Chord diagrams: SwiftyGuitarChords, Fretboard (guitar, licences unchecked); **no piano chord-diagram library found** - build it.

## Lyrics sources (restricted)

- Big apps (OnSong, SongbookPro) do not search lyrics; they import what the user brings.
- LRCLIB: free, no key, plain + synced lyrics, crowdsourced, content licence unclear -> personal module.
- Musixmatch free tier: 30% of lyrics only. Genius API returns no lyrics (scraping breaches ToS). ChartLyrics reportedly shut down Feb 2026 (unverified). Apple MusicKit does not expose lyrics.
- Ultimate Guitar: no public API, ToS forbids scraping -> URL import is personal-only.

## Partner live sync (phase 7) - mostly UNVERIFIED

- Candidate: Network.framework + Bonjour over local Wi-Fi / peer-to-peer, leader broadcasts versioned state snapshots, followers apply idempotently. forScore Cue and OnSong Connect do similar local-network sync.
- Unverified claims to re-check at source before phase 7: "MultipeerConnectivity deprecated in Xcode 27", Wi-Fi Aware availability on macOS, AWDL phase-out, peer ceiling ~8.

## Prior art (Mac-relevant)

OnSong (iOS + web console), BandHelper (Mac/iOS, cloud sync), forScore (PDF-centric, iPad/Mac), SongbookPro (Mac/iOS, UG import), SongSheet Pro (iOS), Capo (Mac, on-device chord detection), Chord ai (Mac M1+, subscription), Set List Maker (deprecated). Gap: no native, offline-first Mac app combining chords + lyrics + setlists + live mode + on-device AI.

Name check: "GigBook" taken by DeepDish GigBook, iGigBook, GigBook Stage (App Store) - product renamed to **Segue** (see decisions.md, Naming).

## Direct competitors to examine later

- **Cadence - Chord Chart Manager** (App Store id6744849238) - chord chart manager, closest by positioning.
- **Verse** (verse.sh) - Mac lyrics display app.

## Naming survey caveat

The naming subagent's "clean" verdicts were unreliable: Slate, Signal, Ledger and Stanza are existing brands. Treat any name verdict as unverified until checked against the App Store, USPTO/EUIPO and domains directly.
