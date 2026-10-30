# P8-5 - Set composer: type a set into a text row at the end of the set list

Phase 8 workstream (2026-10-30). Rulings: `docs/release/decisions.md` **R153**, **R157** (short-word spelling tolerance in `RomanNormalizer`, built here, section 6.8), **R158** (this spec's open questions closed, section 17), **R155** (build order). Related rulings: R84 (Pick / Arrange, Pick's checklist and keys), R85 (break rows, `Setlist.breakLabel(at:)`), R16 (builder undo, one step per action), R39 (design directions before building new UI), R79 (accessibility walk), R113 (test budget), the walkthrough rule "a song appears at most once per setlist" (enforced since commit 1d027df), and the owner's romanized Hindi rule (title and lyric fields have autocorrect and spell-check off; no AI step may "correct" romanized Hindi words). Reference specs for format and seams: `docs/phases/3-workstreams/P3-12-set-builder.md` (the builder this extends) and `P3-16-slot-arrangements.md`.

**Build order (R155):** all of Phase 8 ships before the v0.5 submission. P8-1 first; then P8-2, then P8-3; **this spec (P8-5) runs in parallel** with them and with P8-4a; P8-4b is blocked on research (R160). Index: `README.md` in this folder.

## Session rules

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools. Ignore `.build/`. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams (P8-2, P8-3, P8-4a) edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own hunks. Keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`). The matcher and parser are tricky pure logic and get table-driven in-process tests; UI behaviour gets in-process SegueUI tests; exactly one new XCUITest class (section 13). At the end of the workstream ONE `make quick` plus ONE `make e2e-one` for the new class (and for `SegueSetlistBuilderE2ETests` / `SegueE2ETests` only if the drop zone change in section 4.1 touched what they assert). No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency. The open questions were closed by R158 (section 17); the body reflects the answers.

## 1. Goal

A 12-song set is typed, not clicked: ⌘L, type a few letters of each song, Return, next. The best library match shows as a ghost completion with its key and length, romanized Hindi spelling variants find the right song, "in A" sets that slot's gig key in the same line, "---" splits the set, and a song already in the set is flagged instead of added twice. Target: typing plus one Return per song (section 3).

**In scope (R153):** the composer row at the end of the set list in both Pick and Arrange; ⌘L; ghost completion with key and length; Return appends and keeps focus (Things-style); ↑/↓ and Tab / ⇧Tab cycle alternatives; inline key token ("kesariya in A", "(Am)", "key of D") stored as `SetlistOverrides.transpose`, with the relative major or minor meaning no change (R158 Q2); "---" inserts a break; structural duplicate block; "No song matches"; the whole-line matcher; the R157 short-word rules in `RomanNormalizer` (search improves everywhere); analytics; accessibility; guide page.

**Declined in R153 - do not spec, build or stub:** paste a set from chat, placeholder slots for songs not in the library, gig templates, fill suggestions, drag to sidebar setlists, Play Again from the Gig Log, and the other click-reduction bundles (song entry, set editing, faster to stage). In particular, "No match" offers nothing else: no "Create song", no placeholder, no suggestion.

**Unchanged:** the library column stays for browsing (Pick's checklist, ⌘A, drag); Arrange's keys, the slot popover, break rows, undo, timing.

## 2. Current behaviour (verified 2026-10-30)

- **Set list:** `Packages/SegueUI/Sources/SegueUI/Setlists/SetEntriesList.swift`. Rows in a `LazyVStack` (44-60) followed by `dropZone` (278-301: dashed box "Tick songs in Pick, or drag them here" / "Drag more songs here", a `dropDestination` that appends, id `AccessibilityID.setlistDropZone`). The list is `.focusable()` with ↑/↓ moving the selection and ⌥↑/⌥↓ moving rows (`keyMove`, 79-98; key handlers 66-69). The same view is the right column in Pick and the whole width in Arrange (`SetlistBuilderView.swift` 30-84; Pick's library column 33-49, `SetEntriesList` 75-80).
- **Adding songs:** `SetlistsViewModel.add` (`SetlistsViewModel.swift` 89-98, one song, undo "Add Song") and `insert` (193-204, skips songs already in the set, one undo step through `mutate` 233-256). Store: `SetlistStore.insertSongs` (`SegueCore/Sources/Setlists/SetlistStore.swift` 237-256) creates entries with empty overrides; `addSong` (137) wraps it. There is no way to insert a song with overrides in one write today, so "add, then set key" would be two undo steps.
- **Breaks:** `SetlistStore.insertBreak(into:at:label:length:)` (`SetlistStore+Entries.swift` 50-75, label defaults to `Setlist.breakLabel(at:)`, renumbers automatic labels); view model `insertBreak(in:)` (`SetlistsViewModel+Builder.swift`) inserts after the Arrange selection, else at the end.
- **Pick's library column:** `BuilderLibraryColumn.swift`. `SearchField` (165-170, an `NSSearchField` wrapper, `Library/SearchField.swift`) with Return / ↓ moving focus to the first result (`focusFirstResult`, 184-187); search debounced 150 ms (`runSearch`, 229-246, sleep at 233) through `library.builderSearch` (`LibraryViewModel+Analytics.swift` ~51). Space ticks, ⌘A ticks every row shown.
- **Search:** `LibraryStore.searchWithTier` (`SegueCore/Sources/Library/LibraryStore.swift` 437-468) is all-words-AND over FTS: tier 1 originals (every word a prefix), tier 2 `RomanNormalizer` forms, tier 3 loose forms, and only when 1-3 find nothing, tier 4 edit distance <= 1 per query word of 4+ letters over normalized titles and first lines (`fuzzyMatches`, 399-413; `SongIndex.fuzzyCandidates()`, `SongIndex.swift` 287-303). It searches lyrics bodies too, ranks by bm25, and costs SQLite round trips per call, so it is the wrong tool for "which one song does this whole line name", which is why section 6 adds a scorer.
- **Normalization:** `RomanNormalizer` (`SegueCore/Sources/Library/RomanNormalizer.swift`): `words(_:)` (110, lowercases, folds diacritics, drops apostrophes), `normalizeWord` (79, the rule table at 49-71: `aa`->`a`, `ee`->`i`, `w`->`v`, `z`->`j`, `ph`->`f`, doubled letters collapsed, aspiration `h` dropped, `-ie`->`-i`, final nasal `n` dropped), `looseWord` (95, `e`->`i`, `o`->`u` in words of 5+ letters), `editDistance(_:_:limit:)` (182, internal to the Library module). The index stores `norm_title` and `norm_first_line` (`SongIndex.swift` 226-229); the first line is the first non-blank line of `plainLyrics` (`SongFiles.swift` 93-111).
- **Keys:** `SongKey(parsing:)` (`SegueCore/Sources/MusicTheory/SongKey.swift` 27-39) accepts `G`, `F#m`, `Bbm`, `Ebmin`, `C minor`, `Am`; the letter must be uppercase (`Letter(chartLetter:)`, `NoteSpelling.swift` 59). `SetlistOverrides.transpose` (`Setlists/Setlist.swift` 77-107) is semitones relative to the song as written and, when set, replaces the song's saved view transpose. The row's Key column shows `DisplayTransform.displayKey` (`Editing/DisplayOptions.swift` 113: written key transposed by `options.transpose + Capo.displayOffset(capo:mode:)`) via `SetlistEntryDisplay` (`Setlists/SetlistEntryDisplay.swift`); the slot popover shows the same key as "A · +2" and clamps transpose to -11...11 (`SetEntryEditor.swift` 118-135).
- **Menus:** `App/MenuShortcuts.swift` (`all`, 134-140). **⌘L is free**: no `MenuShortcut` or `.keyboardShortcut("l")` anywhere in the repo (grep, 2026-10-30). Setlist menu items live in `App/Commands/SetlistCommands.swift` (`buildingItems`, 50-75; `shownBuilder` / `editableBuilder` gating, 78-90). The clash test is in `SegueUI/Tests/SegueThemeTests/MenuAndAboutTests.swift`.
- **Analytics:** closed vocabulary in `SegueCore/Sources/Services/AnalyticsEvent.swift` (+ `AnalyticsEvent+Notes.swift` as the newest per-feature file, row 23), throttle rules in `AnalyticsEvent+Throttle.swift`, the table in `docs/release/specs/WS3-services.md` (rows 16-23 at ~307-310), the vocabulary test `SegueCoreTests/ServicesVocabularyTests.swift`. TelemetryDeck is reached through Segue's own client (WS3), never with free text.
- **Spell-check off pattern:** `Services/PlainTextEditor.swift` (25-27) turns off continuous spell checking and automatic correction on an `NSTextView`; SwiftUI fields use `.autocorrectionDisabled()` (e.g. `Live/QuickSearchOverlay.swift` 59).
- **E2E routing:** `UITests/e2e-map.tsv` (lines ~69 and ~88 map `Setlists/*` sources to the builder classes).

## 3. Before / after measurement

| | Today (P3-12 Pick, 12 songs) | Target (composer) |
| --- | --- | --- |
| Per song | click the library search (1), clear the previous query (1), type, Return to the first result (1), ↓ when the first result is wrong (~0.25 avg), Space to tick (1) | type, Return (1) |
| 12 songs | **47 measured** (53 with the break and Kesariya's key) plus typing | ⌘L (1) + 12 Returns = **13 actions plus typing** (+ one Tab / ↓ per song whose best match is wrong); **measured 14 with the break**, no Tab or ↓ |
| Gig key for a slot | click the row (1), popover stepper presses (2-4), Escape (1): ~5 per slot | 0 extra: "in A" is typed in the same line |
| Break | click a row (1), ⇧⌘B (1) | type "---", Return (1) |

Measured 2026-10-30: before, the section 13 set replayed through the real library search on the same 24-song library (every intended song was the first result, so no ↓: 3 actions for the first song, 4 for each later one = 47, +2 for the break, +4 for "in A"); after, `SegueSetComposerE2ETests` counts ⌘L + 13 Returns = 14 for 12 songs and the break, gig key included.

How it is measured:

- **Before (step 0):** one scripted walkthrough on the current build with the 12-song seeded library of section 13 (same set, same spellings), counting every non-typing key press and click; record the count in this section's table, replacing "~51" with the measured number.
- **After:** the E2E in section 13 types the same 12-song set and asserts it took exactly 13 non-typing actions (the test routes every non-typing key through one counting helper), plus the in-process corpus proving each line's first suggestion is the intended song (so no Tab is needed for that set).

## 4. UI and keyboard behaviour

### 4.1 The composer row

- **Where:** always the last row of `SetEntriesList`, after every entry (break rows included), in both Pick and Arrange. It replaces the dashed drop zone's position and **takes over its drop destination** (a library song dropped on it is appended, exactly as today), and its container keeps `AccessibilityID.setlistDropZone` so `SegueSetlistBuilderE2ETests` and `SegueE2ETests` drag targets keep working; the field itself gets a new id (section 11).
- **Anatomy (aligned with `SetEntryRow`'s columns, so the ghost reads as the row it will become):**
  - `#` column: the next song number, muted (e.g. "13"); blank while the line is a break.
  - Title column: the text field (Schibsted Grotesk semibold 16, ink) with the ghost completion (muted) and, under it, one muted status line when there is something to say (section 4.2).
  - Key, Capo, Length columns: the best match's values as the new slot would show them (muted, not ink): Key after the key token if one is typed, else the song's display key with no overrides; Capo as `SetlistEntryDisplay.capoText`; Length from `SetlistTiming.directiveLength`, "-" when unknown (never a guessed value). Start column blank.
  - Leading 4 pt edge: the colour of the part the row would join (`PartPalette`), dimmed.
- **Placeholder** (empty, unfocused or focused): "Add a song - type its name" with a trailing muted "⌘L" key hint (the hint is hidden while focused).
- **Ghost completion:** when the best match's title starts with the typed song text (compared after `RomanNormalizer.words` folding, ignoring case and diacritics), the rest of the title is drawn muted right after the caret ("Kesa|riya"). Otherwise the full title is drawn muted after a gap and an arrow: "kesriya  → Kesariya". The ghost never changes the typed text; nothing the user typed is ever rewritten or "corrected".
- **Read-only setlist** (`setlist.readOnly != nil`): the row shows "Read-only - this setlist was saved by a newer Segue" in muted text, no field, no drop target; ⌘L is disabled.
- **Empty set:** the row is the only row; the placeholder text is the empty-state prompt (the old "Tick songs in Pick, or drag them here" copy goes).

### 4.2 Row states

| Line typed | Ghost / cells | Status line | Return |
| --- | --- | --- | --- |
| empty | none | none | nothing |
| a song query with a match | best match + key + length | none, or "Close spelling" (fuzzy tier) / "From the first line: <first line>" (first-line tier) | appends the shown candidate, clears, keeps focus |
| a query whose shown candidate is already in the set | the candidate, with an "In set" badge in the Key column's place | "Already in the set at #4" (warning glyph, as `entryRepeat` styles it) | does **not** add; the existing row is selected and scrolled into view with a brief highlight; the typed text stays, all selected, so the next keystroke replaces it |
| a query with no match | none | "No song matches" | nothing (no beep; the row already says it) |
| a query + key token, song has a key | candidate, Key cell shows the gig key | none | appends with `overrides.transpose` set (section 7) |
| a query + key token, song has no key | candidate, Key "-" | "This song has no key, so 'in A' is ignored" | appends without overrides |
| "---" (section 5.1) | none; the row draws as a break preview ("Set 2", the label `breakLabel(at:)` would give) | none | appends a break row, clears, keeps focus |
| only punctuation / whitespace | none | none | nothing |

### 4.3 Keyboard

| Key | In the composer | Notes |
| --- | --- | --- |
| ⌘L (Setlist > Add Song by Name) | from anywhere in the main window while a builder is shown: focuses the composer, scrolls it into view, keeps the typed text | menu item, section 9 |
| Return | accept per section 4.2 | after an add: field cleared, focus kept, the set list scrolls so the new row and the composer are visible |
| ↓ / Tab | next alternative (wraps) | only while the line has 2+ candidates; with 0-1 candidates Tab is handled and does nothing (focus never leaves on Tab while text is present); with an empty line Tab / ⇧Tab move focus as usual |
| ↑ / ⇧Tab | previous alternative (wraps) | with an empty line, ↑ moves focus to the set list and selects its last row |
| ↓ on the set list's last row | focuses the composer | small addition to `keyMove` |
| Escape | 1st: close the alternatives list if open; 2nd: clear the line; on an empty line: focus moves to the set list | |
| ⌘Z / ⇧⌘Z | builder undo / redo (section 8.4) | the field editor's own text undo is off |
| ⌘A | selects the field's text | Pick's ⌘A (tick all shown) only applies when the checklist has focus, unchanged |
| ⌘1 / ⌘2 | switch mode; the composer keeps its text and focus | |

**Alternatives:** up to 5 candidates (section 6.5). Cycling changes the ghost and the Key / Capo / Length cells; a counter "2 of 5" appears at the trailing end of the title column while cycling. A compact list of the alternatives also drops down under the row from the first ↓ / Tab (direction B, R158 Q3; section 12). Typing any character resets the cycle to the new best match.

### 4.4 Mouse

- Clicking the row focuses the field. Clicking the ghost text or the "→ Title" accepts it (same as Return). Clicking the "Already in the set at #4" line selects that row.
- Drops: unchanged semantics, now on the composer row (appends).

### 4.5 Text input rules (owner rule, romanized Hindi)

The field is an `NSTextField` wrapper (like `SearchField`) whose field editor has, on `controlTextDidBeginEditing`: `isContinuousSpellCheckingEnabled = false`, `isGrammarCheckingEnabled = false`, `isAutomaticSpellingCorrectionEnabled = false`, `isAutomaticTextReplacementEnabled = false`, `isAutomaticQuoteSubstitutionEnabled = false`, `isAutomaticDashSubstitutionEnabled = false` (so "---" is never turned into a dash glyph), `isAutomaticTextCompletionEnabled = false`, `allowsUndo = false`. No model, AI or autocorrect step touches the typed text; matching normalizes only inside the comparison. Verify each property with the `apple-api-check` skill against the installed SDK before use.

## 5. Line grammar (pure, SegueCore `Setlists/SetComposerLine.swift`)

`SetComposerLine.parse(_ text: String) -> SetComposerLine`:

```swift
public enum SetComposerLine: Sendable, Equatable {
    case empty
    /// "---": a break row with the automatic label.
    case breakRow
    /// A song query, with the key token split off when one parses (`keyToken` keeps the
    /// raw text, for the full-line fallback in section 6.6).
    case song(query: String, key: SongKey?, keyToken: String?)
}
```

### 5.1 Break

The trimmed line consists only of dash characters (hyphen-minus, U+2013 en dash, U+2014 em dash) and counts at least 3 when a hyphen is 1, an en dash 2 and an em dash 3 (defensive: substitution is off, but a pasted or system-substituted dash still works). "--", "- -" and "--- x" are song queries; so is "--- Encore": a break takes no label from the line, and its label stays editable on the break row (R158 Q5).

### 5.2 Key token

Only at the **end** of the line, keywords case-insensitive, the key itself parsed by `SongKey(parsing:)` after upper-casing its first letter (so "in a", "in bb" and "in f#m" work: "A", "Bb", "F#m"). Forms:

| Form | Examples | Split |
| --- | --- | --- |
| `<query> in <key>` | "kesariya in A", "tum hi ho in Bb", "channa mereya in f#m", "pal in C minor" | query "kesariya", key A |
| `<query> (<key>)` | "kesariya (Am)", "tum hi ho (D)" | |
| `<query> key of <key>`, `<query> key <key>`, `<query> key: <key>` | "kesariya key of D" | |

- `<key>` = letter A-G, optional accidental (`#`, `♯`, `b`, `♭`), optional mode (`m`, `M`, `min`, `minor`, `maj`, `major`, with or without a space before the word form), nothing after it except whitespace.
- A token that does not parse leaves the whole line as the query ("tum hi ho in H" is a query).
- The query part must be non-empty ("in A" alone is a query "in A").
- Whether the token is really a key or part of a title ("Stuck in a", "Lost in A Dream") is decided by the matcher, section 6.6, not by the parser.

## 6. Matcher design (pure, SegueCore `Library/SongMatcher.swift`)

A whole-line scorer that answers "which song does this line name", scoring **titles** (with the file-name fallback) and **first lines** as a weaker signal, **never lyrics bodies, artists or tags**. It reuses `RomanNormalizer.words` / `normalizeWord` / `looseWord` / `editDistance`, so the composer and the library search agree on spelling variants.

### 6.1 Types

```swift
public struct SongMatcher: Sendable {
    /// Built once per composer session (section 6.7): every title and first line is
    /// tokenized and normalized here, never per keystroke.
    public init(candidates: [MatchCandidate])
    /// Ranked best first; at most `limit`; empty when nothing reaches the floor.
    public func bestMatches(for query: String, limit: Int = 5) -> [SongMatch]
}

public struct MatchCandidate: Sendable, Equatable {
    public var id: SongID
    /// `{title}`, else the file name without extension (the rule `SongSummary.title` uses).
    public var title: String
    /// First non-blank line of `plainLyrics` (the index's `first_line` rule); "" when none.
    public var firstLine: String
    public init(id: SongID, title: String, firstLine: String)
    /// From a loaded record, using the shared helpers below.
    public init(record: SongRecord)
}

public struct SongMatch: Sendable, Equatable {
    public var id: SongID
    public var score: Int
    public var tier: MatchTier
    public var form: MatchForm
    public var band: MatchBand
}

public enum MatchTier: String, Sendable, CaseIterable { // best first
    case exactTitle, titlePrefix, titleWords, fuzzyTitle, firstLine
}
public enum MatchForm: String, Sendable, CaseIterable { case original, normalized, loose }
public enum MatchBand: String, Sendable, CaseIterable { case strong, likely, weak }
```

- Precomputed per candidate: title words in the three forms (`O` = `RomanNormalizer.words`, `N` = `normalizeWord` of each, `L` = `looseWord` of each `N`), first-line words in `N` and `L`.
- Extract two small shared helpers so the rules cannot drift: `SongRecord.displayTitle` (title or file name) in SegueCore, used by `MatchCandidate` (and optionally by `SongSummary.title`, not required), and `SongDocument.firstLyricLine` used by `SongFiles.indexed` and `MatchCandidate`.

### 6.2 Query forms

`qO = RomanNormalizer.words(query)`, `qN = qO.map(normalizeWord)`, `qL = qN.map(looseWord)`. An empty `qO` returns no matches.

### 6.3 Tiers and scores

A word **matches** a candidate word in a form when they are equal, or, for the **last** query word only, when it is a prefix of the candidate word (in form `O` any length; in forms `N` and `L` only when the query word is at least `SongIndex.minimumPrefixLength` (4) long, the search's own rule against loose short prefixes). Each query word must match a **distinct** candidate word.

| Tier | Rule (tried in forms O, then N, then L; the best scoring form wins) | Base |
| --- | --- | --- |
| `exactTitle` | the title words equal the query words, same count, in order | 100 |
| `titlePrefix` | the query words are the leading title words in order (last one may be a prefix) | 90 |
| `titleWords` | every query word matches some title word, any order | 75 |
| `fuzzyTitle` | form N only: every query word matches as in `titleWords`, or (4+ letters) is within `editDistance(..., limit: 1)` of a distinct title word; at least one word needed the edit distance | 60 |
| `firstLine` | forms N and L, the `titlePrefix` rule (base 50) or the `titleWords` rule (base 45) against the first-line words; only when the query has 2+ words or 5+ letters (R158 Q10) | 50 / 45 |

`score = base - formPenalty - min(extraWords, 5)`, where `formPenalty` is 0 (O), 3 (N), 6 (L) and `extraWords` is the number of title words (first-line tiers: first-line words) the query did not cover.

**Ordering (pin it with tests, not arithmetic):** sort by tier first, then score, then shorter title, then `localizedStandardCompare` of the title, then ID. Tier always dominates, so penalty sizes never let a lower tier overtake a higher one; the score orders candidates within a tier and feeds the full-line rule in 6.6.

Floor: a candidate with no tier is not returned.

### 6.4 Bands

- `strong`: `exactTitle` or `titlePrefix` in any form.
- `likely`: `titleWords`.
- `weak`: `fuzzyTitle` or `firstLine` (the row shows "Close spelling" / "From the first line: ..." so the user sees why).

All bands are appendable with Return; the band drives the status line, the full-line rule (6.6) and analytics.

### 6.5 Alternatives

`bestMatches(limit: 5)`: the composer shows the first as the ghost and cycles through the rest. Songs already in the set are **not** filtered or demoted (the flag is the point, section 4.2); the matcher knows nothing about setlists.

### 6.6 Key token vs title (in `SetComposer.resolve`, pure)

`SetComposer.resolve(_ line: SetComposerLine, rawText: String, matcher: SongMatcher) -> SetComposerResolution` decides:

1. `.song(query, key: k, keyToken: t)` with `k != nil`: score both the full raw line and the stripped query.
2. If the full line's best match is `strong` and its score >= the stripped query's best score, the token is part of the title: use the full-line matches, no key. ("stuck in a" -> "Stuck in a Moment", no key.)
3. Otherwise use the stripped query's matches with key `k`. ("kesariya in a" -> Kesariya, key A.)
4. No key token: the query's matches.

`SetComposerResolution` carries the ranked matches, the key (if applied) and whether the line is a break, so the view only renders.

### 6.7 Candidate loading and speed

- The composer model builds `SongMatcher(candidates: library.catalog.map(MatchCandidate.init(record:)))` when the composer first gains focus, and rebuilds it when `library.catalogRevision` changes. No SQLite per keystroke, no actor hop, no debounce: matching runs synchronously on each text change so the ghost never lags.
- Cost per keystroke is linear in songs with precomputed word arrays; edit distance only runs in the `fuzzyTitle` tier for words of 4+ letters with `limit: 1` (early exit). Record one measured number (2,000 generated songs, debug build) in the step 2 commit message; no timing assertion in any suite (timing asserts flake).
- This deliberately does not add `LibraryStore.matchLines` / `bestMatches(for:)`: every caller already has the loaded catalog, so a store method would be a second path to the same data (R158 Q7 confirmed).

### 6.8 Short-word spelling tolerance in `RomanNormalizer` (R157)

R157 widens the normalizer's variant rules for short romanized Hindi words, so "tuj mai rab" finds "Tujh Mein Rab" in the composer **and in library search**, accepting a one-time rebuild of every library search index.

- **Rule** (appended to `RomanNormalizer.rules`, `Library/RomanNormalizer.swift:49-71`, after `dropFinalN`, so it sees `mei` from `mein`): in a normalized word of **at most 4 letters**, fold the vowel pairs `ei` and `ae` to `ai`. New `Rule` case `.foldShortVowelPair(_ pairs: [String], to: String, maxLength: Int)`. Results: `mein` -> `mei` -> `mai`, `main` -> `mai`, `mai` stays; `ae` -> `ai`; `hae` / `hai` / `hain` -> `hai`; `nei` / `nai` -> `nai`. Longer words are untouched (`deewana`, `their`, `mehfil`).
- **Version:** `RomanNormalizer.version` 3 -> 4 (history line: "4 = short-word vowel pairs (R157)"). The index's stored version is `schemaVersion * 1000 + RomanNormalizer.version` (`SongIndex.swift:63`), so every library rebuilds its index once on next open; no other migration.
- **Guard rails** (`RomanizedHindiSearchTests`, extend, table-driven): the rows above; English short words stay apart where they did before (`pen` / `pin`, `ten` / `tin`, `aid` stays `aid`, `they` unchanged); the existing corpus of that suite stays green. If an English regression appears that the 4-letter limit does not prevent, stop and ask rather than widening further.
- Consumers pick it up with no code change: library search (tiers 2-4), this matcher (forms N and L), and P8-1's near-duplicate score, which calls the normalizer at run time.

## 7. Gig key (pure, SegueCore `Setlists/SetlistOverrides+GigKey.swift`)

```swift
public extension SetlistOverrides {
    /// The `transpose` that makes the slot's displayed key `target` (nil when the song has
    /// no key). `songTranspose` is the song's saved view transpose; `capoOffset` is
    /// `Capo.displayOffset(capo: songCapo, mode: options.capoMode)`.
    static func transpose(
        toShow target: SongKey,
        written: SongKey?,
        songTranspose: Int,
        capoOffset: Int,
    ) -> GigKeyResult
}
public enum GigKeyResult: Equatable { case noOverride, transpose(Int), songHasNoKey }
```

- **Meaning of "in A":** the key the slot's Key column (and the slot popover, and the stage header) will show, i.e. `DisplayTransform.displayKey`, not concert pitch for capo songs (R158 Q1).
- `delta = written.tonic.pitchClass + capoOffset -> target.tonic.pitchClass` in semitones, normalized to -5...+6 (the smallest move; +6 for a tritone).
- **Relative key means no change (R158 Q2).** Let `shown` = `written` transposed by `songTranspose + capoOffset` (the key the row shows with no override). When the typed key's mode differs from the song's and the typed key is `shown`'s relative (major <-> minor, three semitones apart: "in C" for a song showing Am, "in Em" for a song showing G), the result is `.noOverride`: the typed key names the same key signature the row already shows. New `SongKey.relative` (the relative major of a minor key and vice versa) in `MusicTheory/SongKey.swift`, an additive hunk.
- **Any other mode mismatch: tonic to tonic**, the song's mode kept ("in D" for an Am song shows "Dm").
- If `delta == songTranspose` the result is `.noOverride` (what an empty override already shows), else `.transpose(delta)`. The capo override is never touched.
- `written` comes from `KeyContext(document:)` (declared `{key}`, else detection); nil -> `.songHasNoKey` (row status in 4.2, appended without overrides).

## 8. Core, store and view model changes

### 8.1 Store: one write per Return

`SetlistStore.insertSong(_ songID: SongID, overrides: SetlistOverrides, into id: SetlistID, at offset: Int? = nil) throws -> Setlist` in `SetlistStore+Entries.swift`: like `insertSongs` for one song but the new entry carries `overrides`; a song already in the set is skipped and nothing is written (same rule as `insertSongs`). This keeps "add Kesariya in A" one write and one undo step.

### 8.2 View model

`SetlistsViewModel+Composer.swift`:

- `compose(_ resolution: SetComposerResolution, choice: Int, in id: SetlistID) async -> ComposeOutcome` with `ComposeOutcome` = `.added(SetlistItemID)`, `.breakAdded(SetlistItemID)`, `.alreadyInSet(SetlistItemID)`, `.noMatch`, `.ignored`.
- Song: guard not read-only; if the chosen song is in the set -> `.alreadyInSet(existing item)` (no write); else `mutate(undo: (id, "Add Song"))` calling `insertSong(_:overrides:into:at: nil)`.
- Break: `mutate(undo: (id, "Insert Break"))` calling `insertBreak(into: id, at: nil)` (always the end, never after the Arrange selection: the composer is the end of the set).
- Always appends at the end of the set (not Pick's `tickPosition` part rule; R158 Q6).
- Records analytics (section 10) and `featureUsed(.setlistEdit, .builder)` as `insert` does.

### 8.3 Composer UI state

`Setlists/SetComposerModel.swift` (`@MainActor @Observable`): the text, the current `SetComposerResolution`, the alternative index, the matcher and the catalog revision it was built at, a `focusRequest` counter that ⌘L bumps (the view observes it and sets its `@FocusState`). `Setlists/SetComposerRow.swift` (the row view) and `Setlists/ComposerTextField.swift` (the `NSTextField` wrapper, section 4.5; `doCommandBy` maps `insertNewline`, `insertTab`, `insertBacktab`, `moveUp`, `moveDown`, `cancelOperation`).

### 8.4 Undo

Each Return that adds is one builder undo step ("Add Song" / "Insert Break") through `mutate`, so Edit > Undo while the composer is focused removes the last added row (the field editor's `allowsUndo = false` keeps text undo out of the window's undo stack, which the builder shares). Typing and cycling are not undo steps.

## 9. Menu and shortcut

- `MenuShortcuts.addSongByName = MenuShortcut("Setlist", "Add Song by Name", "l")` (⌘L), added to `all` after `insertBreak`; the clash test must pass (⌘L is free today, section 2; check again at implementation time; R158 Q9 gives ⌘L to this workstream, so a sibling that wants it picks another chord).
- `SetlistCommands.buildingItems`: the item is enabled when `editableBuilder != nil`, in both modes, and bumps the shown builder's `composerFocusRequest`. The `?` overlay and Help > Keyboard Shortcuts list it automatically.
- Tooltip on the composer placeholder: "Type a song name and press Return (⌘L)".

## 10. Analytics (non-PII, WS3 pattern)

New file `SegueCore/Sources/Services/AnalyticsEvent+Composer.swift`, a new row in `docs/release/specs/WS3-services.md` (the next free row number at implementation time; 24 if no sibling has taken it):

| Signal | Params | When | Throttle | Question it answers |
| --- | --- | --- | --- | --- |
| `Segue.Setlist.composed` | `segue.action` (`song`, `break`, `alreadyInSet`, `noMatch`), `segue.tier` (`exactTitle`, `titlePrefix`, `titleWords`, `fuzzyTitle`, `firstLine`, `none`), `segue.form` (`original`, `normalized`, `loose`, `none`), `segue.alternative` (Bool: a non-first candidate was accepted), `segue.key` (Bool: a key token was applied), `segue.entry` (`shortcut`: focused by ⌘L; `click`) | a Return in the composer (one per outcome) | daily per (action, tier, alternative) | Is the composer used; how often romanized Hindi variants (`normalized` / `loose`) or fuzzy and first-line matches carry it; how often the first guess is wrong (alternatives); how often the duplicate block and no-match bite; is the key token used |

- Enums and booleans only: never the typed text, titles, keys or IDs. `case setlistComposed(ComposerSummary)` in `AnalyticsEvent`, `area` "Setlist", `eventName` "composed", params and throttle cases, and the name added to `ServicesVocabularyTests`.
- Second signal (R158 Q8): a once-per-composer-session `Segue.Setlist.composerSession` with `segue.songs` (SmallBucket of songs added while focused) and `segue.cycles` (SmallBucket of alternative presses), recorded when the composer loses focus after at least one Return, to see whole sets typed versus one-off adds. Same file, the same WS3 row (two signals), the vocabulary test.

## 11. Accessibility

- The field: label "Add a song by name", identifier `segue.setlist.composer`; the container keeps `segue.setlist.dropZone`. Ghost and cells: `segue.setlist.composer.{ghost,key,capo,length,status,counter}`. Add them to `AccessibilityID+Setlists.swift`.
- The accessibility value of the field reads the suggestion: "Suggestion: Kesariya, key A, 4:05. 1 of 3." The status line is part of the value ("Already in the set at number 4", "No song matches").
- After an add, post an announcement: "Added Kesariya, number 13" (or "Added break, Set 2"); for the duplicate block, "Kesariya is already number 4".
- Alternatives are reachable with the same keys under VoiceOver; the counter is text, never colour alone; muted ghost text meets AA against `ground` (check `muted` in both themes; if it fails, use `mutedStrong` or the token the brand uses for secondary text).
- New UI joins the R79 accessibility walk before any label is claimed.

## 12. Design directions (step 0, R39)

The three directions offered (renders in the session scratchpad `p8-5/`, light and dark, Pick and Arrange):

- **A - Ghost row** (not chosen): the composer looks exactly like a set row with muted values; alternatives cycle in place with the "2 of 5" counter; no list.
- **B - Ghost row + alternatives list** (chosen, R158 Q3): as A, plus a compact list (up to 5 rows: title, key, length, "In set" badge) that drops under the row from the first ↓ / Tab, Things-style.
- **C - Pill** (not chosen): a rounded input pill under the last row (Spotlight-like), with the ghost and the key/length chips inside the pill; less "row-like", more obviously an input.

**Direction B is chosen** (R158 Q3: the alternatives list is visible). Step 0 renders B only, light and dark, Pick and Arrange, with the four states of section 4.2 (match, close spelling, already in set, no match) and the open alternatives list, for Ryan to confirm before step 4.

## 13. Tests (R113 budget)

### 13.1 Matcher corpus (`SongMatcherTests`, new, Swift Testing, table-driven with `@Test(arguments:)`)

Library for the table (titles; first lines where they matter):

`Kesariya` (first line "Mujhko itna bataaye koi"), `Tum Hi Ho`, `Tum Hi Ho Bandhu`, `Channa Mereya`, `Pehla Nasha`, `Deewana Hai Dekho`, `Kabhi Kabhi Aditi`, `Phir Le Aya Dil`, `Tujh Mein Rab Dikhta Hai`, `Ae Dil Hai Mushkil`, `Kitaabon Wali Gali` (first line "Purani si gali mein kitaabon ki dukaan"), `Stuck in a Moment`, `Wonderwall`, `Hotel California`, `Soundcheck at Seven`, an untitled song file `naina.cho` (title from the file name).

| # | Typed | Expected first | Tier / form / band | Also asserted |
| --- | --- | --- | --- | --- |
| 1 | `Kesariya` | Kesariya | exactTitle / original / strong | |
| 2 | `Kesariyaa` | Kesariya | exactTitle / normalized / strong | `aa` -> `a` |
| 3 | `kesar` | Kesariya | titlePrefix / original / strong | ghost suffix "iya" |
| 4 | `kesriya` | Kesariya | fuzzyTitle / normalized / weak | status "Close spelling" |
| 5 | `Tum Hi Ho` | Tum Hi Ho | exactTitle / original | second: Tum Hi Ho Bandhu |
| 6 | `tum hi ho` | Tum Hi Ho | exactTitle / original | case folding |
| 7 | `tum hi` | Tum Hi Ho | titlePrefix | Tum Hi Ho before Tum Hi Ho Bandhu (fewer extra words) |
| 8 | `Tum Hi Ho Bandhu` | Tum Hi Ho Bandhu | exactTitle | Tum Hi Ho not returned first |
| 9 | `bandhu` | Tum Hi Ho Bandhu | titleWords / likely | |
| 10 | `Channa Mereya` | Channa Mereya | exactTitle / original | |
| 11 | `Chana Mereya` | Channa Mereya | exactTitle / normalized | doubled letters |
| 12 | `chana mereyaa` | Channa Mereya | exactTitle / normalized | |
| 13 | `pehla nasha` / `pehela nasha` | Pehla Nasha | exactTitle original / fuzzyTitle normalized | the second needs edit distance 1 |
| 14 | `diwana hai dekho` / `dewana` | Deewana Hai Dekho | exactTitle normalized / titlePrefix loose | `ee` -> `i`, `w` -> `v`; loose `e` -> `i` |
| 15 | `kabhie kabhi` | Kabhi Kabhi Aditi | titlePrefix / normalized | aspiration, `-ie` -> `-i` |
| 16 | `fir le aya dil` | Phir Le Aya Dil | exactTitle / normalized | `ph` -> `f` |
| 17 | `tuj mein rab` | Tujh Mein Rab Dikhta Hai | titlePrefix / normalized | aspiration `jh` -> `j`, final `n` |
| 18 | `ae dil hain mushkil` | Ae Dil Hai Mushkil | exactTitle / normalized | `hain` -> `hai` |
| 18b | `tuj mai rab` | Tujh Mein Rab Dikhta Hai | titlePrefix / normalized | R157 short-word rules (6.8): `mai` and `mein` both normalize to `mai` |
| 18c | `ai dil hai mushkil` | Ae Dil Hai Mushkil | exactTitle / normalized | R157: `ae` and `ai` both normalize to `ai` |
| 19 | `kitabon wali` | Kitaabon Wali Gali | titlePrefix / normalized | |
| 20 | `purani si gali` | Kitaabon Wali Gali | firstLine / weak | status "From the first line" |
| 21 | `mujhko itna` | Kesariya | firstLine / weak | never a lyrics-body match: a word only in a later lyric line finds nothing |
| 22 | `naina` | naina.cho | exactTitle | file-name fallback |
| 23 | `wonderwal` | Wonderwall | titlePrefix / original | |
| 24 | `xyzzy`, `zzz qqq` | none | | "No song matches" |
| 25 | `k` | Kesariya | titlePrefix / original | one letter still gives a ghost; Kesariya before Kabhi Kabhi Aditi and Kitaabon Wali Gali (fewer extra words) |
| 26 | `the` | none | | no title word starts with "the"; the first-line tier needs 2+ words or 5+ letters |
| 27 | `ho` | Hotel California, then Tum Hi Ho, Tum Hi Ho Bandhu | titlePrefix original, then titleWords | a leading-word prefix outranks a later whole word: tier dominates |
| 28 | `!!!`, `   ` | none | | empty query |

Ordering properties (separate tests): tier dominates score; ties break by shorter title, then title, then ID (stable across runs); `limit` respected; the matcher never reads lyrics beyond the first line (a candidate built with a long `plainLyrics` behaves identically to one built from its first line only).

### 13.2 Parser and resolver (`SetComposerLineTests`, `SetComposerResolveTests`, new, table-driven)

| Typed | Parsed | Resolved (with the corpus above) |
| --- | --- | --- |
| `kesariya in A` | query "kesariya", key A | Kesariya, key A |
| `kesariya in a` | key A (letter upper-cased) | Kesariya, key A |
| `Kesariyaa (Am)` | key Am | Kesariya, key Am |
| `tum hi ho key of D` / `key D` / `key: D` | key D | Tum Hi Ho, key D |
| `channa mereya in f#m` / `in Bb` / `in C minor` | F#m / Bb / Cm | Channa Mereya with that key |
| `stuck in a` | query "stuck", key A | full line wins: Stuck in a Moment, **no key** |
| `tum hi ho in H` | "H" is not a key: the whole line is the query, key nil | no match in this corpus ("in" and "h" are not title words) |
| `kesariya in A` with a corpus song titled `Kesariya in A` added | key A | full line wins (exactTitle, strong): that song, no key |
| `in A` | query "in A", no key | |
| `---`, `----`, en dash + hyphen, one em dash | break | break |
| `--`, `- -`, `--- x` | song query | |
| empty / spaces | empty | |

### 13.3 Gig key (`GigKeyTests`, new, table-driven)

G song, no capo, "in A" -> +2; "in G" -> no override; "in F#" -> -1; "in C#" -> +6 (tritone rule) and "in Db" -> +6; Am song "in Bm" -> +2, "in C" -> no override (relative major, R158 Q2), "in D" -> +5 (shows Dm: not the relative, tonic to tonic), "in Cm" -> +3; G song "in Em" -> no override (relative minor), "in Am" -> +2 (shows A); Am song with saved view transpose +2 (shows Bm): "in D" -> no override, "in C" -> +3 (shows Cm); G song with capo 2 in shapes mode (shows A): "in F#m" -> no override; a song with saved view transpose +2 and "in A" (G song) -> no override, "in G" -> transpose 0; G song with capo 2 in shapes mode "in A" -> +2 (Key column shows A, capo 2), in concert mode "in A" -> 0 -> no override; a song with no key and no detectable key -> `songHasNoKey`.

### 13.4 Store and view model

- `SetlistStoreTests` (extend): `insertSong(_:overrides:)` writes the overrides, reloads them, skips a song already present without writing.
- `SetComposerViewModelTests` (new, SegueUI in-process, temp library): Return on a match appends one entry and registers one undo step "Add Song" (undo removes it); with "in A" the entry carries the transpose and a single undo removes the entry with its key; "---" appends a break labelled by `breakLabel(at:)` with undo "Insert Break"; a song already in the set returns `.alreadyInSet` and writes nothing; no match writes nothing; a read-only setlist writes nothing; the matcher rebuilds when `catalogRevision` changes (a song added to the library after the composer opened is found); the analytics recorder receives `Segue.Setlist.composed` with the expected params and no free text (assert the param values are all in the closed vocabulary).
- `ComposerKeyTests` (new, SegueUI in-process): the `doCommandBy` mapping (Return, Tab, ⇧Tab, ↑, ↓, Escape twice) drives the model's alternative index and clear/resign behaviour; the field editor properties of section 4.5 are all off after `controlTextDidBeginEditing`.
- `MenuAndAboutTests` (existing): the clash test passes with ⌘L.
- `ServicesVocabularyTests` (extend): the new signal name.

### 13.5 E2E: `SegueSetComposerE2ETests` (new, one class, one test)

Why an XCUITest: focus, the field editor's key handling, ⌘L through the menu and the real set list scrolling cannot be proven in-process end to end.

- Fresh temp library seeded with `SetlistE2E.makeRoot()` / `song(_:)` (`UITests/SegueSetlistE2ESupport.swift`): the 16 corpus songs with keys and `{duration}` (Kesariya `{key: G}` `{duration: 4:28}`, Tum Hi Ho `{key: Bb}`, Channa Mereya `{key: Em}`, ...), launched with the existing `launch()` helper on a clean state.
- New setlist (⇧⌘N, name, Return), then ⌘L, then type, each followed by Return, through one counting helper:
  `kesariyaa in A`, `tum hi ho`, `chana mereya`, `kitabon wali`, `---`, `pehla nasha`, `fir le aya dil`, `diwana hai dekho`, `kabhie kabhi`, `ae dil hain mushkil`, `tujh mein rab`, `wonderwall`, `tum hi ho bandhu`.
  That is 12 songs + 1 break: assert the actions counter is 14 (⌘L + 13 Returns), i.e. section 3's ⌘L + 12 Returns for the songs plus one for the break, with no Tab or ↓ needed.
- Assert: 13 entries in order with the right titles (`entryTitle`); row 1's Key cell reads "A" (Kesariya is G, no capo: +2); the break row is the 5th entry and labelled "Set 2"; the composer still has keyboard focus and is empty.
- Duplicate: type `kesariya`, Return: the status reads "Already in the set at #1", the entry count is unchanged, the first row is selected.
- No match: type `qqqq`: the status reads "No song matches"; Return changes nothing.
- ⌘Z once: the last song (Tum Hi Ho Bandhu) is gone; the composer keeps focus.
- ⌘1 (Pick): the composer row is still the last row and ⌘L focuses it.
- Add the class to `UITests/e2e-map.tsv` for `Packages/SegueUI/Sources/SegueUI/Setlists/*`, `Packages/SegueCore/Sources/Setlists/*` and `Packages/SegueCore/Sources/Library/SongMatcher.swift` (or `Library/*` if that line exists).

## 14. Steps

0. Direction B renders (section 12) and the "before" count (section 3); Ryan confirms the renders. The open questions are already closed (section 17).
1. Core: `SetComposerLine` parser, `SetlistOverrides` gig key (with `SongKey.relative`), `SetlistStore.insertSong(_:overrides:)`, the two shared helpers (`displayTitle`, `firstLyricLine`). Suites: `SetComposerLineTests`, `GigKeyTests`, `SetlistStoreTests`.
2. Matcher: the R157 `RomanNormalizer` rules and version bump first (section 6.8; suite `RomanizedHindiSearchTests`), then `SongMatcher`, `MatchCandidate`, `SetComposer.resolve`. Suites: `SongMatcherTests`, `SetComposerResolveTests`; record the 2,000-song timing in the commit message.
3. Analytics: `AnalyticsEvent+Composer.swift` (both signals), the WS3 row, the vocabulary test. Suite: `ServicesVocabularyTests`.
4. UI in the picked direction: `ComposerTextField`, `SetComposerModel`, `SetComposerRow`, `SetlistsViewModel+Composer`, drop zone takeover, ↓ from the last row, ⌘L menu item, accessibility ids. Suites: `SetComposerViewModelTests`, `ComposerKeyTests`, `MenuAndAboutTests`.
5. E2E `SegueSetComposerE2ETests`, `e2e-map.tsv`, the guide (`guide/src/content/docs/build-a-set.mdx`: a "Type a set" section with a real screenshot, the line grammar and the duplicate rule; `keyboard.mdx`: ⌘L and the composer keys), then ONE `make quick` and ONE `make e2e-one SegueSetComposerE2ETests` (plus `SegueSetlistBuilderE2ETests` if the drop zone change touched it). Launch the app at the end so Ryan can try it hands-on.

## 15. Files owned

- New (SegueCore): `Library/SongMatcher.swift`, `Setlists/SetComposerLine.swift`, `Setlists/SetComposer.swift` (resolve), `Setlists/SetlistOverrides+GigKey.swift`, `Services/AnalyticsEvent+Composer.swift`; tests `SongMatcherTests`, `SetComposerLineTests`, `SetComposerResolveTests`, `GigKeyTests`.
- New (SegueUI): `Setlists/ComposerTextField.swift`, `Setlists/SetComposerModel.swift`, `Setlists/SetComposerRow.swift`, `Setlists/SetlistsViewModel+Composer.swift`; tests `SetComposerViewModelTests`, `ComposerKeyTests`; `UITests/SegueSetComposerE2ETests.swift`.
- Additive hunks: `SetlistStore+Entries.swift` (`insertSong`), `Library/SongFiles.swift` (use `firstLyricLine`), `Library/SongRecord.swift` (`displayTitle`), `Services/AnalyticsEvent.swift` and `+Throttle.swift` (the new case), `SetEntriesList.swift` (composer row in place of `dropZone`, ↓ from the last row), `SetlistBuilderView.swift` (composer model wiring), `AccessibilityID+Setlists.swift`, `App/MenuShortcuts.swift`, `App/Commands/SetlistCommands.swift`, `docs/release/specs/WS3-services.md` (the row), `UITests/e2e-map.tsv`, `UITests/SegueSetlistE2ESupport.swift` (composer ids, if needed), `guide/src/content/docs/build-a-set.mdx`, `guide/src/content/docs/keyboard.mdx`, existing tests named in 13.4.
- Owned for R157 only: `Library/RomanNormalizer.swift` (the short-word rules and the version bump, section 6.8) and `Tests/SegueCoreTests/RomanizedHindiSearchTests.swift` (its cases). Any further rule change beyond 6.8: stop and ask.
- Not owned: `LibraryStore.search*` and `SongIndex` (unchanged; the index rebuild follows from the version bump through `SongIndex.swift:63`).

## 16. Done criteria

- The composer row is the last row of the set list in Pick and Arrange; ⌘L focuses it from anywhere in the builder; read-only setlists show no field.
- Typing shows the best match as a ghost with key and length; Return appends it as one undo step, clears the row and keeps focus; ↑/↓ and Tab / ⇧Tab cycle up to 5 alternatives.
- "in A", "(Am)" and "key of D" set the slot's displayed key through `overrides.transpose` in the same undo step; a song without a key says so and is added plain.
- "---" appends a break; a song already in the set is flagged and never added; "No song matches" offers nothing else.
- Every corpus row of 13.1-13.3 passes, including all romanized Hindi variants and the R157 short-word rows (18b, 18c); library search finds "tuj mai rab" too, after the one-time index rebuild; the matcher never reads lyrics beyond the first line; nothing the user typed is rewritten.
- "in C" for an Am song (any relative key) leaves the slot's key unchanged; other mode mismatches go tonic to tonic.
- `Segue.Setlist.composed` and `Segue.Setlist.composerSession` are recorded with closed-vocabulary params only and documented in WS3.
- The E2E proves 12 songs + 1 break in ⌘L + 13 Returns; section 3's table carries the measured before and after numbers.
- Guide pages updated; `make quick` green; `make e2e-one SegueSetComposerE2ETests` green; the app launched for Ryan's walkthrough.

## 17. Closed questions

Closed by Ryan on 2026-10-30 (**R158**; "a" = the recommendation as it was written). The body above already reflects each answer.

1. **What "in A" means for a capo song.** (a) The key the row shows (`displayKey`: shapes when the song's capo mode is shapes), so the typed key always reads back in the Key column (R158 Q1; section 7).
2. **Mode mismatch** ("in C" for an Am song). **Relative:** a key typed in the relative major or minor of the key the song shows means no change; any other mode mismatch goes tonic to tonic, keeping the song's mode (R158 Q2; section 7, tests 13.3). This differs from the recommendation (tonic to tonic for all).
3. **Alternatives list visible or not.** (a) Direction B: a compact list under the row from the first ↓ / Tab (R158 Q3; sections 4.3, 12).
4. **Duplicate Return behaviour.** Keep the text: no add, select and highlight the existing row, keep the typed text selected (R158 Q4; section 4.2).
5. **Break with a label.** (a) No: "--- Encore" is a song query; the label stays editable on the break row (R158 Q5; section 5.1).
6. **Where the composer appends when a break row is selected in Arrange.** (a) Always the end of the set (R158 Q6; section 8.2).
7. **No `LibraryStore` API.** (a) Confirmed: the matcher works on the in-memory catalog (R158 Q7; section 6.7).
8. **Second analytics signal.** (a) Yes, `Segue.Setlist.composerSession` (R158 Q8; section 10).
9. **⌘L ownership.** (a) This workstream keeps ⌘L (R158 Q9; section 9).
10. **First-line matching threshold.** (a) 2+ words or 5+ letters, as specced (R158 Q10; section 6.3).

Related ruling since: **R157** (short-word spelling tolerance) is built here, section 6.8; it replaces the old corpus row 18b that documented the limit.
