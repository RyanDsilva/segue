# Segue - Vision & Scope

> Name: **Segue** (formerly working title "Gigbook", dropped because it collides with DeepDish GigBook, iGigBook and GigBook Stage). App Store title e.g. "Segue - Setlists & Chords". Trademark note: "SEGUE EDITOR" is a live US registration for audio-transition software; "SEGUE DATA SYSTEMS" (music software) was cancelled in 2011. Do a manual USPTO search (tmsearch.uspto.gov) before any paid launch.

Canonical product doc. Phase specs (`docs/phases/*.md`) point back here; when they disagree, this doc wins until it is explicitly revised.

## 1. Who and what

A native macOS app for one performing musician (keys, guitar, vocals) playing **solo/duo acoustic gigs, open mics and jams**. It does three jobs:

1. **Get songs in fast** - paste, type, import files or import from URL; on-device AI turns the mess into a clean chord chart.
2. **Build set lists** - by hand or with an AI assistant ("45-min set, songs I know well, upbeat start").
3. **Perform** - a MacBook on a stand, dark stage mode, the whole song readable at a glance, fast mid-gig changes and requests.

Rehearsal at home is a secondary use of the same views. iPhone/iPad is a later phase.

### Worked example (confirmed with the user)

- **Monday** - paste a messy chords-over-lyrics page. AI produces a clean chart (title, artist, key, Verse/Chorus/Bridge) saved as `wonderwall.cho`. Flip to the visual editor, drag a chord onto the right syllable, set capo 2, tag it `crowd pleaser`, proficiency "know it cold".
- **Thursday** - "45-minute set, mostly songs I know well, upbeat start" -> assistant drafts the set; drag two songs around.
- **Friday gig** - stage mode (dark, no sleep, no notifications). Each song fits one screen or auto-scrolls; footer shows next song + key + capo. A request comes in: search the whole library, add to the request queue, play it. Skip a song. The gig log records what was played, where.
- **Later** - the iPhone/iPad app opens the same library folder through the Files app; duo partner's device follows the set over local Wi-Fi.

## 2. Decisions (closed)

| Area | Decision |
|---|---|
| Platform | macOS 26+ (Tahoe), SwiftUI-first, AppKit where needed (live view, text editor). iOS/iPadOS in phase 7, so core code is platform-neutral. |
| Distribution | **Mac App Store only** - no DMG, no direct (Developer ID) distribution (R139). Built to App Store standards from day one (App Sandbox, security-scoped bookmarks, no private APIs). |
| Signing | Free Personal Team `V6BM673U35` (contact@ryandsilva.dev) for development; paid team needed before App Store submission. Bundle ID `dev.ryandsilva.segue`. |
| Tooling | Tuist (project generation), GRDB (SQLite index, FTS5), Tonic (music theory, MIT), SwiftLint + SwiftFormat (via mise). |
| Testing | Integration-first: real parser + file store + index + XCUITest flows. Unit tests only for tricky pure logic (transpose, layout fitting, set packing). |
| Build flavors | Two schemes. **Personal** links a separate local Swift package of restricted modules; **App Store** does not reference it at all - absent from the shipped source tree and binary. Modules plug in through a plugin/registry protocol in core. |
| Restricted (personal-only) set | LRCLIB lyrics search, URL import from chord sites, the custom MLX model setting (R97). *(Audio features removed from the roadmap - R132.)* |
| Storage | **Files are canonical.** Library folder (default `~/Music/Segue`, user can pick any, bookmarked): one clean `.cho` ChordPro file per song + JSON sidecar as the only home of app metadata (newer sidecar schema than the app knows: open read-only + warn) (tags, proficiency, notes, per-song display prefs, audio refs); setlists and gig log as JSON files. A SQLite index is a rebuildable projection (search, filters), never the source of truth. On iOS (phase 7) the app opens a library folder picked in the Files app (any provider) and reads the files directly; no Segue sync engine, no conflict UI (R134). |
| Format | ChordPro (chordpro.org, v6 directives subset) as the song format. Own parser (Chord Provider's is GPL-3.0 and not packaged; no permissive Swift ChordPro package found). |
| AI engine | One `LanguageModelProvider`-style interface. Default: Apple Foundation Models (on-device, ~4,096-token context, `@Generable` guided generation). Fallback: MLX-Swift local model (downloaded on demand) for long/messy input and set building. All local, no cloud. *(v0.5: routing is curated MLX if installed, else FM, else deterministic - R63; see docs/release/decisions.md R61-R79.)* |
| Song entry | Paste + AI cleanup, smart text editor, file import (ChordPro, plain text, chords-over-lyrics), URL import (restricted), LRCLIB search (restricted). No existing library to migrate. |
| Language | English + romanized Hindi (Latin script). Romanization-tolerant search; lyrics never respelled or translated (AI output checked mechanically); autocorrect/spell-check off in lyrics; app-generated Hindi uses casual Bollywood romanization. No Devanagari display. |
| Editor | Both modes, toggleable: text (ChordPro with syntax colors, chord autocomplete, live preview) and visual (click/drag chords onto syllables). |
| Instruments | Transpose + capo toggle (shapes vs concert pitch), Nashville number view toggle, chord diagrams for guitar (standard + alternate tunings + custom shapes) and piano voicings. |
| Live view (v1) | Auto-fit to one screen (columns/scale), auto-scroll (duration/tempo-based, pausable), next-song footer, dark stage theme, per-song font/zoom memory, section highlighting (collapsed chorus repeats), keep awake + suppress notifications. |
| Setlist live ops | Quick library search mid-show, reorder/skip/mark played, request queue. (Multiple sets with timing: not requested.) |
| Gig extras | Per-song notes/cues, gig log/history, PDF export/print. Backing tracks: not requested. |
| Library | Tags (free-form + suggested starters) + smart filters, proficiency (Learning / Ready / Pro), energy rating 1-5, learned real durations. *(v0.5: energy deferred - R71; R70's learned/estimated durations superseded by R91: manual length + "Time it", unknown stays unknown.)* |
| Set assistant | Build a set to a target length; natural-language song picks. |
| Sharing | PDF (phase 4, in v0.5). Share by file (N5: a setlist plus its songs as one file) and partner live sync ship with phase 7 (iOS). |
| Control | MIDI input + mapping with MIDI learn in phase 6 (not critical). Bluetooth HID pedals removed (R132); MIDI output for per-song presets is a research ticket (R135). |
| Process | Spec docs first, open questions closed by the user, then each phase is built by parallel agents with tests + E2E. Present 2-3 visual design directions before building UI. |

## 3. Architecture sketch

```
SegueApp (macOS target, Tuist-generated, schemes: Personal / AppStore)
 ├─ SegueCore (Swift package, platform-neutral, no UI)
 │   ├─ ChordPro      parse / serialize / AST, chords-over-lyrics converter
 │   ├─ MusicTheory   on Tonic: transpose, capo, Nashville, key detection from chords
 │   ├─ Library       file store (bookmarks, coordination), sidecars, GRDB index (rebuildable)
 │   ├─ Setlists      setlists, request queue, gig log
 │   ├─ AI            LanguageModelProvider port: FoundationModels adapter, MLX adapter
 │   └─ Plugins       registry protocols that restricted modules implement (SongImporter, LyricsSource)
 ├─ SegueUI (SwiftUI views; shared with iOS later)
 └─ Packages/SeguePersonalModules (local package in this repo, Personal scheme only; AppStore build verified free of it)
     ├─ LRCLIBSource
     └─ URLImport
```

Principles: files canonical, index rebuildable; injectable clock/IO for deterministic tests; everything works offline on stage; the live view never blocks on AI, network or indexing.

## 4. Phase map

Each phase has a standalone spec in `docs/phases/`. Closed answers to the specs' open questions are logged in [decisions.md](decisions.md). Brand and design system: [brand.md](brand.md).

| # | Phase | Outcome |
|---|---|---|
| 0 | [Walking skeleton](phases/0-walking-skeleton.md) | Project, schemes, Core package, ChordPro parser v0, library folder + index, one song -> one setlist -> basic live view, test + E2E harness |
| 1 | [Editor & music theory](phases/1-editor-and-music-theory.md) | Text + visual editor, transpose/capo/Nashville, chord diagrams (guitar, tunings, custom, piano) |
| 2 | [Setlists & live mode](phases/2-setlists-and-live-mode.md) | Setlist builder, full live mode, request queue, gig log, notes/cues, tags/proficiency basics. **Gig-ready.** |
| 3 | [AI entry & assistant](phases/3-ai-entry-and-assistant.md) | Paste cleanup, file import, AI provider port (FM + MLX), set assistant, smart filters |
| 4 | [Export](phases/4-export.md) | Single chart PDF and songbook PDF, print, embedded preview |
| 5 | [Personal modules](phases/5-personal-modules.md) | Plugin package: LRCLIB lyrics search, URL import |
| 6 | [Hands-free control](phases/6-hands-free-control.md) | MIDI (CoreMIDI) input, mapping UI with MIDI learn |
| 7 | [iOS + partner sync](phases/7-ios-and-partner-sync.md) | iPhone/iPad app with a Files-app library folder, leader/follower set sync over local network, personal modules on iOS |

### Roadmap order (R138, 2026-10-20)

Canonical sequence; rulings R132-R139 in [release/decisions.md](release/decisions.md).

1. **v0.5 (pre-launch):** phases 0-3, the phase 3 leftovers, phase 4 PDFs (single chart, songbook, print, embedded preview), plus:
   - N1 **Singer view** - lyrics only, chords hidden.
   - N4 **Medleys** - several songs joined into one set slot with a written transition.
   - N8 **Gig stats** - most played, not played lately, per-venue history, from the existing play history.
2. **Phase 6:** MIDI input and mapping with MIDI learn; the Ampero II Stomp MIDI-output research ticket (R135) runs alongside.
3. **Phase 5:** LRCLIB lyrics search, URL import.
4. **Phase 7:** iOS/iPadOS app, live partner follow, personal modules on iOS, plus N5 **Share by file** - a setlist plus its songs as one file via AirDrop/Share.

Phases 5 and 7 were not ranked by Ryan; iOS last is the orchestrator's default and open to change.

Removed from the roadmap (R132): setlist one-pager, ChordPro export, audio-to-chart, Bluetooth HID pedals and pedal presets, iCloud Drive library sync with conflict UI.

## 5. Out of scope (unless asked)

Multi-user/band accounts, cloud backend, backing tracks/audio playback, multiple timed sets, lighting, Android, sheet-music/PDF score reading, direct (non-App Store) distribution (R139). MIDI patch changes: research ticket only (R135).

Considered and declined (R137): an external stage display, Shortcuts/Siri/Spotlight App Intents, OnSong/OpenSong import, ukulele/bass diagrams, a per-singer default key.
