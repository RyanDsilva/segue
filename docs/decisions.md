# Decision log

Closed answers to the open questions raised by the phase specs (2026-10-16/17). Specs are updated to match; this log is the audit trail.

## Cross-cutting

- **Testing:** integration-first. Real parser + real file store + real index + real UI flows (XCUITest). Unit tests only for tricky pure logic (transposition, layout fitting, set packing). No mock-heavy unit padding.
- **Signing:** free Personal Team `V6BM673U35` (contact@ryandsilva.dev) for development; switch to a paid team before App Store/iCloud work (phase 7). Bundle ID `dev.ryandsilva.segue`.

## Phase 0

- Project generation: **Tuist**.
- Index: **GRDB** (FTS5).
- Music theory: **depend on Tonic** (AudioKit, MIT).
- Lint/format: **SwiftLint + SwiftFormat** (via mise).
- App metadata: **sidecar JSON only**; `.cho` stays clean ChordPro.
- Newer sidecar schema than app: **open read-only + warn**.
- Default library: **~/Music/Segue** (user can pick any folder; bookmark).

## Phase 1

- Visual editor: **TextKit 2 in AppKit**.
- Guitar shapes: **generated algorithmically per tuning + curated overrides**.
- Nashville in minor keys: **relative major** (Am in A minor = 6m).
- Piano diagram: **compact one octave**, bass marked separately.
- Apply transposition to source: **rewrite chords, keep capo, flag custom shapes** that no longer match.
- Key detection: **deterministic scorer**; AI only when ambiguous.

## Phase 2

- DND: **run user's "Gig Mode" Shortcut on show start/end + pre-show checklist**.
- Repeated chorus: **per-song toggle, default collapse later repeats**.
- Live reorders: **ask at show end** (diff, save/discard).
- "Play now" interrupts: interrupted song **back to pending**.
- Proficiency: **3 levels - Learning, Ready, Pro**.
- **User-set minimum font** (default 22pt); below that, scroll instead of shrinking.
- No second-screen teleprompter. Gig log: venue/date/notes/rating only.

## Phase 3

- MLX: **curated one-click model** (chosen by eval spike) **plus advanced setting for any mlx-community model**.
- Paste review sheet: **always shown**.
- Set builder: **learn real durations** (time songs in shows/rehearsal), **energy 1-5 per song**, **suggested starter tags**. Repeat avoidance: not venue-aware. No polished batch import.

## Phase 4

- Songbook PDF **with table of contents**. No duplex, notes opt-in per export, no branding footer, no large-print setlist.
- ChordPro export **applies current transpose by default**.

## Phase 5

- Restricted package: **folder in this repo** (`Packages/SeguePersonalModules`), never referenced by AppStore scheme, mechanically verified; stripped from any App Store source export.
- **In-app recording in 5a.** Source audio not retained by default.
- ASR default **picked by eval** (WhisperKit vs SpeechAnalyzer on user's recordings).
- URL import: **Ultimate Guitar, E-Chords/Chordie, generic page extraction**.
- Success bar: **accuracy targets gate** (WER <= 25%, chords >= 70%).

## Phase 6

- None of: MIDI program-change out, pedals outside live mode, per-song pedal overrides, long-press default. Taps stay instant; long-press opt-in.

## Phase 7

- Partner follows **section/scroll position**; **trusted devices remembered**. Partner cannot request songs.
- **Visual editor on iPhone**, **personal modules on iOS**, **user-picked iCloud Drive folder**.
- Transport and iCloud-vs-CKSyncEngine stay gated on research tickets R7.1 / R7.2.

## Round 2 (2026-10-17)

- **Phase 0:** team ID committed as `DEVELOPMENT_TEAM` in `Project.swift`; Tuist local-only (no cloud account or caching). Verification task added: Shortcut launch behaviour from a full-screen sandboxed app (feeds phase 2).
- **Phase 1:** chords Tonic cannot model use our own interval table - transposable, with generated diagrams. Nashville header in minor keys shows both, e.g. "Am (rel. C)".
- **Phase 2:** unfinished show older than 12 hours is closed into the gig log on next launch and the reorder diff is offered then. Rehearse-setlist run added (no show or gig-log record).
- **Phase 3:** rehearsal timing uses both a rehearse-setlist run and a per-song Start/Stop timer. Energy at import is optional in the review sheet, prefilled with an AI suggestion; the scorer falls back to tempo when blank.
- **Phase 5:** if no chord model reaches 70%, chord detection stays behind the experimental toggle and spike 5 evaluates training our own licence-clean model.
- **Phase 7:** the follower's own transpose/instrument view persists per partner device.

## Naming (2026-10-17)

- Product name: **Segue** (replaces working title "Gigbook", which collides with DeepDish GigBook, iGigBook and GigBook Stage).
- App Store title e.g. **"Segue - Setlists & Chords"**.
- Bundle ID `dev.ryandsilva.segue`; modules SegueApp / SegueCore / SegueUI / SeguePersonalModules; default library `~/Music/Segue`; sidecars `<slug>.segue.json`.
- Trademark check: "SEGUE EDITOR" is a live US registration (audio-transition software); "SEGUE DATA SYSTEMS" (music software) cancelled 2011. No App Store setlist/chord app named Segue found. Manual USPTO search before any paid launch.
- Naming survey caveat: its "clean" verdicts were unreliable (Slate, Signal, Ledger, Stanza are existing brands).

## Brand (2026-10-17)

- Direction **C "Precise"**: Schibsted Grotesk (SIL OFL 1.1, bundled), ink/paper with dark stage ground, single coral cue accent (#F2555A; #C42B30 / #FF6B6F for text).
- App icon: **Taped setlist** (sheet with coral gaffer tape, rotated -6deg), built as a macOS 26 Icon Composer layered `.icon` in phase 0.
- Full spec: `docs/brand.md`. Key screen layouts presented as 2-3 variants on the design canvas before phase 1/2 UI.

## Language (2026-10-17)

- Languages: **English + romanized Hindi (Latin script) only**. No Devanagari display, no other languages.
- Sections stay **Verse / Chorus / Bridge / custom labels**; no Mukhda/Antara/Sanchari section types.
- **No auto-transliteration of pasted text** - lyrics are kept exactly as the user pasted them.
- **Romanization-tolerant search: yes.** The index stores a deterministic normalized form so spelling variants match ("pyar" finds "Pyaar").
- Where the app itself generates Hindi text (phase 5 ASR output, LRCLIB results returned in Devanagari), it uses **casual Bollywood romanization** - no diacritics, e.g. "tum hi ho", "pyaar".
- Always-on safeguards:
  1. **Lyric preservation:** AI cleanup may change only chords, section labels and metadata, never lyric words. Enforced in code: the lyric token sequence of the output must equal the input's, otherwise the AI result is rejected and the deterministic result is used.
  2. **Editor input:** autocorrect, spell-check and smart quote/dash substitution are off in lyric text.

## Phase 0 build rulings (2026-10-17)

- **ChordPro round trip:** separate `fileComment` and `commentDirective` block cases, and every directive/line keeps its original source spelling (trivia) so serialization is byte-identical; edits re-spell only what changed.
- **Sections hold blocks:** `Section.items: [Block]` (lines, comments, directives, blanks; no nested sections).
- **E2E library path:** Debug configurations only get a temporary-exception entitlement for a `/tmp` test path; Release and AppStore builds never carry it, and `make verify-appstore` checks that.
- **Two app targets:** `Segue` (Personal, links SeguePersonalModules) and `SegueAppStore` share sources, bundle id and entitlements, because SwiftPM dependencies attach per target, not per configuration.

## Phase 7 research outcomes (2026-10-17)

- **R7.1 transport:** Network.framework (new Swift NetworkListener/NetworkBrowser/NetworkConnection), TCP + TLS, length-prefixed JSON, Bonjour `_segue._tcp`, peer-to-peer Wi-Fi enabled. Wi-Fi Aware adapter later for iOS-to-iOS / Android. See `docs/research/phase7-sync.md`.
- **R7.2 library sync:** keep the user-picked iCloud Drive folder; change detection via NSFilePresenter plus rescan on launch/foreground/bookmark resolve (NSMetadataQuery is unreliable for user-picked folders); detect both NSFileVersion conflicts and "name 2.cho" duplicates.

## Key screen layouts (2026-10-17)

Chosen on the design canvas (https://claude.ai/artifact/XizqyqzA1chVfBSGThAzcQ):
- **Library:** a - three pane (sidebar, song list, chart preview).
- **Editor:** b - visual canvas (chord pills over syllables, transpose/capo/Nashville bar, chord palette); text mode remains via toggle.
- **Setlist builder:** a - library to set (two columns, start times, running total vs target).
- **Paste review:** a - side by side (original vs result, AI changes marked apart from rule-based conversion).

## Phase 5 research notes (2026-10-17)

See `docs/research/phase5-audio.md`. Conflicts with earlier research to re-verify in spike: BTC weights reported MIT (earlier: CC-BY-NC-SA); `schism-audio/htdemucs-coreml` does not exist (use MLX Swift Demucs ports). Do not feed the separated vocal stem to ASR by default (Jam-ALT: WER worsens). Apple SpeechTranscriber has no hi-IN on this machine.

## Phase 3 research outcomes (2026-10-17)

- **Minimum OS stays macOS 26.** Our own AI provider port abstracts Foundation Models vs MLX; the macOS 27 `LanguageModel` protocol is not required. Raise the floor later if useful.
- **Romanized Hindi AI cleanup:** try Apple Foundation Models first; on unsupported-language/guardrail/refusal errors fall back to the local MLX model automatically. The spike measures how often this happens.

## Phase 1 build rulings (2026-10-17)

- `{key}` with `{capo}` names the **shapes** key (concert = key + capo).
- `{meta: tuning}` in the song wins over the sidecar tuning; the editor writes both.
- "Apply transposition to source" **adds a `{key}`** (the detected/inferred key, transposed) when the song had none.
- Nashville view supports **number entry** (1, 4, 6m, b7, 5/7) in addition to letter names; numbers resolve against the display key.
- Diagram strip is **off by default**.
- Inserting a chord where one already sits **replaces** it (no stacking).
- Nashville digit suffixes take parentheses (`E7` in Am = `3(7)`, `1(6/9)`); bIII and bVII spelled flat in every key; minor leading tone always sharp; strict chord parsing (no `o` for diminished, so Hindi "Do" is never a chord).
