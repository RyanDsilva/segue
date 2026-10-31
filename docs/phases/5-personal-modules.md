# Phase 5 - Personal modules (restricted package)

> Canonical context: `docs/00-vision.md` (decisions) and `docs/research.md` (verified facts). This doc is standalone for the phase 5 build session. If it disagrees with the vision doc, the vision doc wins.

Roadmap: after launch, after phase 6 (MIDI input).

## 1. Goal

Add to the separate local Swift package `SeguePersonalModules` (a **folder in this repo at `Packages/SeguePersonalModules`**, which already holds the Personal-only custom-model setting, R97) two licence-sensitive capabilities for the **Personal** build only:

1. **LRCLIB lyrics search** (5.2) - type a title/artist, get plain lyrics as a starting point.
2. **URL import** (5.3) - paste a chord-site URL (or Share from Safari), extract the chart.

The **App Store** scheme must not reference this package at all: absent from the source tree it builds, from the build graph, and from the binary. Core (`SegueCore`) never imports it; it only exposes protocols the package implements.

Why restricted: LRCLIB's content licence is unclear; scraping chord sites breaches their ToS (Ultimate Guitar).

## 2. Plugin contract in core

Core owns the protocols and a registry; it ships with zero implementations of them (App Store build simply shows no URL/LRCLIB entry points).

```swift
// SegueCore/Plugins
public protocol SongImporter: Sendable {
    static var id: PluginID { get }
    var displayName: String { get }
    func canImport(_ input: ImportInput) -> Bool        // .url(URL), .file(URL), .text(String)
    func importSong(_ input: ImportInput, progress: ProgressSink) async throws -> DraftSong
}

public protocol LyricsSource: Sendable {
    static var id: PluginID { get }
    func search(title: String, artist: String?) async throws -> [LyricsCandidate]
    func fetch(_ candidate: LyricsCandidate) async throws -> LyricsResult
}

public final class PluginRegistry {          // built once at launch, immutable after
    public func register(_ importer: any SongImporter)
    public func register(_ source: any LyricsSource)
}
```

- `DraftSong` is core's existing "unsaved song" value (ChordPro AST + metadata + provenance). Every plugin result lands in the same review/correct flow used by paste cleanup (phase 3); nothing is saved without user confirmation.
- UI asks the registry what is available; it never checks build flags.

**Registration.** The Personal scheme's app target links `SeguePersonalModules` and contains one file, `PersonalPlugins.swift`, that calls `SeguePersonalModules.registerAll(into: registry)` at launch. That file belongs only to the Personal target's membership. The App Store target has no such file and no package dependency. No `#if PERSONAL` in shared code.

## 3. Enforcing absence from the App Store build

Mechanical checks, run in CI and as a pre-archive script, fail the build on any hit:

1. **Graph check** - `xcodebuild -scheme AppStore -showBuildSettings` plus resolved package graph (`Package.resolved` / `xcodebuild -resolvePackageDependencies -scheme AppStore`) must not list `SeguePersonalModules` or any restricted dependency.
2. **Source check** - script greps sources compiled by the AppStore target (from the target's file list) for `SeguePersonalModules`, `LRCLIB`, and module type names.
3. **Binary check** - on the archived `.app`: `nm`/`otool -L`/`strings` scan for restricted symbols, frameworks, and the LRCLIB host. Zero matches required.
4. **Export check** - if a source tree is ever exported for App Store builds, the exporter copies only paths in an allowlist; the restricted package directory is not on it.

Decided: the package stays an in-repo folder (`Packages/SeguePersonalModules`); these checks, not repo separation, are the enforcement. They run in `make verify-appstore` (phase 0) and must pass before any App Store archive.

## 4. Romanization (core)

LRCLIB can return Hindi lyrics in Devanagari. They are converted deterministically to casual Bollywood romanization (no diacritics: "tum hi ho", "pyaar", "dil", "hai") by a `HindiRomanizer` in core: a rule table (consonants, matras, inherent-vowel deletion at word end and in common medial positions, nasalization as "n", nukta forms) plus an override dictionary for frequent words where the casual spelling differs from the rules. No language model in the loop, so output is reproducible. English words in mixed lines pass through unchanged.

### 4.1 Devanagari to casual romanization - research (2026-10-17)

- **Apple ICU `.toLatin` probe** **V** (local run) is ISO-15919-like:
  - `तुम ही हो` gives "tuma hī hō", `चलते` gives "calatē", `आँखें` gives "ām̐khēṁ", `क्यों` gives "kyōṁ".
  - Adding `.stripDiacritics` gives "tuma hi ho / calate / amkhem / kyom / divana".
  - It has no schwa deletion, writes च as "c" (not "ch"), writes anusvara/chandrabindu as "m", and loses vowel length (target style is "aa"/"ee": "pyaar", "deewana").
  - Verdict: not a usable base, and fixing it with post-rules is no simpler than writing our own table.
- **Libraries.**
  - `indic_transliteration` (sanscript) and `common_maps` are **MIT** **V**. They have scheme tables (ITRANS, OPTITRANS, HK, IAST) but **no schwa deletion** (grep of the source finds none). Usable as a reference for the consonant and matra table.
  - **Aksharamukha is AGPL-3.0** **V** (README) and libindic `indic-trans` is AGPL-3.0 **V**. Avoid both.
  - IndicXlit (MIT) is an ML model, excluded by the "no language model" rule above.
  - Google Dakshina's romanization lexicon (Hindi words with *attested casual romanizations*) is **CC BY-SA 4.0** **V** (README).
- **Override dictionary sources.** Dakshina's frequency-ranked attested spellings would be ideal for the override dictionary, but the share-alike licence would attach to the derived list. Because `HindiRomanizer` lives in core (App Store), **hand-curate the override list ourselves from Bollywood lyric words** and use Dakshina only as a local eval oracle, never shipped.
- **Approach.** A small deterministic Swift implementation is feasible (~300 lines plus a table):
  - Grapheme pass with a casual consonant map: च ch, छ chh, श/ष sh, व v/w, ज़ z, फ़ f, ड़ d.
  - Casual vowels: ा aa, ी ee/i (final i), ू oo/u, ै ai, ौ au, ए/े e, ओ/ो o.
  - Nasals: ं/ँ become n, or m before labials (प/ब/म).
  - Schwa deletion: delete word-final inherent a, and delete medial a in a VC_CV context when the following syllable has a full vowel (the classic Narasimhan et al. 2004 rule family **U** for the citation). For example, चलते gives "chalte".
  - Then the override dictionary.
- **Conclusion.** Do not build on ICU `.toLatin`. Write our own table with schwa deletion, MIT sanscript tables as a reference, and a hand-curated override list. Dakshina (CC BY-SA) is for eval only and never shipped in core.

(**V** = verified at the cited primary source or by a local probe on macOS 26.6.2, 2026-10-17; **U** = unverified.)

## 5. Sub-milestones

- **5.2 - LRCLIB.** Package registry wiring and absence checks (section 3) if not already present, then the `LyricsSource` implementation (search, fetch plain lyrics; synced LRC kept as an optional timing hint); the result feeds the phase 3 paste review flow to add structure. Attribution shown. Results returned in Devanagari go through `HindiRomanizer` first; search queries in romanized Hindi also try the normalized form from phase 0.
- **5.3 - URL import.** `SongImporter` for URLs: fetch the page the user chose and extract the chart. Site-specific extractors for **Ultimate Guitar, E-Chords and Chordie**, plus **generic page extraction** for any other site (readable-text extraction, then the phase 3 chords-over-lyrics converter + AI cleanup). Share extension in Personal build only.

Each sub-milestone ends with a green test suite, passing absence checks, and an E2E run of both schemes.

## 6. Test strategy

Integration-first; unit tests only for tricky pure logic.

- **LRCLIB / URL import (primary):** integration tests against recorded HTTP fixtures of real pages (UG, E-Chords, Chordie, a generic blog) through the real extractors and converter, landing in the real review sheet; one opt-in live-network smoke test.
- **Registry integration:** launch Personal and AppStore builds, assert which entry points exist (XCUITest).
- **Absence checks** (section 3) run as tests against real AppStore archives.
- **Unit tests (narrow):** a `HindiRomanizer` table (Devanagari word -> expected casual romanization) of a few hundred common lyric words.

## 7. Acceptance criteria

- LRCLIB search and URL import produce drafts that go through the same review flow as paste.
- App Store build: archive succeeds, all four absence checks pass, no UI entry points for these features.
- Nothing in this package runs during live mode.
- Hindi lyrics from LRCLIB arrive in casual Latin-script romanization, never Devanagari.

## 8. Research spikes (before or at start of phase)

1. LRCLIB API terms and rate limits re-check; whether synced lyrics help structure.
2. Page structures of UG, E-Chords and Chordie (UG embeds chart JSON in page data - verify), and Share extension behaviour on macOS 26.
3. **Licence-clean transliteration:** done - see section 4.1 (own rule table with schwa deletion, hand-curated override list).

## Resolved decisions

See `docs/decisions.md`.

1. **Package location: folder in this repo** (`Packages/SeguePersonalModules`) - absence is enforced by the section 3 checks, not by repo separation.
2. **URL import sites: Ultimate Guitar, E-Chords/Chordie, plus generic page extraction.**

## Open questions

None open.
