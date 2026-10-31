# P8-8 - Several artists, Movie / Album, and slot time from the timeline

Phase 8 workstream (new, 2026-10-31). Ruling: `docs/release/decisions.md` **R172** (several artists as chips, one `{artist:}` each; the import/paste split on ",", "&", "feat.", "ft.", never "and", with chips in the review to merge back; "Movie / Album" as `{album}`, shown under the title, searchable, in smart filters and set requests; song length removed entirely; slot times, set totals and the set assistant's target from tempo x the bars of each slot's played passes via `SongTimeline`; no tempo = unknown, and every total that includes it flagged incomplete). Built on: **R167** (one `SongTimeline`; nothing outside it computes chord lengths; explicit `{tempo}` inserts), **R153** / **R157** / **R163** (the set composer, `RomanNormalizer`, "code results win" in paste refinement), **R158** P8-1 Q8 (the near-duplicate score over title, artist and content), **R109** (already-ChordPro files import byte-for-byte), **R122** / **R149** (slot arrangements and pass modes), **R85** / **R86** / **R105** (breaks, changeover, intermission), **R113** (test budget), **R39** (design directions before new UI), and the owner's romanized Hindi rule (autocorrect and spell-check off in name fields; no AI step "corrects" a name). The clean-state rule is the R170 cleanup precedent: commits `d234a4e` (decision-log entries only about a discarded feature are dropped, mixed entries keep only their kept content, R-numbers unchanged), `abf097c` (phase specs, research and release docs keep only kept features) and `77da825` (code comments name only kept features).

**Build order:** three sessions (section 15). **P8-8a** (core for artists and Movie / Album) may start now: it touches SegueCore only and runs beside P8-7d. **P8-8b** (their UI) starts after **P8-7d** has landed, because both edit the song card and editor area. **P8-8c** (time from the timeline, the removal, the docs cleanup, guide and E2E) follows P8-8a and **P8-7e** (both edit the stage: `LiveSession`, `LiveView`), and lands its guide edits after P8-7f's guide pages. All before the R140 store media pass (the Welcome songs and screenshot seeds change here). Index: `README.md` in this folder.

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling workstreams (P8-7d/e/f) edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks, keep the tree compiling between steps. `docs/release/walkthrough.md` is being edited by someone else as this spec is written: section 6's cleanup edits it hunk by hunk, never by overwriting the file.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); tricky pure logic (the splitter, the artist edit, slot time, the lexicon, the matcher) gets table-driven in-process tests; UI behaviour gets in-process SegueUI tests. Exactly **one** new XCUITest class for the workstream (section 13.5, in P8-8c). At the end of each session ONE `make quick`, plus ONE `make e2e-one` per existing UI test class the session changed (section 13.6 lists them). No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- Before using any Apple API not already in the codebase, run the `apple-api-check` skill.
- Ryan's real library is never opened by a test or a session. Section 7's checks run on a copy (section 7.3).
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any section 17 question still open when a step reaches it.

## 1. Goal

A Bollywood song usually has several singers and comes from a movie. Today Segue keeps the first artist only in every field you can edit, has nowhere to say "Kalank", and asks you to type or time a song length that is wrong the moment you arrange the slot. After P8-8: artists are chips, "Movie / Album" sits under the title and is searchable and filterable, and a slot's time is worked out from the song's tempo and the bars actually played, so an arranged slot (skip the second verse, chorus x2) times itself.

**In scope (R172):** an ordered artist list edited as chips (byte-identical files until edited); "A, B" everywhere; any-artist matching in search, smart filters, the set composer, the set assistant and the near-duplicate check; the deterministic artist splitter on paste and convert-import with merge-back chips in the review; the AI refinement never inventing, splitting differently or re-spelling an artist; `{album}` as "Movie / Album" (editor, under the title, FTS, smart filters, set requests); the index version bump; removing song length (field, `{duration}` reading, columns, preview, "Time it", slot lengths, rehearsal timing samples, length analytics, the Length smart filter condition); slot time from `SongTimeline`; totals and the assistant on slot time; unknown time and the quick tempo affordance; auto-scroll on stage reading the same time; the docs, guide, site and store cleanup; analytics; one E2E.

Also in scope (R173): the one-time move of the `timings/` folder to the Trash with a note (5.8); the one-time library cleanup that offers to remove `{duration}` lines (5.7); the Gig Log's per-song played times removed (5.1).

**Unchanged:** break rows and their intermission, changeover, the setlist target and the "45 min" request (they are set times, not song lengths); the gig's own start and end time and the show-ended duration bucket (the show's length); `{tempo}` / `{time}` / `{key}` handling and P8-7's timeline layers; tap tempo on the song card; P8-7b's Insert Tempo Change Here.

## 2. Current behaviour (verified 2026-10-31)

### 2.1 Artists and album

- **Model:** `Metadata.artists: [String]` is already an ordered list, one per `{artist}` directive in source order (`ChordPro/SongDocument.swift:41-42`, collected by `SongDocument+Derived.swift:134`). `{album}` is read but has no field: it lands in `Metadata.extra["album"]` (`extraNames`, `SongDocument+Derived.swift:102-105`; `addExtra`, 147-150).
- **Writes keep only the first:** `SongCardWrite.artist` (`SegueUI/SongCard/SongCardModel.swift:68-70`) is `.setDirective(name: "artist", ...)`, and `EditPlanner.setDirective` rewrites only the **first** matching line (`SegueCore/Sources/Editing/EditPlanner.swift:180-183`). Editing the artist of a two-artist song rewrites line 1 and silently leaves line 2. `SongCardValues.artist` is `artists.first` (`SongCardModel.swift:39`); the library heading reads and writes the first artist only (`Library/SongDetailPane.swift:158-191, 239-241`), so a second artist is never shown there. Swap Title and Artist uses the first artist (`Paste/PasteReviewItem.swift:146-175`); paste analytics compare the first artist (`Paste/PasteAnalytics.swift:95`); the AI eval scores the first (`SegueAI/Sources/AIEval/PasteEvaluator.swift:89`).
- **Displays that already join:** `SongSummary.artist` ("A, B", `Rendering/SongSummary.swift:20-26`) for library rows (`Library/LibraryViews.swift:436`) and the stage quick search (`Live/QuickSearchOverlay.swift:218`); `SongSummary.subtitle` for the rendered page header (`SongSummary.swift:66-77`, `Rendering/SongPageView.swift:29-31`); `RenderHeader.artists` (`Editing/RenderModel.swift:81`).
- **Completions:** `LibraryViewModel.knownArtists` counts whole stored values (`SongCard/LibraryViewModel+SongCard.swift:88-100`), offered by the card's Artist field (`SongCard/SongCardView.swift:85-125`) and the heading editor.
- **Index:** `IndexedSong.artist` is the artists joined with ", " (`Library/SongFiles.swift:102`), so FTS already finds any artist word. No album column. `SongIndex.schemaVersion = 3`, stored version `schemaVersion * 1000 + RomanNormalizer.version` (`Library/SongIndex.swift:54-64`; columns 67-72; tables 116-151; upsert 218-248).
- **Filters:** `SongFilter` and `SmartFilterConditions` have no artist or album condition (`Library/SongFilter.swift:16-43`, `Library/SmartFilter.swift:52-70`).
- **Set composer:** `SongMatcher` scores titles and first lines only, "never lyrics bodies, artists or tags" (`Library/SongMatcher.swift:70, 104`; tiers `MatchTier` at 4; `MatchCandidate` 56-79).
- **Set assistant:** chips `SetChip` (`SetAssistant/SetRequest.swift:76-117`) have tags, keys, tempo, smart filters, slots, but no artist or album; the lexicon reads library tag and smart filter names with "from" for filters (`SetRequestLexicon.swift:249-300`); admission `SetBuilder.admits` (`SetBuilder.swift:78-100`).
- **Near-duplicate:** `artistSimilarity` is 1 when the normalized artist sets overlap (`Library/NearDuplicates.swift:204-207`, forms 233-235). A library song stored as `{artist: Vishal & Shekhar}` and a paste split into Vishal, Shekhar do not overlap today.
- **Ingest:** `MetadataExtractor` maps `Artist:` / `Singers:` / `Vocals:` lines and "X - Y", "X by Y", "X Chords by Y" headers to one artist value each (`Ingest/MetadataExtractor.swift:150-160, 190-270`), and `Album:` / `Film:` / `Movie:` lines to `.album` (160). `MetadataAssembly` dedups and writes one `{artist}` per value and `{album}` (`Ingest/MetadataAssembly.swift:65-81, 146-152`). Real fixtures: `paste/H06-scale-capo-tab.txt` "Artist: Zoya & The Village Band" (a band: a split is wrong), `paste/H08-codemixed.txt` "Late Night Dilli - DJ Saahil ft. Rhea" (a split is right), `paste/E03-inline-chordpro.txt` `{artist: June & the Lighthouse}` (an existing directive).
- **AI refinement:** a model artist is taken only when code found neither title nor artist (`Ingest/Refinement.swift:41-49`, R121), and only when it appears in the candidate lines, case-insensitively (`ModelPort/PasteRefiner.swift:86-103`); the returned value keeps the **model's** casing, not the sheet's. The prompt asks for one artist string (`ModelPort/Prompts.swift:68-73`).
- **Review sheet:** paste and files that need conversion share it (`Library/LibraryViewModel+Import.swift:10-23`); already-ChordPro files import directly and byte-for-byte (R109), except near-duplicates (R158 P8-1 Q4). The draft card is `SongCardView` in `.expanded` layout (`SongCard/SongCardDraft.swift`, `Paste/PasteItemColumns.swift:140-150`).

### 2.2 Song length

- **Reading:** `Metadata.duration` from the first `{duration}` (`SongDocument.swift:52-53`; `SongDocument+Derived.swift:135, 166-176`), with a diagnostic for an unreadable value (`182-183`, filtered at `Editing/SourceSnapshot+Internals.swift:156`). Undo names "Set Length" / "Clear Length" (`Editing/DocumentEditor.swift:209-212`). `LengthValue` parses typed lengths (`ChordPro/LengthValue.swift`).
- **Song card:** the Length token and `LengthField` with "Time it" (`SongCard/SongCardView.swift:179-205`, `SongCard/LengthField.swift`, `SongCard/TimeItModel.swift`); `SongCardField.length` (`SongCardModel.swift:18`). Set essentials are key + length + tempo (`Library/SongEssentials.swift:9-31`; dot help "used for set timing and flow", `SongCard/SetEssential.swift:9`), feeding the card dots, the row dots and the built-in "Missing essentials" filter (`SongFilter.swift:42, 109`).
- **Editor helpers:** `{` completion "Length" -> `duration: ` and the `/` menu "Length..." (`Editor/EditorSuggestions.swift:153, 376-381`), value header "Length: m:ss" (`464`, `names` at 458), completion wiring in `Editor/SourceEditorController+Completion.swift`.
- **Library:** no length column and no sort exist in the library list (`LibraryViews.swift:354-440` shows title, artist, key chip, proficiency); the length shows in the library **preview** through the song card strip's Length token, and in the builder's library column meta "G · 96 · 3:40" (`Setlists/BuilderLibraryColumn.swift:386-394`). Nothing to remove for sort.
- **Set timing:** `SetlistTiming` (`Setlists/SetlistTiming.swift`) takes `lengths: [SongID: SongLength]` from `{duration}` (`directiveLength`, 254-257; `SongLengthSource` 18-27) or an arranged slot's own `arrangement.length` (193-206), and already never guesses: an unknown adds nothing, later starts read "≥", the total reads "≥38:20 + 2 unknown" (230-236). Builder glue: `SetlistTiming(setlist:songs:defaultChangeover:)` (`Setlists/SetlistEntryDisplay.swift:42-61`), the row's Length cell (`Setlists/SetEntryRow.swift:8, 56-57`), the header total and "N unknown" button (`Setlists/SetlistTimeline.swift:86-150, 304-366`), the missing-lengths list with its Length field and Open Song (`Setlists/MissingLengthsList.swift`, R88), the composer ghost's Length cell (`Setlists/SetComposerRowState.swift:75-92, 178-183`).
- **Arrange Sections:** "Length for this gig" with Time it and "Song: 3:40" in the footer (`Setlists/ArrangementEditorSheet.swift:351-379`), `ArrangementDraft.setLength` (`Setlists/ArrangementDraft.swift:66, 317-320`), "Set Slot Length" (`Setlists/SetlistBuilderView.swift:103-112`), stored as `arrangement.length` in the setlist file (`Library/SlotArrangement.swift:145-160, 232-253`).
- **Set assistant:** `AssistantSong.length` from `{duration}` (`SetAssistant/AssistantSong.swift:20-21, 60`), arranged slots' own lengths (`SetBuilder.withSlotLengths`, `SetBuilder.swift:173-195`), songs without one set aside under a length target and named (`leftOutNoLength`, 26-28, 199-235; R107), packing on lengths (`Packer.swift:30-60, 113-118, 166-301`); UI `Assistant/AssistantCommandBar.swift:193-235`, `Assistant/LeftOutLengths.swift`, `Assistant/SetAssistantModel.swift:49, 237-246`.
- **Smart filters:** a Length range condition (`SmartFilter.swift:66-67, 138-147`; `SongFilter.swift:36-38, 133-142`; editor rows `SmartFilters/SmartFilterDraft.swift:57, 110-117, 159-211`).
- **Stage auto-scroll:** speed from `{duration}`, or an arranged slot's `arrangement.length`, else a per-line tempo estimate, else a default (`Live/LiveSession+Viewport.swift:151-171`, `LiveLayout/AutoScroll.swift:5-13, 77-108`). R172 does not name it, but it is a song-length consumer (section 5.6).
- **Rehearsal timing samples:** every completed rehearsal song becomes a `DurationSample` (`ShowController.swift:48-49, 182-185, 205-210, 377-455`) sent to a `RehearsalTimingStore` (`AppModel+Shows.swift:322-336`) that writes `timings/<run ulid>.rehearsal.json` (`Shows/DurationSamples.swift`; `LibraryRoot.timingsDirectory` and `rehearsalSuffix`, `Support/LibraryRoot.swift:42-45, 76-77`). **Nothing in the app reads them**: `loadAll` / `loadReport` have no caller outside tests. The archive export includes `timings` (`Library/LibraryArchive.swift:13, 28`; Settings note "songs, setlists, shows and timings", `Settings/DataSettingsView.swift:31`). The end-of-rehearsal sheet says "Song timings are kept." (`Live/LiveView.swift:441`).
- **Seeds:** the four Welcome songs carry `{duration}` and `{tempo}` (`App/WelcomeLibrary/*.cho`); `App/Sources/Debug/ScreenshotSongs.swift`; fixtures `basic-verse-chorus.cho`, `live-very-long.cho`, `malformed-sections.cho`, `metadata-only.cho`; UI seeds in `UITests/SegueSetlistE2ESupport.swift` and `SegueLiveE2ETests+Support.swift:161`.
- **Analytics:** `FeatureKey.timeIt` (`Services/FeatureKey.swift:29-30`), its context note (`Services/AnalyticsContextEnvironment.swift:6-9`). The show-ended `DurationBucket` is the show's length, not a song's (kept).
- **Links:** `SegueLinks.unknownLengths` -> `/guide/running-time#unknown` (`App/SegueLinks.swift:63, 91`); `openSongForLength` (`SegueRootView.swift:306-308`).

### 2.3 The timeline

`SongTimeline.build(document:sections:units:timing:order:)` (`Library/Timing/SongTimeline.swift:270-293`): `order: nil` is the written song with `{chorus}` stubs written out; an arranged order is `ArrangementResolver.resolve(...)` -> `.applied(order:)` (`Library/ArrangementResolver.swift:44-74`), Skip passes left out; Chords-only and First-line passes play their full chords (P8-7 5.2). Per-chord `tempo` / `meter` from the positional maps; `seconds(at:factor:fallback:)` converts ticks to seconds per chord **with a 90 BPM fallback** for chords without a tempo (229-249), which P8-8 must never use. A caller that builds it from a record: `BassLine.context` (`Library/BassLine+Song.swift:14-36`: `SongSections.units(of:)`, `model.sections`, `prefs.timing` from `record.sidecar.bass.timing`).

## 3. Several artists

### 3.1 Model and names (SegueCore `Library/ArtistNames.swift`, pure)

`Metadata.artists` stays the model (already ordered). New:

```swift
public enum ArtistNames {
    /// "A, B" (the one display join; `SongSummary.artist` calls it).
    public static func display(_ artists: [String]) -> String?
    /// R172's deterministic split of one combined value, for import and paste only.
    public static func split(_ value: String) -> ArtistSplit
    /// Matching forms of a stored list: each value split as above, then
    /// `RomanNormalizer.normalize`; used for matching only, never for display or writes.
    public static func forms(_ artists: [String]) -> Set<String>
}
public struct ArtistSplit: Sendable, Hashable {
    public var original: String       // exactly as read
    public var parts: [String]        // in order; one element when nothing split
    public var separators: Set<ArtistSeparator>
}
public enum ArtistSeparator: String, Sendable, CaseIterable { case comma, ampersand, feat }
```

**Split rules:** separators are "," , "&", and the words "feat.", "ft." (the dot required) and "featuring" (case-insensitive, each a whole word; R172, R173), plus a `(feat. X)` / `(ft. X)` / `(featuring X)` parenthesis whose brackets are dropped. Never "and", "x", "with", "/" or "-" (section 17 Q7). Each part is trimmed of whitespace and of a leading or trailing separator; empty parts dropped; a part equal to an earlier one ignoring case and diacritics is dropped (first spelling kept). The parts keep the source's exact spelling and case: no capitalisation, no romanization change, no "correction". Table (`ArtistNamesTests`):

| Value | Parts |
| --- | --- |
| `Vishal & Shekhar` | Vishal, Shekhar |
| `Arijit Singh, Shreya Ghoshal` | Arijit Singh, Shreya Ghoshal |
| `DJ Saahil ft. Rhea` | DJ Saahil, Rhea |
| `Atif Aslam featuring Shreya Ghoshal` | Atif Aslam, Shreya Ghoshal |
| `Badshah feat. Aastha Gill & Neha Kakkar` | Badshah, Aastha Gill, Neha Kakkar |
| `Atif Aslam (feat. Shreya Ghoshal)` | Atif Aslam, Shreya Ghoshal |
| `Simon and Garfunkel` | Simon and Garfunkel (never "and") |
| `Salim-Sulaiman`, `Shankar Ehsaan Loy` | unchanged |
| `Featherstone`, `Daft Punk ft`, `A feat B` | unchanged (whole word, "feat" / "ft" with the dot only) |
| `arijit singh, Arijit Singh` | arijit singh (dedup keeps the first) |
| `, A ,, B,` | A, B |

### 3.2 `.cho` read and write

- **Read:** unchanged (one `{artist}` per name, any number). A legacy `{artist: Vishal & Shekhar}` stays one artist for display and editing; matching uses `ArtistNames.forms`, which splits it, so filters and the composer still find "Vishal" (section 3.5).
- **Write, new `EditOperation.setArtists([String])`** (`Editing/DocumentEditor.swift` + `EditPlanner.setArtists`): let `E` be the song's `{artist}` lines in source order (`snapshot.directiveLines(named: "artist")`) and `A` the new list (each value cleaned as `SongCardWrite.cleaned` does: trimmed, no "}" or newline; empties dropped).
  - For each `i < min(|E|, |A|)`: if `E[i]`'s value equals `A[i]`, the line is untouched (bytes kept); else only its value is re-spelled (`DirectiveLine.replacingValue`, its spelling and position kept).
  - Extra `A` values: inserted as canonical `{artist: X}` lines right after the last existing `{artist}` line, else after `{title}`, else after the leading metadata directives (`setDirectiveLine`'s rule).
  - Extra `E` lines: deleted (with their line ending).
  - `A == E` produces no edit and no undo step. One undo step "Set Artists" otherwise. A file is byte-identical until someone edits its artists: no step of P8-8 rewrites `{artist}` lines on open, index, save of another field, or migration.
- `SongCardWrite.artist(_:)` is replaced by `SongCardWrite.artists(_ list: [String]) -> EditOperation`. `setDirective(name: "artist")` stays legal (P8-8b's callers stop using it; Swap Title and Artist keeps it for the one-artist case, 3.6).

### 3.3 The chip field (SegueUI `SongCard/ArtistChipField.swift`)

- Chips in order (first = primary), each with an "x"; a trailing input. **Return or "," commits** the typed text as one chip, exactly as typed after trimming ("&" is literal in the editor: a duo typed by hand stays one chip; section 17 Q8). Backspace in an empty input selects the last chip, a second Backspace removes it. Drag to reorder; VoiceOver actions Move Left / Move Right / Remove. A chip whose text contains a separator shows a quiet "Split" button (one click: `ArtistNames.split`, one undo step, section 17 Q12).
- **Input rules (romanized Hindi):** an `NSTextField` wrapper reusing the field-editor settings of P8-5's `Setlists/ComposerTextField.swift` (continuous spell-check, grammar check, automatic spelling correction, text replacement, quote / dash substitution and text completion all off; `allowsUndo = false` so the window's undo is the edit's). Verify each property with `apple-api-check`. Nothing rewrites typed text.
- **Suggestions** from the library: `knownArtists` stays the distinct stored values, most songs first (`LibraryViewModel+SongCard.swift:88-100`). A legacy combined value such as "Vishal & Shekhar" is offered whole: it is one name until someone splits it. Matching for the suggestion list is a `RomanNormalizer.normalize` prefix match of the typed text against each name's words ("shreya goshal" offers "Shreya Ghoshal"); a suggestion is applied only by an explicit pick (↓ then Return, Tab, or a click), never by Return on typed text.
- Chips already present are not offered again; a typed duplicate (ignoring case and diacritics) is refused with a beep and the existing chip flashes.
- Writes `SongCardWrite.artists` through the host's `perform`, one undo step per commit, remove, reorder or split.
- Where it appears: section 3.6.

### 3.4 Display

`ArtistNames.display` ("A, B") everywhere a song is named with its artists: library rows, the library heading (today first-only), the rendered page header, the stage quick search, the near-duplicate review line "Looks like 'X' by A, B in your library" (`PasteReviewItem.swift:100-102`), the composer status lines. The stage header is unchanged.

### 3.5 Matching any artist

| Feature | Change |
| --- | --- |
| Library search (FTS) | none: the joined column already holds every artist word. A test pins "shekhar" finding a song with `{artist: Vishal}` `{artist: Shekhar}` and one with `{artist: Vishal & Shekhar}`. |
| Smart filters | new condition `artists: [String]` ("Artist is any of"): a song matches when `ArtistNames.forms(song.artists)` intersects the forms of the listed names. Compiles to `SongFilter.artists: Set<String>` (forms). The editor row offers library artist names (3.3's list) as token suggestions. |
| Set composer | `MatchCandidate.artists`; two additions to `SongMatcher` (3.5.1). |
| Set assistant | chips `.artist(String)`; lexicon in 3.5.2; `SetBuilder.admits`: any artist chip matches (any of), ANDed with the other kinds. Applies to `SetRequest.songFilter` (library and stage NL search) too. |
| Near-duplicate | `NearDuplicateIndex.artistForms` becomes `ArtistNames.forms` (split first), so a legacy combined value meets its split form. No other change to the score (R158 P8-1 Q8). |

#### 3.5.1 Composer (amends P8-5 section 6, which said "never artists")

- **Artist qualifier:** in the title tiers, trailing query words that all match words of one of the candidate's artist forms (form N, the last word may be a prefix of 4+ letters) are set aside before scoring the title, and do not count as uncovered: "tum hi ho arijit" -> Tum Hi Ho (exactTitle) and, between two songs titled "Tum Hi Ho", the one by Arijit Singh first. A qualifier never rescues a query whose remaining words match no title (no title match = no candidate).
- **Artist tier (new, lowest):** when no title or first-line tier matches and the whole query matches the leading words of an artist form (one or more words, prefix rule as above), every song with that artist is a candidate, tier `artist`, base 40, band `weak`, ordered by title; status line "By Arijit Singh". Only when the query has 4+ letters (so "a" does not list a whole library).
- Ordering, bands and the key token rule (P8-5 6.3-6.6) are otherwise unchanged; `MatchTier` gains `.artist` after `.firstLine`. Movie / Album is not matched by the composer.

#### 3.5.2 Assistant lexicon (`SetRequestLexicon`, amends P3-7)

- The lexicon is built with the library's artist names (`ArtistNames.split` parts of every stored value, plus legacy whole values) and album names, using the same `nameWords` / `keys` folding as tags (RomanNormalizer-tolerant).
- **Artist:** "by <name>" anywhere ("ballads by arijit"), or "<name> songs" ("arijit songs"). A name matches a full artist name or the leading words of exactly one artist name ("arijit" -> Arijit Singh; "shreya" with two Shreyas matches neither and stays leftover). Several artist chips: any of them.
- **Album:** "from <name>" (smart filter names are tried first, as today at `SetRequestLexicon.swift:258-263`; then album names), "songs from the movie <name>", "<name> songs" when no artist claims it. Several album chips: any of them.
- Negation follows tags ("no arijit", "not from kalank" -> excluded chips) through `negatorBefore`, as `readNames` does for tags.
- The async model pass may not propose artist or album chips (its vocabulary stays as it is; code finds names or nothing).

### 3.6 Where artists are edited

- **Song card, expanded** (Start blank, the paste and import review's draft card): Title field, then the Artist chip field (label "Artists"), then "Movie / Album" (section 4).
- **Library heading** (`SongDetailPane`): the artists line shows "A, B"; double-click (or Edit Artists) turns it into the chip field in place; Escape or focus leaving ends editing (each chip commit already wrote). The Movie / Album line under it edits in place the same way.
- **Editor:** the song strip gains an Artists token and a Movie / Album token (popovers holding the same field) for an existing song; a new song shows the expanded card as today.
- **Swap Title and Artist** (review sheet): enabled only with exactly one artist; with two or more it is disabled with the help "Swap works with one artist".
- The exact placement is step 0's design pick (section 11).

### 3.7 Import and paste split

- `MetadataAssembly.add(.artist(value))` (`MetadataAssembly.swift:146-149`) splits the value with `ArtistNames.split` and appends each part (dedup as today), **for values read from credit lines and headers only**. A value that came from an `{artist}` directive in the source (`collector.directiveFields`) is kept whole: the source already said what one artist is (fixture E03 "June & the Lighthouse" stays one; section 17 Q5).
- `IngestResult` gains `artistSplits: [ArtistSplit]` (only splits with 2+ parts), carried through `reassembled` and `Refinement.apply`.
- Already-ChordPro files keep importing byte-for-byte (R109): not split (section 17 Q5).
- **Review sheet:** under the artist chips, for each split, one muted line: "Split from 'Zoya & The Village Band' · Keep as one" (button). Keep as one replaces those parts with the original value in place (one `setArtists` edit of the review text, one undo step, the line disappears). The chips can also be edited like any chip field. The split line disappears if the user edits the artists by hand.
- Fixtures: the golden `.cho` of every paste fixture whose artist came from a credit line or header with a separator is regenerated, and each diff is reviewed by hand in the step commit (expected today: `H06-scale-capo-tab.cho` "Zoya", "The Village Band"; `H08-codemixed.cho` "DJ Saahil", "Rhea"; grep the inputs for "," "&" "feat." "ft." in artist positions and list each in the commit message). `paste/gold.json` is updated the same way.

### 3.8 AI refinement (R174: artists from code only)

- The model no longer reads or writes artists (R174: code parsing gets all 46 recorded pastes right and the model added nothing). `MetadataOutput`, `MetadataWire`, the MLX grammar and `Refinements` have no artist; `RefinedField` is the title only; the prompt asks for the title and key. The metadata call runs only when code found no title (`PasteRefiner.metadataTask`).
- `PasteRefiner.refinements` returns **the sheet's own spelling** of the matched title (the substring of the candidate lines it matched, case-insensitively), never the model's casing or spelling; a value not found verbatim is dropped. No model step reads or writes `{album}`.
- `PasteEvaluator` scores the artist **list** (exact, in order), which is code's; the FM recordings test pins that every refined result keeps code's artist list.

### 3.9 Index

Album columns (section 4.3) change the FTS table: `SongIndex.schemaVersion` 3 -> 4 (history line "4 = the album (Movie / Album) columns, P8-8"); every library rebuilds its index once on next open. Artists need no index change.

## 4. Movie / Album

### 4.1 Model and write

- `Metadata.album: String?` (the first `{album}`; derived from `extra["album"]`, which stays as it is for other readers). `SongCardWrite.album(_:)` = `.setDirective(name: "album", value: cleaned)`; blank clears. Single value (R172 names one field). A song with two `{album}` lines shows the first; editing rewrites the first (the setDirective rule).
- Label everywhere: **"Movie / Album"**; placeholder "Movie or album". Same input rules as the chip field's input (3.3): spell-check and substitutions off. Suggestions from the library's album values (normalized prefix), applied only by an explicit pick.
- The editor's `{` completion and `/` menu gain "Movie / Album" -> `album: ` (`EditorSuggestions.swift:146-154`, `.value("album")` with aliases `movie`, `film`, `album`) and the Start blank template (`Editor/SongEditorViewModel.swift:421`) is unchanged (no empty `{album}`).

### 4.2 Display

- **Library rows:** under the title, the secondary line becomes "A, B · Kalank" (artists, then the album, `·`-separated, muted, truncating the album first). No artist: "Kalank".
- **Song header** (the library heading and the rendered page, `SongSummary.subtitle` / `RenderHeader`): `RenderHeader.album`; the line reads "A, B · Kalank  ·  G, capo 2, 96" on the rendered page; in the library heading the album is its own line under the artists (editable in place, 3.6). The future PDF reads the same header. The stage header is unchanged (section 17 Q11).
- **Stage quick search** results: album after the artist; the placeholder becomes "Search title, artist, movie, first line or tag".

### 4.3 Search

`IndexedSong.album`; FTS gains `album`, `norm_album`, `loose_album` (bm25 weight 5, like artist), the three column lists and `rankExpression` updated (`SongIndex.swift:67-72`), `songs` table unchanged. Tiers 1-3 search it; tier 4 (edit distance) stays on titles and first lines. Version bump in 3.9.

### 4.4 Smart filters and set requests

- Condition `albums: [String]` ("Movie / Album is any of"), compared by `RomanNormalizer.normalize` equality of the whole value; compiles to `SongFilter.albums`. The editor row suggests the library's albums.
- Set requests: `.album(String)` chips (3.5.2); in `SetBuilder.admits` and `SetRequest.songFilter`.

## 5. Time only from the timeline

### 5.1 What goes

| Removed | Where (section 2.2) |
| --- | --- |
| `Metadata.duration`, `parseDuration`, the Duration diagnostic, "Set / Clear Length" undo names | `SongDocument.swift:52-53, 67, 77`; `SongDocument+Derived.swift:135, 165-176, 182-183`; `SourceSnapshot+Internals.swift:156`; `DocumentEditor.swift:209-212` |
| `LengthValue` | `ChordPro/LengthValue.swift` and `LengthValueTests` |
| The Length token, `LengthField`, `TimeItModel`, `SongCardField.length`, `.setLength` | `SongCard/*`, `SongCardAccessibilityID.swift`, `SongCardHost.swift` |
| `SetEssential.length` (essentials become key + tempo; dot help "Set essential: used to time a set and plan its flow") | `SongEssentials.swift`, `SetEssential.swift` |
| `{` completion and `/` menu Length items | `EditorSuggestions.swift:153, 376-381, 458, 464` |
| The builder library column's length in its meta ("G · 96") | `BuilderLibraryColumn.swift:386-394` |
| Slot length (Arrange Sections footer field, Time it, "Song: 3:40" hint, `ArrangementDraft.setLength`, "Set Slot Length", `SlotArrangement.length`) | section 2.2 |
| The Length smart filter condition | `SmartFilter.swift`, `SongFilter.swift`, `SmartFilterDraft.swift` |
| `DurationSample`, `DurationSampleSink`, `RehearsalTimingStore`, `ShowEnvironment.durations`, the controller's sample queue, `LibraryRoot.timingsDirectory` / `rehearsalSuffix`, "timings" in the archive | section 2.2; files policy in 5.8 |
| `FeatureKey.timeIt`, the analytics context note about Time it | section 2.2 |
| `openSongForLength`, `SegueLinks.unknownLengths` (renamed, 5.5) | `SegueRootView.swift:306-308`, `SegueLinks.swift:63, 91` |
| The Gig Log's per-song played times: `PlayedSong.duration` and the played row's length (R173; the gig's own start, end and the show-ended bucket stay) | `GigLog.swift:23`, `GigLog/GigDetailView.swift:256`, `GigText.length` if nothing else uses it |

### 5.2 Slot time (SegueCore `Library/Timing/SlotTime.swift`, pure)

```swift
public enum SlotTime: Sendable, Hashable {
    /// `seconds` at the tempo map; `bars` from the timeline's bar grid; `tempo` the BPM in
    /// effect at the first played chord; `estimated` when any played chord's length came
    /// from the rule layer (`TimingSource.rule`), shown as "~3:40" (R173).
    case known(seconds: TimeInterval, bars: Int, tempo: Double, estimated: Bool)
    case unknown(UnknownTime)
}
public enum UnknownTime: String, Sendable, Hashable, CaseIterable {
    case noTempo    // the song has no readable {tempo}
    case noChords   // nothing timed: no chords in the played passes
}
public enum SlotTimes {
    /// The whole song in written order (`{chorus}` stubs written out): a new slot, the
    /// assistant's candidates, the composer's ghost.
    public static func song(_ record: SongRecord) -> SlotTime
    /// A setlist slot: its arrangement's played passes when it resolves `.applied`, else the
    /// full song (an out-of-date arrangement plays the full song on stage, R122).
    public static func slot(_ record: SongRecord, arrangement: SlotArrangement?) -> SlotTime
    /// The rule for any timeline (also the stage's, 5.6).
    public static func time(of timeline: SongTimeline) -> SlotTime
}
```

- **Building:** `SongTimeline.build(document:sections:units:timing: record.sidecar.bass.timing, order:)` with the sections of `RenderModel(document:options: DisplayOptions())` (the list `SongSections.units(of:)` indexes, as `BassLine.context` does) and `order` nil (song) or the resolved `.applied(order:)` (slot). If a cheaper section builder gives identical indices, use it; prove it with a test that compares both on the fixture corpus.
- **Rule:** `chords` empty or `totalTicks == 0` -> `.unknown(.noChords)`; any timed, non-silent chord with `tempo == nil` -> `.unknown(.noTempo)` (the tempo map's initial value covers every chord once any `{tempo}` exists, so this means the song has none). Else `seconds = timeline.seconds(at: totalTicks, factor: 1)`; the `fallback` parameter is never reached and `SlotTimes` asserts so in debug. Round to whole seconds for display only.
- **Modes (R149):** a Skip pass is absent from the order and adds nothing; Full, Chords only and First line passes all count their full chords (they are played; only the stage shows less); "x2" is two passes and counts twice. Mid-song `{tempo}` and `{time}` changes are honoured by the maps. User corrections, grids and tap captures change the time because they change the timeline.
- **No placeholder ever:** an unknown time adds nothing to any sum and is never replaced by a default tempo, a per-line estimate or an average.

### 5.3 Set totals and breaks (`Setlists/SetlistTiming.swift`)

- `SetlistTiming.init(entries:times:target:changeover:)` with `times: [SetlistItemID: SlotTime]` (per slot, not per song: two slots of one song may be arranged differently). `SongLengthSource` becomes `.song` (full song timeline), `.arrangement` (an applied arrangement's passes) and `.intermission` (a break). `ItemTiming` gains `unknown: UnknownTime?`; `PartTiming` and the whole set keep `unknownItemIds`.
- Arithmetic is unchanged: starts accumulate known times; a changeover after every song but the last of each part (R86); a break's intermission counts in the whole total only (R105); an unknown adds nothing and makes every later start and every total that includes it a lower bound: "≥13:50", "≥38:20 + 2 unknown", "2 unknown" (the existing notation, which is R172's "flagged as incomplete"). The part totals flag only their own unknowns.
- `SetlistTiming(setlist:songs:defaultChangeover:)` (`SetlistEntryDisplay.swift:42-61`) computes each slot's `SlotTimes.slot` through the cache (5.9).
- **Rows:** the column header and cell become **Time** (section 17 Q10); a known time reads "3:40" with the help "96 BPM, 72 bars"; a time that rests on any default chord length (any played chord timed by the rule layer, `TimingSource.rule`) reads "~3:40" with ", chord lengths estimated" added to the help (R173, section 17 Q6). So `SlotTime.known`'s `estimated` is true when **any** played chord is rule-timed, not only when every one is (5.2); a set total that includes an estimated slot also reads "~" (before any "≥"), and the composer ghost's cell the same; unknown reads "--:--" with the help "No tempo" or "No chords to time". The arranged mark is unchanged.
- **Header:** the total and target as today; the "N unknown" button opens the list in 5.5. VoiceOver: "38 minutes 20 seconds so far, incomplete: 2 songs have no time".
- **Composer ghost:** the Time cell shows `SlotTimes.song` of the shown candidate (cached), "-" when unknown (never a guess).

### 5.4 Set assistant (`SetAssistant/*`)

- `AssistantSong.length` becomes `time: TimeInterval?` plus `unknownTime: UnknownTime?`, filled by the caller: `AssistantLibrary(records:playStats:filters:now:times:)` takes `times: (SongRecord) -> SlotTime` (the UI passes the cache; tests pass `SlotTimes.song`). `withSlotLengths` becomes `withSlotTimes`: a kept or re-picked arranged slot counts its arrangement's time (`SlotTimes.slot`).
- Under a length target ("45 min", or the setlist's target), songs with an unknown time are left out and named, as R107 did for lengths: `leftOutNoTime`, the bar's note "2 songs left out: no tempo" ("no time" when the reasons differ). Packing (`Packer`) is unchanged arithmetic over `time`. The target itself and the tolerance are unchanged.
- The left-out list (`Assistant/LeftOutLengths.swift` -> `LeftOutTimes.swift`) uses the rows of 5.5.

### 5.5 Unknown time and adding a tempo quickly

- **The list** (`Setlists/MissingLengthsList.swift` -> `MissingTimesList.swift`, ids `segue.setlist.missingTimes*`): one row per unknown slot in set order. **No tempo:** title, an inline Tempo field (`TempoEditorView`'s parsing via `SongCardWrite.tempo`, with its Tap button and `TapTempo`), Open Song. Return writes the song's `{tempo}` through `library.editSongSource(id:_:)` (one undo step per song in the library's undo, as the length rows do today); the row leaves the list and every total updates. **No chords:** "No chords to time" and Open Song. The list's help button links to `/guide/running-time#unknown` (`SegueLinks.unknownTimes`, keeping the anchor so the site routes and the app's link table stay in step).
- **Arrange Sections footer:** "Time for this gig: 2:40" (read-only, the draft's `SlotTimes.slot`, live as passes change), or "No tempo" with a "Set Tempo..." button opening the same Tempo field in a popover (writes the song file, not the setlist; the help says "Sets the song's tempo"). Replaces the Length field, Time it and the "Song: 3:40" hint.
- **Which write:** a song-level tempo is `setDirective(name: "tempo")`, which writes the canonical `{tempo: 96}` line after the leading metadata, the same `DirectiveLine.canonical` P8-7b's `insertDirective` writes. P8-7b's "Insert Tempo Change Here" (mid-song) stays as it is in the editor; the song card's Tempo token stays the per-song entry point.
- **Songs without a tempo elsewhere:** the card's dashed Tempo token with its dot (an essential), the rows' quiet dot and "Missing essentials" as today.

### 5.6 Stage auto-scroll

`ScrollSpeedInput.duration` becomes `time: TimeInterval?` = `SlotTimes.time(of:)` of the stage's own timeline for the item being shown (the played passes P8-2 lays out, the arrangement only when it is applied, as `LiveSession+Viewport.swift:157-162` decides today); `ScrollSpeedSource.duration` becomes `.timeline`. Without a known time it falls back as today to the per-line tempo estimate (a chordless song with a tempo); a song with no tempo starts at the default speed, adjusted with [ and ] as today, and the stage shows a quiet hint to add a tempo (R173). The stage builds the timeline once per song preparation (P8-7 5.8), never per frame. This is a behaviour change on stage that R172 does not name (section 17 Q13).

### 5.7 `{duration}` in files

Ignored on read: no field, no diagnostic, no completion, no index column. The line stays in the file byte-for-byte; no edit, save or import removes it; Text mode shows it as an ordinary directive.

**One-time library cleanup (R173, section 17 Q14):** the first time a library is opened with this build and any song holds a `{duration}` line, Segue offers once (a dismissable note: "Song length is now worked out from tempo. Remove the old length lines from N songs?" with Remove and Not Now) to remove them. Remove deletes each `{duration}` line (with its line ending) and nothing else, one library undo step for the whole batch, read-only songs skipped. Not Now and Remove both record the offer as made in the library's `.segue/` state, so it never appears again for that library; the offer also stays reachable as a library menu command for later. No other line of any file changes. Welcome songs and app-owned seeds lose their `{duration}` lines in the bundle (P8-8c); copies already in users' libraries are untouched.

### 5.8 The `timings/` folder

- New builds never create, write or read `timings/`; rehearsals record nothing beyond the show file they already write.
- An existing `timings/` folder **moves to the Trash once on upgrade** (R173, section 17 Q2): the first open of a library with this build moves the whole folder with `FileManager.trashItem` (recoverable from the Trash, never deleted), then shows a one-time note: "Rehearsal timings are no longer used. The old timings folder was moved to the Trash." A failed move (permissions, no Trash on the volume) leaves the folder exactly as it is and says nothing; it is tried again on the next open. No "unreadable file" report.
- The archive export (`LibraryArchive.includedFolders`) drops "timings"; the Settings note reads "One zip of your songs, setlists, shows and filters".
- Ryan's library has such files: P8-8c's last step tells the orchestrator, for Ryan, that the folder is in the Trash after the first open and can be restored from there.

### 5.9 Cost and caching

`SlotTimes` needs a `RenderModel` and a timeline per song. A `SongTimeCache` (`@MainActor`, SegueUI `Library/SongTimeCache.swift`) on the library view model memoises `SlotTime` per (song ID, content hash, sidecar timing, arrangement), dropped when the record changes; the set builder, composer and assistant read through it. The assistant computes times only for the songs its request admits, not the whole library. Step 7 records, in its commit message, the cold cost of `SlotTimes.song` for the 2,000-song generated library and for one 20-slot set (debug build); no timing assertion in any suite.

## 6. Removing the docs and mentions (clean-state rule)

After P8-8c nothing in the repo describes song length, "Time it", slot lengths or rehearsal timings as a feature, except R172 itself. Follow the `d234a4e` / `abf097c` / `77da825` precedent:

- **Decision logs:** in `docs/release/decisions.md`, drop entries that concern only the removed feature (R78, R88, R91, R107) with survivors' R-numbers unchanged, and trim mixed entries to their kept content (the line-46 note, R71 "length", R80's card fields, R81's value pickers, R110's essentials, R122's slot length, any later mention found by grep). In `docs/decisions.md`, lines 46 and 135-136. Keep R172 whole (section 17 Q1).
- **Specs:** `docs/phases/3-workstreams/P3-5-durations.md` is removed (`trash`), and every link to it updated; P3-6, P3-7, P3-9, P3-10, P3-12, P3-16, `docs/phases/2-interfaces.md`, `3-ai-entry-and-assistant.md`, P8-2, P8-3, P8-4, P8-5 (its ghost "key and length", the E2E's `{duration}` seeds, the matcher's "never artists" now amended), P8-6, P8-7 lose length lines; `docs/00-vision.md:41, 45-46` (auto-scroll "duration/tempo-based" becomes "timeline/tempo-based"; the Library row drops lengths; the assistant row keeps "a target length"). Release specs: WS2b, WS3 (row 8 vocabulary), WS4 (`#running-time` at 1082), WS5 (166, 175, 234, 240, 508, 516), WS6, `app-store-connect.md:166, 175`, `docs/release/README.md`, `open-questions.md`, `walkthrough.md` (hunk by hunk). Research docs (`docs/research/phase3-spikes.md`, `phase3-store-ai.md`, `phase8-time-model-and-fills.md`, `docs/release/research/04-store-listing.md`) lose lines that describe song length as a Segue feature; competitor descriptions and video "Length 15-30 s" rows are not about it and stay. `JOURNAL.md` is covered too (R173, section 17 Q15): its lines that describe song length, Time it, slot lengths or rehearsal timings as a feature are trimmed the same way.
- **Guide** (section 10), **website** (`website/index.html:137` aria-label "key, capo, length and start time" -> "key, capo, time and start time"), **store** (`store/screenshots.json`, the listing copy in WS5 / app-store-connect), `content/changelog.json:16` (the draft 0.5 highlight: "The song card: key, tempo, capo and tags as controls, nothing to memorise." plus one highlight for artists and Movie / Album), `guide/src/data/shots.json` ("length", "missing-lengths", "card-time-it" shots replaced).
- **Code comments and names:** every comment naming R91, R88, R107, `{duration}`, Time it or lengths as a feature (grep list in section 2.2 plus `ShowRecord.swift:66`, `ShowTypes.swift:127, 146`, `SmartFilter.swift:1-4`, `SongFilter.swift:3-7`, `SetBuilder.swift:1-6`, `SlotArrangement.swift:145-160`, `AutoScroll.swift:5-9, 33`). Test names and ids follow (`testPickArrangeBreaksAndMissingLengths`, `missingLengths*` ids).
- **The check** (P8-8c's last cleanup step, results in the commit message): `git grep -n -i -E 'duration|song length|lengths?\b|time it|timeit|timings|R91|R88|R107'` over `docs guide/src website store content Packages App UITests scripts`, every remaining hit justified in the message (show length, break length, target length, chord length, fill length, video length, `Duration` the Swift type, R172).

## 7. Migration and safety (the owner's real library)

### 7.1 What changes on disk, and when

| File | On open | On a later save |
| --- | --- | --- |
| `.cho` with one `{artist}`, `{album}`, `{duration}` | nothing (the one-time `{duration}` cleanup is offered, 5.7) | only the edited directive changes (3.2, 4.1); `{duration}` lines only when the user accepts the cleanup |
| sidecar | nothing | nothing new (no schema change) |
| `setlists/*.setlist.json` with `arrangement.length` | ignored | dropped when that setlist is next saved (section 17 Q3) |
| `filters/*.filter.json` with `length` | ignored (the filter matches without it) | dropped when that filter is next saved; the editor shows "The Length condition was removed in this version" until then (section 17 Q3) |
| `shows/*.show.json` (an arrangement snapshot with `length`) | ignored | never rewritten for this |
| `timings/` | moved to the Trash once, with a one-time note (5.8) | |
| `.segue/index.sqlite` | rebuilt once (version 4) | |

No schema version is bumped for setlists, filters or sidecars: no build that reads them has shipped (v0.5 is unreleased), and the new filter conditions are additive.

### 7.2 Safety rules

- No silent migration pass and no "upgrade library" step. Every change to a user file is a user edit with an undo step; the only batch edit is the `{duration}` cleanup the user accepts (5.7, one undo step). The `timings/` folder is moved to the Trash, never deleted (5.8).
- The splitter never runs on stored files; only on paste and convert-import (3.7) and the explicit Split button (3.3).
- A read-only song (newer sidecar, non-UTF-8 file) shows its artists and album but the chip field is disabled (as the card is today).

### 7.3 Proof on a copy (P8-8c, before the E2E)

Copy Ryan's library folder to the session scratchpad (never open the original), open the copy with the new build, and record in the step commit: the index rebuilt once; `git diff --no-index` (or a byte compare) of every `.cho`, sidecar, setlist, filter and show file against the original shows **no** change after open (other than `timings/` now in the Trash with the note shown once, and the `{duration}` cleanup offered once: answer Not Now here, then run Remove on a second copy and confirm only `{duration}` lines left), browse, opening a set, a rehearsal start and end, and an archive export; then edit one two-artist song's artists and confirm only its `{artist}` lines changed. If Ryan's library path is not known, ask the orchestrator for it (a manual answer from Ryan).

## 8. Analytics (non-PII, closed vocabulary, WS3)

Enums, booleans and buckets only: never names, titles, albums or typed text. New file `Services/AnalyticsEvent+Metadata.swift`; WS3 rows 29 and 30 (26 is reserved for the fill editor, 27-28 are P8-7's; take the next free numbers at build time); `ServicesVocabularyTests` extended.

| Signal | Params | When | Throttle | Question |
| --- | --- | --- | --- | --- |
| Row 29 `Segue.Song.artistSplit` | `segue.source` (`paste`, `import`), `segue.parts` (SmallBucket), `segue.separator` (`comma`, `ampersand`, `feat`, `mixed`), `segue.outcome` (`kept`, `merged`, `edited`) | review Accept, per accepted song with a split | daily per (source, separator, outcome) | Are R172's splits right, and which separator misfires (a high `merged` rate for `ampersand` means duos and bands) |
| Row 30 `Segue.Setlist.timed` | `segue.songs` (SmallBucket), `segue.noTempo` (SmallBucket), `segue.noChords` (SmallBucket), `segue.arranged` (SmallBucket), `segue.estimatedOnly` (Bool: every known slot is rule-timed), `segue.target` (`none`, `under`, `within`, `over`) | the builder leaves a setlist with 1+ songs | daily per setlist (count only, no id), per (target) | Does timeline time cover real sets, how many songs lack a tempo, do arranged slots and corrections matter |

- `FeatureKey` (row 8): remove `timeIt`; add `songArtists` (the chip field changed a list: editor or library context), `songAlbum` (Movie / Album set), `artistSplit` (the Split button), `tempoFromSet` (a tempo written from the no-time list, the assistant's left-out list or Arrange Sections: builder or assistant context).
- Row 24 (composer): `segue.tier` gains `artist`; new Bool `segue.artistWords` (an artist qualifier was used).
- Row 21 (assistant): Bools `segue.artistChips`, `segue.albumChips`; `segue.leftOut` (SmallBucket of songs left out for no time).
- `librarySnapshot`: `segue.noTempo` (SongBucket: songs without a `{tempo}`), to see how much of a library can be timed.
- Paste row 19's `segue.correction`: no artist term (artists are never AI-filled, R174).

## 9. Accessibility

- Chip field: each chip is an element "Arijit Singh, artist 1 of 2" with actions Remove, Move Left, Move Right (and Split when shown); the input's label "Add artist"; ids `segue.songCard.artists`, `.artistChip`, `.artistInput`, `.artistSplit`. Movie / Album: label "Movie or album", id `segue.songCard.album`.
- Review split line: "Split from Zoya and The Village Band. Keep as one, button."
- Time cells: value "3 minutes 40 seconds", "About 3 minutes 40 seconds" for a "~" time, or "Unknown, no tempo"; totals as in 5.3. Muted text meets AA in both themes.
- New UI joins the R79 accessibility walk.

## 10. Guide pages and site

- `song-card.mdx`: Artists chips (Return or comma, reorder, Split), Movie / Album, essentials "key and tempo"; drop Length and Time it and the `card-time-it` shot; the card shot's callouts become key, tempo, artists.
- `running-time.mdx` (keeps the slug; anchors `#breaks`, `#break-length`, `#changeover`, `#unknown`): "Each song's time comes from its tempo and the bars you play: Segue counts the bars of the chart (one bar per chord unless the chart or your chord timing says otherwise) at the song's tempo. An arranged slot counts only the passes it plays." `#unknown` becomes "Songs with no time": no tempo (type or tap one in the list) or no chords; the shot `missing-times`.
- `arrange-sections.mdx`: drop "Length for this gig"; "The footer shows this slot's time from the passes you play."
- `set-assistant.mdx`: "Songs with no time are left out"; requests by artist ("by Arijit", "Arijit songs") and movie ("from Kalank").
- `build-a-set.mdx`: the composer ghost's time; typing an artist after the title, or an artist alone.
- `paste-a-song.mdx` and `import-files.mdx`: several artists, the split and "Keep as one"; Swap needs one artist.
- `smart-filters.mdx`: Artist and Movie / Album conditions; no Length.
- `library-folder.mdx:24` search covers movies; `text-mode.mdx` lists Movie / Album, not Length; `keyboard.mdx` drops the Time it row and adds the chip keys; `index.mdx:12` tile "Key and tempo on the song card"; `chord-timing.mdx` one line: chord lengths also set each song's time in a set.
- Real screenshots (`make docs-shots` for the changed shots only, after P8-8c's UI lands); the full re-capture is R140's pass. Verify the guide's links from the app (`SegueLinks`) against the local build, and against the live site once deployed.

## 11. Design directions (step 0 of P8-8b, R39)

Two directions, light and dark, rendered in the session scratchpad `p8-8/` with real Hindi film songs (Kalank, Tum Hi Ho, a three-artist song) for Ryan to pick before step 5:

- **A - Credits in the heading:** library heading "Title / Arijit Singh, Shreya Ghoshal / Kalank", each line double-click-to-edit (chip field in place); the editor strip gains two compact tokens "Artists" and "Movie / Album"; the expanded card shows both fields under Title.
- **B - Credits as tokens everywhere:** the strip's first two tokens are "Arijit Singh +1" and "Kalank" (popovers with the chip field and the album field) in both the library and the editor; the heading shows them read-only.

Also rendered: the review sheet's split line, the set row Time cell (known, estimated help, unknown), the no-time list with a Tempo field, and the Arrange Sections footer. Recommendation: A (section 17 Q9).

## 12. Core, store and view model changes (summary)

- SegueCore: `ArtistNames` (3.1); `EditOperation.setArtists` + `EditPlanner.setArtists` (3.2); `Metadata.album` (4.1); `IngestResult.artistSplits`, `MetadataAssembly` split (3.7); `PasteRefiner` sheet spelling (3.8); `NearDuplicateIndex` forms (3.5); `SongIndex` v4 album columns (3.9, 4.3); `SongFilter` / `SmartFilterConditions` artists and albums, Length removed (3.5, 4.4); `MatchCandidate.artists`, `MatchTier.artist`, qualifier (3.5.1); `SetChip.artist` / `.album`, lexicon, `SetRequest.artists` / `albums`, `admits`, `songFilter` (3.5.2); `SlotTime` / `SlotTimes` (5.2); `SetlistTiming` per-slot times (5.3); `AssistantSong.time`, `withSlotTimes`, `leftOutNoTime` (5.4); `ScrollSpeedInput.time` (5.6); removals (5.1).
- SegueUI: `ArtistChipField`, card, heading, strip, review split line (3.3-3.7); Movie / Album field and displays (4); `SongTimeCache` (5.9); Time column, header, composer cell, `MissingTimesList`, `LeftOutTimes`, Arrange Sections footer (5.3-5.5); stage auto-scroll input (5.6); analytics (8).

## 13. Tests (R113 budget)

### 13.1 SegueCore, pure (Swift Testing, table-driven)

- `ArtistNamesTests`: the 3.1 table; `forms` of a legacy combined value equals the forms of its split; display join.
- `SetArtistsEditTests`: unchanged list -> no edit; one-artist file untouched byte-for-byte after editing its key; rename artist 2 of 3 changes only that line; add after the last `{artist}`, else after `{title}`, else at the top; remove; reorder; spelling of an existing directive kept; one undo step "Set Artists"; values with "}" or newlines cleaned.
- `MetadataAlbumTests`: `{album}` read, first wins, set and clear through `setDirective`.
- `IngestArtistSplitTests` + the regenerated paste goldens: H06 split, H08 split, E03 (directive) kept whole, a `Singers: A, B & C` credit line -> three, dedup, `artistSplits` carried through refinement.
- `PasteRefinerTests` (extend): a model "TUM HI HO" against a sheet "Tum Hi Ho" returns "Tum Hi Ho"; a model value not in the sheet is dropped; the refined artists are always code's (R174).
- `NearDuplicateTests` (extend): `{artist: Vishal & Shekhar}` vs a paste with Vishal, Shekhar scores artist 1.
- `SongIndexTests` / `LibrarySearchTests` (extend): album found in all three forms ("kalank", "kalnk" is not, tier 4 is titles only); the version is 4xxx and an old index rebuilds; "shekhar" finds both stored forms.
- `SmartFilterTests` (extend): artists any-of (split forms), albums any-of; a hand-written file with `"length": {...}` decodes, matches without it and is not rewritten by loading.
- `SongMatcherTests` (extend): "tum hi ho arijit" -> the Arijit Tum Hi Ho first among two; "arijit" -> artist tier, every Arijit song by title, status "By Arijit Singh"; "ari" (3 letters) -> no artist tier; a qualifier never rescues a non-title query; existing rows unchanged.
- `SetRequestLexiconTests` (extend): "ballads by arijit", "arijit songs", "from kalank" (a smart filter named Kalank wins), "songs from the movie kalank", "no arijit", ambiguous "shreya" stays leftover; `SetAssistantTests`: artist and album chips admit any-of and AND with tags.
- `SlotTimeTests`: 4/4 at 96 BPM, 64 one-bar chords = 160 s, 64 bars; `{time: 3/4}` at 90; mid-song `{tempo}` change; a chorus x2 adds its bars twice; Skip adds nothing; Chords only and First line count fully; an out-of-date arrangement times the full song; a `{chorus}` stub counted in written order; user `beats` corrections change the time and clear `estimated`; no `{tempo}` -> `noTempo`; lyrics only -> `noChords`; the 90 BPM fallback is never used (a song with no tempo never yields seconds).
- `SetlistTimingTests` (rewrite on times): per-slot times for two slots of one song; unknown flagged in the part and the whole total; changeover and intermission unchanged; "≥" starts.
- `SetAssistantTests` / `SetAssistantIntegrationTests`: left out for no time under a target, named; packing to a target over slot times; arranged kept slots count their passes.
- `AutoScrollTests` (extend): `.timeline` source from a known time; chordless song with tempo -> `.tempo`; neither -> `.fallback`.
- `ShowScenarioTests` / `ShowRecoveryTests` / `ShowStoreTests` (update): a rehearsal writes no `timings/`; a pre-existing `timings/` folder is moved to the Trash once on open (an injected trash function in tests) and the note is shown once; a failed move leaves it in place; the archive export has no `timings`.
- `DurationIgnoredTests`: a `.cho` with `{duration: 4:05}` opens without a diagnostic, its line survives every other edit byte-for-byte, nothing reads it.
- `DurationCleanupTests`: the offer counts songs with `{duration}`, Remove deletes only those lines (one undo step, read-only songs skipped), the offer is made once per library.
- `SlotTimeTests` also: one rule-timed chord among corrected ones sets `estimated`.
- `ServicesVocabularyTests`: the new names and values.

### 13.2 SegueUI, in-process

- `ArtistChipFieldTests`: field-editor properties off after begin-editing; Return and "," commit as typed; Backspace twice removes; a suggestion applies only on pick; a duplicate is refused; reorder and Split are one undo step each; a read-only song disables it.
- `SongCardTests` (update): no Length token; essentials key + tempo; Movie / Album writes `{album}`.
- `PasteReviewArtistSplitTests`: the split line shows for H06; Keep as one restores "Zoya & The Village Band" in one edit; the line disappears after a hand edit; Swap disabled with two artists.
- `MissingTimesListTests`: a no-tempo row, typing 96 writes `{tempo: 96}`, the row leaves, the total drops its unknown; Tap fills the field; a no-chords row offers only Open Song.
- `ArrangementEditorTests` (update): the footer time follows a Skip toggle; "Set Tempo..." writes the song.
- `SetComposerViewModelTests`, `SetAssistantUITests`, `SetBuilderPickTests`, `SmartFilterSessionTests`, `LiveModeTests`, `WelcomeSeedingTests`, `AutosaveTests` (update for the removals); `LengthEntryTests` removed.

### 13.3 Performance (no assertions)

The 2,000-song cold `SlotTimes.song` cost and a 20-slot set (5.9), recorded in the step 7 commit.

### 13.4 Eval

Paste artist accuracy (code only, R174; 3.8), recorded in the step 3 commit.

### 13.5 E2E: `SegueSongMetadataE2ETests` (new, one class, one test, P8-8c)

Fresh temp library (`SetlistE2E.makeRoot()`), seeded with three songs with chords and `{tempo}` (one 3/4) and one without a tempo; clean launch:

1. Paste "Late Night Dilli - DJ Saahil ft. Rhea" plus a chorded verse and "Movie: Dilli Nights": the review shows chips DJ Saahil, Rhea and the split line; click Keep as one; the chips read "DJ Saahil ft. Rhea"; Split again from the chip; Accept. The file holds two `{artist}` lines and `{album: Dilli Nights}`.
2. Library search "dilli nights" finds it; the row reads "DJ Saahil, Rhea · Dilli Nights".
3. In the editor, add an artist chip "Shreya" by typing "shre" and picking the suggestion; reorder; Undo once.
4. New setlist, ⌘L, type the four songs: the rows show times computed from tempo (assert the 3/4 song's exact "m:ss"), the no-tempo song shows "--:--" and the total reads "≥... + 1 unknown".
5. Open the unknown list, type 100 in its Tempo field, Return: the total has no "≥" and equals the expected sum including changeover.
6. Arrange Sections on one slot: Skip a verse; the footer time drops by the verse's bars; Done; the row's time matches.
Assert no `timings/` folder exists at the end. Add the class to `UITests/e2e-map.tsv` for `SongCard/*`, `Setlists/*`, `Paste/*` and `Library/Timing/SlotTime.swift`.

### 13.6 Existing UI tests changed (one `make e2e-one` each, in the session that changes them)

`SegueSongCardE2ETests` (Time it and length steps removed; P8-8c), `SegueSetBuilderE2ETests` (missing-lengths -> missing-times; P8-8c), `SegueAssistantE2ETests` (left out: no tempo; P8-8c), `SegueArrangementE2ETests` (slot length -> footer time; P8-8c), `SegueLiveE2ETests` (the timings assertion at 211-216 becomes "no timings folder"; P8-8c), `SegueSetComposerE2ETests` (seeds lose `{duration}`, the ghost's Time cell; P8-8c), the guide shots in `UITests/AppStore/GuideShots.swift` (card, time-it, missing-lengths; run with `make docs-shots` for those shots only).

## 14. Files owned

- New (SegueCore): `Library/ArtistNames.swift`, `Library/Timing/SlotTime.swift`, `Services/AnalyticsEvent+Metadata.swift`; tests named in 13.1.
- New (SegueUI): `SongCard/ArtistChipField.swift`, `SongCard/AlbumField.swift`, `Library/SongTimeCache.swift`, `Setlists/MissingTimesList.swift` (from `MissingLengthsList.swift` by `git mv`), `Assistant/LeftOutTimes.swift` (from `LeftOutLengths.swift`); tests in 13.2; `UITests/SegueSongMetadataE2ETests.swift`.
- Removed: `ChordPro/LengthValue.swift`, `SongCard/LengthField.swift`, `SongCard/TimeItModel.swift`, `Shows/DurationSamples.swift`, `LengthValueTests`, `LengthEntryTests`, `docs/phases/3-workstreams/P3-5-durations.md`.
- Hunks: every file listed in sections 2 and 5.1, the guide pages in 10, the docs in 6, `docs/release/specs/WS3-services.md`, `UITests/e2e-map.tsv`, the Welcome `.cho` files and `manifest.json` (the target stays), `App/Sources/Debug/ScreenshotSongs.swift` (tempos kept, `{duration}` gone), test fixtures.
- Not owned: P8-7's timeline internals (`Library/Timing/SongTimeline*.swift`: read, never changed; a needed change goes back to the orchestrator), the fill editor (`Editor/Fill/`), stage fills (P8-7e).

## 15. Sessions and steps

**P8-8a - artists and Movie / Album core** (SegueCore only; may run beside P8-7d)

1. `ArtistNames` (split, forms, display), `Metadata.album`, `EditOperation.setArtists`. Suites: `ArtistNamesTests`, `SetArtistsEditTests`, `MetadataAlbumTests`.
2. Ingest split and `artistSplits`; paste goldens regenerated and reviewed; `PasteRefiner` sheet spelling. Suites: `IngestArtistSplitTests`, the paste corpus suite, `PasteRefinerTests`.
3. `PasteEvaluator` artist lists and the code-only vs with-model numbers (13.4). Suite: the AIEval suite.
4. Matching: `NearDuplicateIndex` forms; `SongIndex` v4 album columns; `SongFilter` / `SmartFilterConditions` artists and albums (Length stays until P8-8c); `SongMatcher` qualifier and artist tier; lexicon chips and `admits` / `songFilter`. New enum cases (`MatchTier.artist`, `SetChip.artist` / `.album`) get their arms in every exhaustive switch, SegueUI included, in this same step so the tree keeps compiling (a minimal chip title is enough until P8-8b). Suites: `NearDuplicateTests`, `SongIndexTests`, `SmartFilterTests`, `SongMatcherTests`, `SetRequestLexiconTests`, `SetAssistantTests`.
5. Analytics row 29 and the `FeatureKey` additions (8), the WS3 rows. Suite: `ServicesVocabularyTests`. One `make quick`.

**P8-8b - artists and Movie / Album UI** (after P8-7d lands, and P8-8a)

0. Section 11's renders; Ryan picks a direction (wait for it before step 2).
1. `ArtistChipField` and `AlbumField` with the field-editor rules. Suite: `ArtistChipFieldTests`.
2. The card (expanded, strip tokens), the library heading, rows and quick search, `SongSummary` / `RenderHeader.album`, editor `{` and `/` items for Movie / Album. Suites: `SongCardTests`, render tests touching the header.
3. Review sheet: split line, Keep as one, Swap rule, paste analytics list compare, row 29 recording. Suite: `PasteReviewArtistSplitTests`.
4. Smart filter editor rows (Artist, Movie / Album); composer status "By ..."; assistant chips UI. Suites: `SmartFilterSessionTests`, `SetComposerViewModelTests`, `SetAssistantUITests`. One `make quick`; `make e2e-one` for any existing class this session changed (none expected).

**P8-8c - time from the timeline, the removal, the cleanup** (after P8-8a and P8-7e; guide hunks after P8-7f's pages)

1. `SlotTime` / `SlotTimes`. Suite: `SlotTimeTests`.
2. `SetlistTiming` on per-slot times; `SongTimeCache`; rows' Time column, header, composer cell. Suites: `SetlistTimingTests`, `SetBuilderPickTests`, `SetComposerViewModelTests`.
3. `MissingTimesList`, Arrange Sections footer, "Set Tempo..." (remove slot length and its draft action in the same step). Suites: `MissingTimesListTests`, `ArrangementEditorTests`.
4. Set assistant on times, `LeftOutTimes`. Suites: `SetAssistantTests`, `SetAssistantIntegrationTests`, `SetAssistantUITests`.
5. Stage auto-scroll on the timeline time. Suites: `AutoScrollTests`, `LiveModeTests`.
6. Remove song length: `{duration}` reading, `LengthValue`, card token, Time it, essentials, editor items, builder column meta, the Length filter condition (with the editor note of 7.1), `timeIt`; the one-time `{duration}` cleanup offer (5.7); the Gig Log's per-song played times (5.1). Suites: `DurationIgnoredTests`, `DurationCleanupTests`, `GigLogTests`, `SongCardTests`, `SmartFilterTests`, `SmartFilterSessionTests`, `EditorCompletionTests`.
7. Remove rehearsal timing samples; the one-time move of `timings/` to the Trash and its note (5.8); archive folders, Settings and stage copy; analytics row 30, the composer / assistant / snapshot params. Suites: `ShowScenarioTests`, `ShowRecoveryTests`, `ShowStoreTests`, `ServicesVocabularyTests`; record the 5.9 numbers.
8. Seeds: Welcome songs, screenshot songs, fixtures, UI seeds without `{duration}` (tempos checked so the Welcome Set has a full time). Suites: `WelcomeLibraryTests`, `WelcomeSeedingTests`.
9. Section 7.3's proof on a copy of Ryan's library.
10. Docs and mentions (section 6), with the grep check in the commit message.
11. Guide pages and site (section 10) with the changed shots.
12. `SegueSongMetadataE2ETests` and the 13.6 updates; ONE `make quick`, ONE `make e2e-one` per changed class. Tell the orchestrator, for Ryan: the `timings/` folder note (5.8) and that the app is ready to try. Launch the app at the end for Ryan's walkthrough.

## 16. Done criteria

- A song's artists are chips everywhere they are edited, stored one `{artist}` each; untouched files are byte-identical; "A, B" everywhere; library heading shows every artist.
- Paste and convert-import split on ",", "&", "feat.", "ft." (never "and"), the review offers Keep as one, directive values and already-ChordPro files are not split, and no model output adds, splits, merges or re-spells an artist.
- Search, smart filters, the composer, the assistant and the near-duplicate check match any artist, including legacy combined values.
- Movie / Album is `{album}`, shown under the title, searchable after the one index rebuild, a smart filter condition and a set request.
- No length field, `{duration}` reading, length column or preview, Time it, slot length, Length condition or rehearsal timing sample exists; `{duration}` lines stay on disk unless the user accepts the one-time cleanup; the `timings/` folder is in the Trash after the first open, with the note shown once; the Gig Log shows no per-song played times; a time resting on a default chord length reads "~".
- Slot times, set totals and the assistant's packing come from `SlotTimes` (tempo x the bars of the played passes, Skip adding nothing); a song with no tempo or no chords is unknown, never guessed, and every total including one reads "≥ ... + N unknown"; a tempo can be typed or tapped straight from the set's list and Arrange Sections.
- Analytics rows and keys as in section 8, closed vocabulary only, documented in WS3.
- The section 6 grep shows only justified hits; the guide, site and store copy describe the new behaviour.
- Every 13.1-13.2 suite passes; `make quick` green; `make e2e-one` green for `SegueSongMetadataE2ETests` and each 13.6 class; the proof of 7.3 recorded; the app launched for Ryan.

## 17. Closed questions

Closed by `docs/release/decisions.md` **R173** (Ryan, 2026-10-31). Where R173 differs from the original recommendation the body above follows R173.

1. **Decision-log cleanup.** Follow the `d234a4e` / `abf097c` / `77da825` precedent (drop R78, R88, R91, R107; trim mixed entries; R-numbers unchanged; R172 kept whole). R173 names no change, so the recommendation stands.
2. **`timings/` files.** *R173:* the folder moves to the Trash once on upgrade (recoverable), with a one-time note, and is excluded from the archive export (5.8). Differs from the recommendation (leave on disk).
3. **Stale `arrangement.length` and filter `length` keys.** *R173:* dropped on the next save of that setlist or filter (7.1), as recommended.
4. **Gig log played times.** *R173:* the Gig Log drops played times (5.1). Differs from the recommendation (keep). The gig's own start and end and the show-ended bucket are the show's length, not a song's, and stay.
5. **What the splitter applies to.** *R173:* pasted credit lines and headers only; `{artist}` directives and already-ChordPro files stay whole (3.7), as recommended.
6. **Estimated chord lengths.** *R173:* a slot time that rests on any default chord length shows as "~3:40" (5.3). Differs from the recommendation (no marker).
7. **More separators.** *R173:* ",", "&", "feat.", "ft." and "featuring" (3.1), as recommended.
8. **Comma in the chip field.** *R173:* a comma or Return commits a chip (3.3), as recommended.
9. **Design direction.** Not ruled by R173: P8-8b step 0 renders A and B and Ryan picks (section 11).
10. **Set row column name.** *R173:* "Time", as recommended.
11. **Movie / Album on stage.** *R173:* not shown on stage, as recommended.
12. **Split button on a legacy combined chip.** *R173:* a combined chip offers Split, as recommended.
13. **Stage auto-scroll.** *R173:* follows tempo times the played bars; with no tempo it starts at the default speed, adjusted with [ and ], with a hint to add a tempo (5.6).
14. **`{duration}` in Ryan's files.** *R173:* a one-time library cleanup offers to remove `{duration}` lines from charts (5.7). Differs from the recommendation (no cleanup).
15. **Research docs and `JOURNAL.md`.** *R173:* the cleanup covers every doc including `JOURNAL.md` (section 6). Differs from the recommendation (leave `JOURNAL.md`).
16. **Composer and assistant name rules.** *R173:* the composer accepts "by <artist>" and the assistant understands "by <artist>", "<artist> songs" and "from <movie>" (3.5.1, 3.5.2).
