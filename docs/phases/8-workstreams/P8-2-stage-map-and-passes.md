# P8-2 - Stage map, passes and show modes, section jump and loop, single-song sessions

Phase 8 workstream (new, 2026-10-30). Rulings: `docs/release/decisions.md` **R147** (every section expanded, section map, collapse toggle removed), **R148** (section jump, rehearsal loop with a count-in), **R149** (per-pass show modes; the editor is P8-3's), **R150** (Rehearse or Live a single song from the library, not logged), **R151** (bigger metronome pips, an exception to `docs/brand.md` section 8; its placement amended by R158 Q1), **R155** (build order), **R156** (P8-3's "Rehearse this" plays the slot's arrangement through this spec's entry point), **R158** (this spec's open questions closed, section 20). Earlier rulings this builds on or supersedes: R122 and R123 (per-slot arrangements, P3-16; R147 supersedes R123's "an extra play follows the collapse-repeats setting", R148 supersedes R122's "no stage-time section jumping"), R45 (page turners), R90/R108/R118 (metronome, P3-14), R113 (test budget), R146 (fingerprints), R154 (pedal safety, sibling P8-1). Approved design: the owner-picked mockup "Stage map strip and arrangement editor - design directions, 30 Oct 2026", section **A1 (top strip) for both Live and Rehearsal** (A2's left rail was not chosen) and the **"Beat pips"** metronome variant (edge bar and downbeat frame declined). The mockup file does not survive the session; every size, colour and state used here is transcribed in sections 7, 8 and 12.

**Build order (R155):** all of Phase 8 ships before the v0.5 submission. P8-1 is built first; **then this spec (P8-2)**; then P8-3, which consumes this spec's pass model; P8-4a and P8-5 run in parallel with them; P8-4b is blocked on research (R160). Index: `README.md` in this folder.

Sibling specs in this folder: **P8-3** (`P8-3-arrangement-sequence-strip.md`) builds the Arrange Sections editor on the model defined here (section 5 is its contract); **P8-1** (`P8-1-fix-round.md`, landed before this spec) adds `LiveCommand.repeatsWhenHeld`, the in-flight page-turn guard and "page-forward at the bottom of the last song stays put"; P8-5 does not touch the stage; P8-4a adds a bass-note toggle, a scale line in the header and a mini neck at the left end of the status band (P8-4 section 7.3), so the right end stays this spec's metronome.

## Session rules

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read/Grep/Glob tools. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks. Keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`). The LiveLayout engine is pure, so stage behaviour is proven with fast layout tests, not E2E. One new XCUITest class for the core stage flow (section 16.4) plus updating the existing ones this change breaks. At the end: ONE `make quick`, ONE `make e2e-one` per UI test class added or changed. No `make gate`, no `make check`, no E2E retry loops, no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency. The open questions were closed by R158 (section 20); the body reflects the answers.

## 1. Goal

On stage the song reads top to bottom exactly as it will be played: every section and every repeat written out, a map strip across the top showing the whole roadmap with the current pass lit, one key or click to jump to any pass, and (in rehearsal) a loop of one section with a one-bar count-in. A slot arrangement can now say, per pass, "chords only", "first line only" or "skip". A song can be rehearsed or played live straight from the library, without a setlist and without touching the gig log.

**In scope:** the pass model, setlist schema 6 and show record 4 with their migrations, the resolver and pass naming (the API P8-3 builds on), removal of repeat collapsing from the stage, rendering of the four show modes, the section map strip, gutter pass badges and mode tags, current-pass tracking, jump (click and 1-9), rehearsal loop with count-in, the bigger metronome in the band above the footer (bottom right, R158 Q1), single-song Rehearse/Live sessions, key bindings and help, guide pages.

**Not in scope:** the Arrange Sections editor (P8-3), named or song-level arrangements (R122, R149 declined), a count-in before auto-scroll starts (R154 declined; the loop count-in is R148's and separate), pedal safety and the last-song page-forward rule (P8-1), the PDF export (phase 4 gets its own repeats option, default written out in full, R158 Q9; noted in `docs/phases/4-export.md` rule 6), any change to `.cho` files.

## 2. Terms

- **Part**: one `RenderSection` of the song rendered with default options, as today (`SongSectionUnit`, `SlotArrangement.swift:192-216`): a labelled section, a `{chorus}` repeat, or a run of loose lines.
- **Pass**: one time a part is shown on stage, with a **show mode**. A slot arrangement is an ordered list of passes. A song with no arrangement plays every part once, in song order, all Full.
- **Show mode** (R149): `full` (default), `chordsOnly` (the chord row of each lyric line, no lyrics), `firstLine` (the first lyric line, then "+ N more lines"), `skip` (kept in the arrangement for the editor, never on stage or in the map).
- **Shown pass**: a pass whose mode is not `skip`. Only shown passes are numbered for keys 1-9, appear in the map and get gutter badges.
- **Pass label**: the part's display label (`SectionNotes.label(of:)`, else "Lead-in" / "After Verse 2" for loose lines, `SongSectionUnit.title`). **Pass number**: among shown passes with the same label key (`SectionNotes.key`), "2 of 3"; a label shown once has no number.
- **Reading line**: the y position in the song that counts as "where the performer is" (section 9).

## 3. Current behaviour (what changes)

Model and storage:

- `ArrangementStep { anchor, fingerprint, plays }` with `plays` 0 = skipped, 1-9 = played that many times in a row, codec with keys `section/occurrence/loose/after/afterOccurrence/fp/plays`: `Packages/SegueCore/Sources/Library/SlotArrangement.swift:55-122`. `SlotArrangement { steps, length }`, `maxPlays = 9`, `fullSong(_:)`, `playedSteps`, `playedSummary` (the gig log line, "Chorus 3rd x2"): `:126-186`.
- `ArrangementResolver.resolve(_:units:)` returns `.applied(order: [PlayedSection{index, plays}], newSections:)` or `.outOfDate(missing:)`; `unit(for:in:)` matches anchor and fingerprint (legacy fingerprint accepted): `Library/ArrangementResolver.swift:38-82`. `ArrangedSections.build` expands plays and writes a `{chorus}` repeat out with its target's items: `:98-127`.
- Setlist file schema 5 ("5 = per-slot arrangements (R122)"), `Setlist.currentSchemaVersion = 5`: `Setlists/Setlist.swift:282-286`; entry field `arrangement`: `:170`, codec `:225-269`; JSON migrator: `:463`.
- `ShowItem.arrangement` and `arrangementState`, copied at show start: `Shows/ShowRecord.swift:100-117`, `ShowController.swift:96-105`. `ShowRecord.currentSchemaVersion = 3` (`ShowRecord.swift:300`); migrator steps `[1, 2]` identity: `Shows/ShowStore.swift:58-63`.

Stage pipeline:

- `LiveSession.relayout()` resolves the slot arrangement and builds the `LayoutRequest` with `collapseRepeats: prefs.collapseRepeats` and `arrangement: [PlayedSection]?`: `Packages/SegueUI/Sources/SegueUI/Live/LiveSession+Viewport.swift:34-109`. The up-next model is arranged with `ArrangedSections` (`:54-62`). Auto-scroll duration uses the slot length when applied (`:161-181`).
- `SongPreparation.measure()` pins cues on the song's own sections, applies the arrangement, then runs `RepeatCollapser.collapse(sections, enabled: request.collapseRepeats)` and builds `MeasuredSection` bodies `.full` or `.collapsed(line: "Repeat chorus", differing:)` with an "x2" gutter detail: `Packages/SegueCore/Sources/LiveLayout/SongPreparation.swift:13-147`.
- `RepeatCollapser` (collapse, `repeatTarget`, `displayLabel`, private `normalize`): `LiveLayout/RepeatCollapser.swift:15-136`. `CollapsedSection`: `LiveLayout/LayoutEngine.swift:26-44`. `LayoutBlock.Content.collapsed`, `collapsedBaseline`, `LayoutBlock.id` "index into RenderModel.sections": `LiveLayout/LayoutPlan.swift:176-237`. `TextRole.collapsedRepeat`: `LayoutRequest.swift:31`. `LayoutRequest.collapseRepeats`: `:297-328`.
- Other `RepeatCollapser` consumers: `WelcomeLibraryTests.swift:88` (`displayLabel`), `LiveLayoutCollapseTests`, `SectionNoteIdentityTests.swift:191`, `LiveLayoutCorpusTests.swift:21`, `StageLayoutRenderTests.swift:266`, `SlotArrangementTests.swift:186`. The arrangement fingerprint does **not** use `RepeatCollapser.normalize` any more: `SongSections` has its own `normalize` and `repeatTarget` (`SlotArrangement.swift:361-390`), so nothing outside the stage needs `RepeatCollapser`. The PDF export spec (`docs/phases/4-export.md` pagination rule 6) refers to "a collapsed chorus repeat ... when the live view collapses it"; the export is not built yet, and that rule now carries the R147 / R158 Q9 note (its own repeats option, default written out in full).
- Collapse toggle: `LiveCommand.toggleCollapseRepeats` (`Shows/LiveCommand.swift:38`, scope `:67`, title `:107`), default key `o` (`Shows/InputBindings.swift:257`), help group "View" (`Shows/KeyHelp.swift:28`), dispatch (`Live/LiveSession+Commands.swift:48,69`), `toggleCollapseRepeats()` (`LiveSession+Viewport.swift:332-337`), analytics `FeatureKey.collapseRepeats` (`Services/AnalyticsEvent.swift:224`), `LivePrefs.collapseRepeats` (`Library/Sidecar.swift:186-221`), the Arrange Sections preview (`Setlists/ArrangementEditorSheet.swift:492`). A current-version `bindings.json` naming `toggleCollapseRepeats` decodes strictly (`InputBindings.swift` `loadReporting`), so deleting the case would reject the whole file.

Stage chrome:

- `LiveView` stacks header (76), song area (body top padding 20), status band (30 + 2 x 8), footer (64); `viewport(for:topInset:)`: `Live/LiveView.swift:20-41`. The metronome sits bottom right in the status band, hidden while the request panel shows: `:254-266`.
- `StageHeader`: cue dot, title, "G, capo 2, 96", "Arranged"/"Full song", spacer, "Rehearsal" chip, progress dots, elapsed: `Live/StageChrome.swift:9-61`. `StageFooter` up next / "End of set": `:146-254`. Status line hints from `KeyHelp.statusHints`: `:258-285`.
- `StagePlanView` is `Equatable` and draws the plan once; it is offset by the scroll inside a `TimelineView`: `Live/StageSongBody.swift:8-31`, `LiveView.swift:106-148`.
- Metronome: `StageMetronomeView` draws the BPM (13 pt semibold muted) and one 18 pt dot that flashes (fade over the first 60% of a beat, beat 1 cue with a halo); Reduce Motion shows a 20 pt numeral: `Live/StageMetronomeView.swift:11-82`. Model `StageMetronome` (`follow`, `toggle`, `toggleClick`, private `restartGrid`): `Live/StageMetronome.swift:18-120`. Beat math `MetronomeTrack`, `MetronomeMeter.pulses`: `Packages/SegueCore/Sources/Shows/Metronome.swift:9-139`.
- Auto-scroll: `AutoScroller` (`offset(at:)`, `start`, `pause`, `seek(to:at:)`, lead-in): `LiveLayout/AutoScroll.swift:127-262`. Paging: `pageDown/pageUp/pageForward/pageBack`: `LiveSession+Viewport.swift:219-260`. `pageForward` pages, then at the bottom performs `.next`.
- Keys: `InputBindingTable.defaults` (`InputBindings.swift:236-271`): digits `1`-`9` and `l` are unbound; `o` is the collapse toggle; `0` is bound only with Command. `LiveKeyInput.handle` lets auto-repeat through only for `.viewport` commands (P8-1 replaces that with `repeatsWhenHeld`).

Runs:

- Rehearsal is a `ShowKind` over a whole setlist (`Shows/ShowRecord.swift:63-67`). `AppModel.startShow(_:kind:)` flushes the editor, shows the pre-show checklist, starts a `ShowController` that writes `shows/<ulid>.show.json` at once and claims it, presents the stage: `Packages/SegueUI/Sources/SegueUI/App/AppModel+Shows.swift:86-143`. `showEnvironment` adds a `RehearsalTimingStore` for rehearsals: `:307-329`. `finishRun` ends, records analytics, counts gigs for the review prompt, runs the end Shortcut, reloads reviews: `:380-405`. A gig record that is saved finished feeds the plays projection (`ShowStore.save`, `ShowStore.swift:114-127`) and the gig log (`GigLog.swift:66`). `ShowStore.claim` throws `notLoaded` without a root.
- Library: the song detail header has "…" (`SongActions`) and "Edit": `Library/SongDetailPane.swift:48-66, 205-222`; the list row context menu uses `SongActions`: `Library/LibraryViews.swift:110, 271-292`. Setlist > Start Show `⌘↩` and Rehearse `⌥⌘↩` act on the shown setlist only (`App/Commands/SetlistCommands.swift:19-24`); `MenuAndAboutTests` requires every declared chord to be unique (`MenuAndAboutTests.swift:11-13`).

## 4. Data model and schema

### 4.1 Decision: one entry per pass

The two options from the mockup's question 1:

- **(A) A mode array on the step**: `{anchor, fp, plays: 3, modes: [full, full, firstLine]}`. Keeps "x3" as a concept and small files, but has two spellings of the same thing (one step x2, or two consecutive steps x1), needs merge and split rules whenever a pass is dragged away from its siblings, and every consumer (map, badges, editor lane, summary) has to expand it anyway.
- **(B) One entry per pass** (recommended, and what P8-3 assumes): `ArrangementPass {anchor, fp, mode}`; "x2" is simply two consecutive passes.

**Choice: B.** It is canonical (one representation per arrangement), maps 1:1 to the editor's lane chips (R149, B1), to the stage's passes and to the map chips, and makes dragging, numbering and per-pass modes trivial. Files grow by one small object per repeat, which is negligible.

### 4.2 Types (SegueCore `Library/SlotArrangement.swift`)

```swift
/// How a pass is shown on stage (R149). Coded values are stable.
public enum PassMode: String, Sendable, Hashable, Codable, CaseIterable {
    case full = "full"
    case chordsOnly = "chords"
    case firstLine = "first"
    case skip = "skip"
}

/// One pass of a slot arrangement: a part of the song and how it is shown.
public struct ArrangementPass: Sendable, Hashable, Codable {
    public var anchor: SectionAnchor          // unchanged type (label + occurrence, or loose block)
    public var fingerprint: String?           // R123/R146 fingerprint when saved
    public var mode: PassMode                 // default .full
    public init(anchor: SectionAnchor, fingerprint: String? = nil, mode: PassMode = .full)
    public var isShown: Bool { mode != .skip }
}

/// A part the arrangement knew when it was saved (for "New in the song", R123).
public struct KnownPart: Sendable, Hashable, Codable {
    public var anchor: SectionAnchor
    public var fingerprint: String?
}

public struct SlotArrangement: Sendable, Hashable, Codable {
    public static let maxPasses = 48
    public var passes: [ArrangementPass]
    /// Every part of the song when the arrangement was last saved; parts of the current song
    /// not in this list (and not in `passes`) are "New in the song" (R123).
    public var knownParts: [KnownPart]
    public var length: TimeInterval?          // unchanged meaning (R122)
    public init(passes: [ArrangementPass], knownParts: [KnownPart] = [], length: TimeInterval? = nil)
    public static func fullSong(_ units: [SongSectionUnit]) -> Self   // every part once, Full, song order; knownParts = all units
    public var shownPasses: [ArrangementPass] { get }                // mode != .skip
    public var problems: [ArrangementProblem] { get }                // the validator (4.4)
    public var playedSummary: String { get }                         // gig log line (4.6)
}
```

`SectionRef`, `SectionAnchor`, `SongSectionUnit`, `SongSections` stay as they are. `ArrangementStep` and `maxPlays` are deleted (no alias kept; the only consumers are the files listed in section 18).

### 4.3 JSON (inside a setlist entry, absent when nil)

```json
"arrangement": {
  "passes": [
    {"section": "Intro", "occurrence": 1, "fp": "4f1a9c02", "mode": "chords"},
    {"section": "Verse", "occurrence": 1, "fp": "b7e0d3aa"},
    {"section": "Chorus", "occurrence": 1, "fp": "9d2be417"},
    {"section": "Bridge", "occurrence": 1, "fp": "0c55e9f1", "mode": "skip"},
    {"section": "Chorus", "occurrence": 3, "fp": "repeat"},
    {"section": "Chorus", "occurrence": 3, "fp": "repeat"},
    {"section": "Outro", "occurrence": 1, "fp": "11aa0c3e", "mode": "first"}
  ],
  "knownParts": [
    {"section": "Intro", "occurrence": 1, "fp": "4f1a9c02"},
    {"loose": 1, "fp": "77e1b0d2"}
  ],
  "length": 215
}
```

- Anchor keys are exactly today's (`section`/`occurrence`, or `loose`/`after`/`afterOccurrence`), shared by passes and known parts.
- `mode` is omitted for `full`; an unrecognised `mode` string decodes as `full` (lenient within schema 6). `plays` is never written and is ignored if present.
- `knownParts` is written on every save from the song's current units; absent or empty on read means "the parts named in `passes`" (so a hand-written or migrated file still works).
- `length` is omitted when nil or not positive (today's rule).

### 4.4 Invariants and the validator

`SlotArrangement.problems` returns zero or more of `.noShownPass` (every pass is Skip, or there are no passes), `.tooManyPasses` (more than `maxPasses`). The editor refuses edits that would create a problem (P8-3). On decode a file that breaks them still loads; the resolver treats it as out of date (the stage shows the full song, R122), never rejects the setlist.

### 4.5 Migrations

- **Setlist 5 -> 6.** `Setlist.currentSchemaVersion = 6`; history line: "6 = arrangement passes with show modes (R149)". Migrator step `5`: for each `entries[i].arrangement`, `SlotArrangement.migrateV5(_ json: inout [String: Any])` rewrites `steps` into `passes`: a step with `plays` 0 (or below) becomes one pass with `"mode": "skip"`; `plays` n >= 1 becomes `min(n, 9)` consecutive passes (no `mode` key, so Full) with the same anchor and `fp`; a step without `plays` is one Full pass. `knownParts` = the distinct anchors (with their `fp`) of the old steps, in order (v5 listed every part, R123). The `steps` key is removed. Old files read fine and are written at 6 on their next save (the existing rule). An older build opens a v6 file read-only (`VersionedJSON`).
- **Show record 3 -> 4.** `ShowRecord.currentSchemaVersion = 4`; `ShowStore.migrator` step `3` applies the same `SlotArrangement.migrateV5` to every `items[i].arrangement` and every `planned[i].arrangement`. `arrangementState` is unchanged. A running show from the previous build resumes with its arrangements expanded; finished gig log records keep their summaries. An older build opens a v4 show record read-only.
- `migrateV5` is one public static function in Library, used by both migrators, so the two cannot drift.

### 4.6 The gig log summary

`playedSummary` reads the saved passes (no song needed): shown passes in order, consecutive passes with the same anchor and mode merged into "x2", the mode named in brackets: "Intro (chords), Verse 1, Chorus, Chorus 3rd x2, Outro (first line)". Names follow today's rule (label, "Chorus 3rd" for occurrence > 1, "Lead-in", "After Verse 2"). Consumer: `GigLog/GigDetailView.swift:236` (unchanged call).

## 5. Interface for P8-3

P8-3 (section 4 of its spec) is written against these names; they are final here.

1. **Pass type and mode**: `PassMode` (`full`, `chordsOnly`, `firstLine`, `skip`; coded `full/chords/first/skip`), `ArrangementPass { anchor, fingerprint, mode }`, `SlotArrangement { passes, knownParts, length }` with the memberwise init and `fullSong(_:)` (section 4.2). P8-3's editor writes `knownParts = SongSections.units(of:)` mapped to `KnownPart` on every save (a helper `KnownPart.all(_ units:)` is provided).
2. **Limits and validator**: `SlotArrangement.maxPasses = 48`, `problems: [ArrangementProblem]` with `.noShownPass`, `.tooManyPasses`.
3. **New-section detection**: by `knownParts` (P8-3 question 3 answered: passes may be removed freely; a part never needs a Skip pass to stay "known"). `ArrangementResolution.applied(..., newSections:)` lists the song's units matching neither a pass nor a known part.
4. **Resolver**:
   ```swift
   public struct PlayedPass: Sendable, Hashable {
       public var index: Int        // part: index into RenderModel.sections
       public var mode: PassMode    // never .skip
       public var position: Int?    // index into arrangement.passes; nil for the full song
   }
   public enum ArrangementResolution { case applied(order: [PlayedPass], newSections: [SongSectionUnit]); case outOfDate(missing: [ArrangementPass]) }
   ArrangementResolver.resolve(_ arrangement: SlotArrangement, units: [SongSectionUnit]) -> ArrangementResolution
   ArrangementResolver.unit(for pass: ArrangementPass, in units: [SongSectionUnit]) -> SongSectionUnit?
   ArrangementResolver.fullSong(_ units: [SongSectionUnit]) -> [PlayedPass]   // every part once, Full
   ```
   Skip passes are resolved (an unresolvable Skip pass still makes the arrangement out of date, as a skipped row does today) but left out of `order`. `.outOfDate` also when `problems` is not empty.
5. **Pass numbering**: `PassNaming.names(_ passes: [ArrangementPass], units: [SongSectionUnit]) -> [PassName?]` (nil for a pass that does not resolve) and the stage-side `PassNaming.names(titles: [String], shown: [Bool]) -> [PassName]` it is built on. `PassName { title: String; short: String; number: Int?; total: Int }`: `number` is nil for a skipped pass and for a label shown once; grouping is by `SectionNotes.key(title)`. Display helpers: `chipText` ("Chorus 2/3" or "Chorus"), `badgeText` ("2 of 3" or nil). `PassNaming.short(_ title:)`: "Verse 2" -> "V2", "Chorus" -> "C", "Bridge" -> "B", "Intro" -> "I", "Outro" -> "O", "Pre Chorus" -> "PC", "Lead-in" -> "Lead", "After Verse 2" -> "+V2", others: the initials of each word plus a trailing number. The same function names the map, the gutter badges and P8-3's chips, so "2 of 3" means the same everywhere.
6. **Stage layout input**: `LayoutRequest.passes: [PlayedPass]?` (nil = the full song as written) replaces `arrangement`; `collapseRepeats` is gone. `LayoutPlan.passes: [PlanPass]` (section 6.5) exposes each shown pass's column, top, bottom and `position`, so the preview can scroll to a selected pass (`plan.passes.first { $0.position == selected }`).
7. **Map strip and badges for the preview**: `StageMapStrip(passes:current:progress:loop:style:onJump:)` with `StageMapStrip.Style.stage` and `.preview` (section 7.4); `.preview` is non-interactive (no hints, no jump, no progress bar). `StagePlanView` draws the gutter pass badges and mode tags itself, so the preview needs no drawing code.
8. **Migration**: `SlotArrangement.migrateV5` (section 4.5). The editor only ever sees passes.
9. **Summary**: `playedSummary` (section 4.6). Editor-side texts are P8-3's.
10. **Accessibility identifiers** (mirrored in the UITests target): `segue.live.map` (strip), `segue.live.map.chip.<n>` (n = 1-based shown-pass number), `segue.live.passBadge.<n>`, `segue.live.jumped` (the confirmation), `segue.live.loop` (header pill), `segue.library.song.rehearse`, `segue.library.song.live`.
11. **Shared stage request**: P8-2 provides it. `StageRequest.make(song: SongRecord, slot: StageSlot, prefs: LivePrefs, settings: LiveSettings, minLyricSize: Double, viewport: LayoutSize) -> (request: LayoutRequest, resolution: ArrangementResolution?)` in `SegueUI/Live/StageRequest.swift`, where `StageSlot { overrides: SetlistOverrides; note: String?; arrangement: SlotArrangement? }` (built from a `ShowItem` or a `SetlistEntry`). `LiveSession.relayout()` calls it; P8-3's preview calls it with its draft arrangement. The render model with overrides (`LiveSession.renderModel`) and the resolution move into it.
12. **Single-song entry point** (P8-3's "Rehearse this"): `AppModel.startSongSession(_ song: SongID, kind: ShowKind, slot: StageSlot? = nil, onEnd: (@MainActor () -> Void)? = nil) async -> Bool` (section 13). The library passes `slot: nil` (the full song as written, R150); P8-3 passes the slot's overrides and draft arrangement and reopens its sheet in `onEnd`.

**Interim editor adapter (this workstream):** until P8-3 replaces the sheet, `ArrangementDraft` keeps its row model (anchor + plays) and converts at the boundary: load collapses consecutive Full passes with the same anchor into one row with that play count and a Skip pass into a skipped row; save expands rows back into passes and writes `knownParts`. Any other mode is preserved by refusing to load it into the old editor (the sheet shows "This arrangement uses show modes; update Segue's editor" read-only). This keeps the tree compiling and the existing E2E meaningful; P8-3 deletes the adapter.

## 6. The expanded stage (R147)

### 6.1 Removals

- `RepeatCollapser.swift` is deleted, with `CollapsedSection` (`LayoutEngine.swift:26-44`), `MeasuredSection.Body.collapsed`, `LayoutBlock.Content.collapsed`, `LayoutBlock.collapsedBaseline`, `TextRole.collapsedRepeat` and their uses in `StageTypography.swift:27`, `StageSongBody.swift:100-107,171,186`, `PlanAssembly.swift:55-56,79`. `SongPreparation` uses `SongSections.repeatTarget` and `SectionNotes.label(of:)` instead (identical rules). `WelcomeLibraryTests.swift:88` switches to `SectionNotes.label`. `LiveLayoutCollapseTests` is replaced by `LiveLayoutPassTests` (section 16.2). The fingerprint is unaffected (it never used `RepeatCollapser`).
- `LayoutRequest.collapseRepeats` is removed; every call site drops the argument (stage, `ArrangementEditorSheet.swift:492` until P8-3 rewrites it, tests).
- `LiveCommand.toggleCollapseRepeats`, its `o` default, its "View" help row, `toggleCollapseRepeats()` and its dispatch, and `FeatureKey.collapseRepeats` are removed. `bindings.json`: `LiveCommand` gains `static let retired: Set<String> = ["toggleCollapseRepeats"]`; decoding a current-version file skips a binding whose command is retired (counted nowhere, no error), and still throws for any other unknown command.
- `LivePrefs.collapseRepeats` is removed: the lenient decoder ignores the key (no read), the encoder no longer writes it; no sidecar schema bump (an older build reading a sidecar without it defaults to collapsing, which is that build's own behaviour).
- `docs/phases/2-interfaces.md` (repeat collapsing, frozen interface) gets a dated "Superseded by R147" note pointing here; `docs/brand.md` section 8 gets the R151 exception line (section 12). These two doc edits are part of this change.

### 6.2 Passes in `SongPreparation`

`measure()` always works on a pass list: `request.passes ?? ArrangementResolver.fullSong(units)` (units from `request.model.sections`). It keeps today's order of operations: pin cues to the song's own sections first, then build the passes (`ArrangedSections.build(sections, order:)`, now taking `[PlayedPass]` and returning `ArrangedSection { section, source, mode, isFirstShown, position }`), then measure each pass. Consequences:

- Every `{chorus}` repeat is written out with its target's items (already true in `ArrangedSections.build`), in arranged and full-song plans alike. A `{chorus}` with no earlier chorus to write out renders one muted comment row "Repeat chorus" (a `.comment` item with the `{chorus}` line's own path), the only place that text survives.
- Every played repeat of a part is laid out in full: no collapsing, no "x2".
- Cues show on the part's first **shown** pass only (a cue on a part whose only passes are Skip is not played, and not "unmatched").
- `MeasuredSection.id` and `LayoutBlock.id` are the shown pass's index (0-based among shown passes; unique even when a part plays twice); `LayoutBlock` gains `source: Int` (index into `RenderModel.sections`) and `pass: Int?` (index into `plan.passes`; nil for the notes block). `LayoutAudit` and any test reading `block.id` as a section index switch to `source`.
- `lineCount` (the tempo scroll estimate) counts **performed** lines: a Full, Chords only or First line pass counts all the part's lyric lines; Skip counts none. (Known limitation: auto-scroll speed is uniform over the overflow, so a long First line pass scrolls past faster than it is played; not addressed here.)

### 6.3 Rendering the show modes

All three are pure transforms in LiveLayout, tested in-process (section 16.2). Sizes are relative to the plan's lyric size `ly`; colours are stage tokens.

- **Full**: as today.
- **Chords only** (R149: the chord row of each lyric line, no lyrics): each `.lyrics` item with at least one chord becomes one **chord row** (new `LayoutRow.Kind.chordRow`): the line's chords in order, each a `PlacedText` with role `.chord` (bold, `cueText`, 0.82 ly), separated and bracketed by `|` glyphs with new role `.chordSeparator` (regular weight, `indicatorOff` #66676E, 0.82 ly). Gap between runs 0.55 em of the chord size; each chord run is at least 1.6 em wide; row height 1.5 x 0.82 ly. Mockup rendering of "[C]Harbour lights, [G]call me back": `| C | G |`. A lyric line with no chords is dropped; `{comment}` lines, tab/grid (`verbatim`) lines and stanza breaks stay as in Full (consecutive breaks collapse to one). Chords respect transposition and capo as the plan already does.
- **First line only**: `{comment}` items before the first lyric line stay; then the first `.lyrics` item with non-empty lyrics (with its chords, as in Full; if the part has none, its first lyrics or verbatim item); then one **more line** row (new role `.moreLines`: medium, `muted`, 0.6 ly, 2 pt above): "+ 3 more lines (first line only)", singular "+ 1 more line (first line only)", omitted when nothing follows. Everything after the first line is dropped.
- **Skip**: not laid out, not in `plan.passes`, not in the map, not counted for keys 1-9 (decided by the approved mockup: "Skipped passes never appear on stage").

### 6.4 Gutter: label, pass badge, mode tag

`GutterLabels` builds up to three lines per block's first part (continuation parts keep "(cont.)" only):

1. The name, as today (`.sectionLabel`, bold 13, `muted`; chorus labels `ink`).
2. The **pass badge** when the label is shown more than once: "2 of 3", new role `.passBadge` (semibold 12, `ink`), 4 pt below the name; `StagePlanView` draws a box around it: 1 pt `controlBorder`, radius 5, padding 1 x 6. Replaces the "x2" detail.
3. The **mode tag** for Chords only / First line passes: "CHORDS" / "1ST LINE", new role `.modeTag` (bold 10.5, uppercase, tracking 0.06 em, `muted`), 4 pt below the badge or name.

The gutter widens up to `maxGutterWidth` only as today (the badge and tag are narrower than most names).

### 6.5 `LayoutPlan.passes`

```swift
public struct PlanPass: Sendable, Hashable {
    public var index: Int            // 0-based among shown passes; key = index + 1
    public var position: Int?        // index into SlotArrangement.passes; nil for the full song
    public var source: Int           // RenderModel.sections index
    public var name: PassName        // title, short, number, total
    public var mode: PassMode        // never .skip
    public var tint: SectionTint
    public var kind: SectionKind?    // for the map's kind stripe
    public var column: Int           // column of the pass's first block
    public var top: Double           // y of its first block in that column
    public var bottom: Double        // bottom of its last block (last part)
    public var weight: Double        // sum of its blocks' heights (map chip width)
}
```

`PlanAssembly` fills it from the placed blocks. With one column, `top`s are strictly increasing and each `bottom` equals the next pass's `top` minus the block gap.

## 7. The section map strip (R147, mockup A1)

### 7.1 Placement

A strip under the header in both Live and Rehearsal, the full stage width minus the 40 pt side padding. Height **58 pt**: chips 48 pt tall plus 10 pt below. `LiveView` gains `mapHeight = 58`; `viewport(for:topInset:)` subtracts it (the lyric area loses about one 28 pt line, as the mockup notes). The band is always reserved, so the viewport never changes between songs. It is empty during a break interstitial, at the end of the set, while a song is unavailable, and for a plan with fewer than two shown passes (R158 Q7: the band stays reserved and empty, no layout shift).

### 7.2 Chips (stage style)

One chip per shown pass, in played order, `HStack(spacing: 4)`:

- Width proportional to `PlanPass.weight` (flex-grow), minimum **52 pt**. When the chips cannot fit at their minimum (`count x 52 + (count - 1) x 4 > strip width`), the strip scrolls horizontally and keeps the current chip in view (no animation with Reduce Motion).
- Shape: radius 7, 1 pt border `line` (#222326), no fill; padding 6 top, 9 sides, 0 bottom; content stacked, 1 pt apart, left aligned, clipped.
- **Label line**: bold 15, `ink`, one line: the full title when it fits the chip, else `PassName.short`; when numbered, the "2/3" follows in semibold 12 `muted`, 3 pt to the right. Examples: "Chorus 2/3", "C 3/3", "Verse 1".
- **Mode line**: bold 10.5, uppercase, tracking 0.06 em, `muted`: "CHORDS", "1ST LINE"; for Full a non-breaking space (keeps the height).
- **Kind stripe**: 3 pt wide at the left edge, from 7 pt below the top to 9 pt above the bottom, radius 0/2/2/0 (right corners). Colour: the section band colour of the part's kind (`SectionBandStyle.dynamicColor(for:)`, P3-11), as P8-3 decided for its chips (R158 Q6: one meaning of colour across editor, band and stage). The mockup's monochrome stripes (verse #8E8E96, chorus #ECECEE, bridge #F2555A, other #55565C) were declined.
- **States**:
  - Upcoming: as above.
  - **Current**: fill `surfaceAlt` (#1A1B1E), border `controlBorder` (#8E8E96 at 40%); a **progress bar** along the bottom edge, 3 pt high, `cue` (#F2555A), width = progress through the pass (section 9), from the left.
  - **Played** (index < current): label `muted`, its "2/3" `indicatorOff` (#66676E); progress bar full width in `indicatorOff`.
  - **Hover**: border `controlBorder`; the number-key **hint** fades in (120 ms; none with Reduce Motion) at top right (6 pt from the right, 5 pt from the top): the key "1"-"9", semibold 11, `muted`, 1 pt `controlBorder` border, radius 4, padding 0 x 4. Passes after the ninth have no hint.
  - **Looping** (rehearsal): border cue at 70% (`rgba(242,85,90,.7)`).
- Click: jumps to that pass (section 10). The stage still needs no mouse.

### 7.3 Accessibility

The strip is one container, "Section map", identifier `segue.live.map`. Each chip is a button, identifier `segue.live.map.chip.<n>`, label "Chorus, 2 of 3, chords only" (mode and number only when present), value "current" / "played" / "upcoming" (plus ", looping"), hint "Jumps to this section", action = jump. The progress bar, stripe and hint are hidden from VoiceOver. All state is text, never colour alone.

### 7.4 Preview style (for P8-3)

`StageMapStrip.Style.preview`: height 40 (chips 32 + 8 below), side padding 16, gap 3, chip minimum 30, padding 4 top / 6 sides, label 11.5, number 10, no mode line hints, no hover hint, no progress bar, no click.

## 8. The song body: pass highlight and loop marks

Decorations that change with scroll are drawn in a separate overlay above `StagePlanView` (which stays `Equatable` and is not redrawn per frame), positioned from `plan.passes` and the gutter label lines:

- **Current pass**: a 7 pt `cue` dot before the gutter name, 6 pt gap, vertically centred on the name's x-height; the name drawn `ink` (it is `muted` otherwise for non-chorus labels). Exactly one pass is current.
- **Looping pass** (rehearsal): a dashed bracket in the gutter gap, centred in the clear strip between the gutter and the section tint (the tint starts 8 pt left of the lyrics, so in the 18 pt gutter gap the bracket's left edge is 3.5 pt right of the gutter, R163), 3 pt wide, radius 2, from the pass's top to 8 pt below its bottom, `cue` dashes 8 pt with 5 pt gaps; and under the gutter lines, 6 pt below, a "⟲ Loop" label, bold 12, `cueText`, 5 pt gap after the glyph.

## 9. Current pass and progress

Pure, in LiveLayout (`StagePasses`), so it is tested without a window:

- `readLine(offset:plan:) = offset + viewportHeight x (0.28 + 0.72 x f)`, where `f = offset / overflow` (0 when the plan does not scroll). At the top the reading line sits 28% down the viewport (mockup), and it slides to the bottom of the content as the scroll reaches the end, so the last passes become current even when they never reach 28%.
- `current(in:offset:pinned:)`: if `pinned` is set, it wins; else for a **one-column plan that scrolls**, the last shown pass whose `top <= readLine`; else (the song fits, or two or three columns) pass 0 (R158 Q2: nothing dims until a jump pins another pass).
- `pinned` is set by a jump and by a loop wrap, and cleared by the next manual scroll, page step, Home, auto-scroll start or song change. A jump to a pass near the bottom (where the seek clamps at the overflow) therefore still shows that pass as current.
- `progress(of:in:offset:) = clamp((readLine - top) / (bottom - top), 0, 1)` for the current pass (0 when pinned and the reading line is above it).
- Played = shown passes with index < current. Jumping back un-dims the passes after it.
- `LiveSession` exposes `currentPass(at now:)` and `passProgress(at now:)`; the strip and the overlay read them inside the existing `TimelineView` (no new timers).

## 10. Jump (R148)

- **Keys**: nine new commands `LiveCommand.jumpToPass1` ... `jumpToPass9` (scope `.viewport`; `repeatsWhenHeld` false, P8-1's property), defaults `1`-`9` with no modifiers (free today; `⌘0`-style menu chords are unaffected because the stage key monitor sees plain digits only). A digit beyond the number of shown passes does nothing and flashes "No section 7" in the mode indicator.
- **Click** a chip: the same jump.
- **Jump**: seek the scroller to `clamp(top - 14, 0, overflow)` (14 pt above the pass, mockup), keeping auto-scroll running if it was; set `pinned`; clear an active loop if the target is another pass (section 11). With columns or a fitting song nothing scrolls; only `pinned` changes.
- **Confirmation**: a toast centred at the top of the song area, 14 pt below the map: "Jumped to Bridge", or with a number "Jumped to Chorus · 2 of 3". Semibold 14 `ink` on `surfaceAlt` at 95%, 1 pt `controlBorder` border, radius 8, padding 6 x 12; fades in and out over 250 ms, visible 1.1 s; no fade with Reduce Motion; it takes no clicks. VoiceOver: posted as an announcement with the same text. Identifier `segue.live.jumped`.
- Works in Live and Rehearsal, in arranged and full-song plans.

## 11. Rehearsal loop (R148)

- **Command** `LiveCommand.toggleLoop`, default `L` (free), scope `.viewport`, `repeatsWhenHeld` false. In a gig it changes nothing and flashes "Loop works in rehearsals".
- **On**: loops the current pass (section 9). Marks: the chip border (7.2), the gutter bracket and "⟲ Loop" (section 8), and a **header pill** before the "Rehearsal" chip: "⟲ Looping Bridge" (with the number when there is one: "⟲ Looping Chorus 2/3") then "L stops" in medium `muted`; semibold 14 `ink`, padding 5 x 11, radius 6, 1 pt border cue at 55%, fill cue at 8%, 8 pt gaps. Identifier `segue.live.loop`.
- **Off**: `L` again, a jump to another pass, a song change, End.
- **Wrap point**: the loop ends when the reading line reaches the pass's `bottom`, or when the scroll reaches the overflow first. `AutoScroller` gains `instant(reaching offset: Double) -> Date?` (when a running scroll will reach `offset`; nil when not running, already past, or never); `LiveSession` schedules the wrap for that instant on the scroll clock and reschedules on every seek, nudge, pause or re-layout.
- **Wrap**: seek to the pass's `top - 14`, set `pinned`, then a **one-bar count-in**: `AutoScroller.seek(to:at:holding:)` (new) holds the scroll still for `MetronomeTrack.barDuration` (`pulses x 60 / bpm`, new property) and then resumes at the same speed; `StageMetronome.countIn(at:)` (new, replaces the private `restartGrid`) restarts the beat grid at the wrap instant so beat 1 of the count-in bar falls on the wrap, and the section starts on the next downbeat. During the count-in the metronome pips (above the footer, section 12) show even when the pulse is off (they hide again after the bar if it is off); the click sounds only when the rehearsal click (`K`) is on. A song without a usable tempo holds 2 s with no pips (R158 Q4).
- **Without auto-scroll**: a Page Down (pedal) that would move the reading line past the looped pass's bottom wraps instead, with the same count-in; in a song that fits on screen each Page Down wraps (R158 Q3). `→`/Space still go to the next song and end the loop. Without a loop, Page Down is unchanged (section 12).
- The loop is session state only (never saved, never in the show record).

## 12. Page Down, metronome and header

**Page Down / pedal**: unchanged (R147): `pageForward` turns one screenful (to the next `pageStops` entry), and at the bottom moves to the next song at its top; `pageBack` mirrors it; `↓`/`↑` page within the song only. The only addition is the loop wrap in section 11. P8-1's guards (in-flight song change, last song stays put) apply on top.

**Metronome (R151, "Beat pips")**, `StageMetronomeView` redrawn **in place: the right end of the status band above the footer, bottom right**, where the dot is today (`LiveView.swift:254-266`), per the approved mockup. R158 Q1 amends R151's "stage header". The 18 pt dot is removed; the band's line height (30 pt, `LiveView.statusLineHeight`) already fits the 30 pt pips, so the viewport does not change:

- Layout: `HStack(spacing: 12)`: the **BPM** "96" bold 22 `ink`, monospaced digits, followed 3 pt later by "BPM" semibold 12 `muted`; then the **pips**: one per pulse of the bar (`MetronomeMeter.pulses`: 4 in 4/4 and 12/8, 3 in 3/4, 2 in 6/8), `HStack(spacing: 7)`, each a 30 x 30 rounded rectangle, radius 8. Pip 1 fill `cue` (#F2555A), the others `ink`; resting opacity 0.14.
- Flash: with `f = max(0, 1 - phase / 0.45)` for the sounding beat: that pip's opacity `0.16 + 0.84 f`, scale `1 + 0.12 f`; beat 1 also gets a glow, shadow radius `18 f`, spread `6 f`, cue at `0.45 f` alpha. Other pips stay at 0.14. Driven per display frame from the monotonic stage clock (`TimelineView`), as today.
- More than 8 pulses (7/8 is 7, 9/4 is 9): the numeral form below instead of pips.
- **Reduce Motion**: no pips; a stepping numeral, extra bold 28, 30 pt wide, centred, `cueText` on beat 1 and `ink` otherwise, beside the BPM.
- Hidden when the pulse is off (except the count-in, section 11), without a tempo, in a break, past the end, and while the request panel covers the bottom-right corner, as today. Accessibility unchanged ("Metronome, 96 beats per minute", `segue.live.metronome`), never takes clicks or focus.
- `docs/brand.md` section 8 gains: "Exception (R151): the stage metronome's beat pips flash at the song's tempo when the metronome is on; Reduce Motion shows a stepping numeral instead."

**Header order** (left to right, 14 pt spacing, unchanged otherwise): cue dot, title, "G, capo 2, 96", "Arranged" / "Full song", spacer, loop pill (rehearsal, when looping), "Rehearsal" chip, progress dots, elapsed. The metronome is not in the header. The title keeps its layout priority and truncates first. Sibling P8-4a (R152) adds the scale line to the header: it goes after "Arranged", before the spacer. P8-4a's mini neck sits at the left end of the status band (P8-4 section 7.3); the status line, when it fades in, sits between the two.

## 13. Single-song Rehearse and Live from the library (R150)

### 13.1 Entry points

- **Song detail header** (`SongDetailPane.header`): "Rehearse" (with the `play.fill` symbol) and "Live" buttons, `.segueSecondary`, large, between "…" and "Edit"; help "Rehearse this song on stage, not logged (⌥⌘↩)" / "Play this song live on stage, not logged (⇧⌘↩)". Identifiers `segue.library.song.rehearse` / `.live`.
- **Selected song row**: the same two buttons, small (12 pt, padding 3 x 8, radius 6), trailing, on the selected row only.
- **Context menu and "…" menu** (`SongActions`): "Rehearse Song" and "Play Song Live" first, then a divider, then today's items.
- **Library menu**: "Rehearse Song" `⌥⌘↩` and "Play Song Live" `⇧⌘↩`, enabled when a single library song is focused (`focusedSongID`), no setlist is shown, nothing is performing, and no show is starting or pending resume. `⌥⌘↩` is also Setlist > Rehearse, which needs a shown setlist, so the two are never enabled together; `MenuAndAboutTests`' clash test gains this one documented, tested exception (R158 Q5). `⇧⌘↩` is new and free.
- Disabled for a read-only library state where starting a show is disabled today; a read-only song is fine (it is only read).

### 13.2 How a one-song session runs

- `AppModel.startSongSession(_:kind:slot:onEnd:)` (section 5, item 12): flushes the open editor and refreshes the library (as `startShow`), builds an in-memory one-entry `Setlist` (fresh `SetlistID` and `SetlistItemID`, name = the song's title, the entry's overrides and arrangement from `slot`, else none: the full song as written), and starts a `ShowController` with an **unsaved environment**: `ShowEnvironment.store` becomes optional and nil means an unsaved run: `start` skips the claim, `persist()` records the write as done without touching disk, `end()` returns `ShowEnding(record, diff: nil, gigLogEntry: nil)`, and `durations` is nil. Structurally nothing reaches `shows/`, the gig log, the plays projection, play stats, the resume prompt or the launch auto-close (R150).
- No pre-show checklist, no Gig Mode Shortcut and no rehearsal timing samples (mockup C: "the pre-show checklist is skipped"; R158 Q8); the metronome pulse follows the remembered setting; the rehearsal click starts off.
- `LiveSession` gains `scope: StageScope` (`.setlist`, `.song`). With `.song`: no progress dots; the footer's end state reads "End of song" with "Cmd-. ends the rehearsal" / "Cmd-. ends"; the End dialog says "End this song?" and "A single song is never added to the gig log."; the keep-awake reason is "Rehearsing <title>" / "Performing <title>". Everything else (keys, map, jump, loop in a rehearsal, search, requests) works as on any stage, and nothing is logged.
- `finishRun` for `.song`: ends the controller, closes the stage, records the analytics in 13.3, and skips `recordShowEnded`, `countCompletedShow`, the end Shortcut and the review reload. `onEnd` is called last.
- Page Down at the bottom of the only song: P8-1's "last song stays put" rule applies.

### 13.3 Analytics (non-PII, R74 closed vocabulary)

New `FeatureKey` cases recorded with `featureUsed`: `.sectionJump` (stage; once per session, first jump, key or click), `.sectionLoop` (stage; loop switched on), `.singleSongSession` (library; on start, with kind as the existing token pattern). `FeatureKey.collapseRepeats` is removed. Update `docs/release/specs/WS3-services.md` (the event catalogue) in the same change.

## 14. Keys and help

- `InputBindingTable.defaults`: remove `o`; add `1`-`9` -> `jumpToPass1...9`, `l` -> `toggleLoop`.
- `KeyHelp.layout`: remove `.toggleCollapseRepeats` from "View"; new group "Sections" after "Scrolling": the nine jump commands and `toggleLoop` ("Loop Section (Rehearsal)"). When the nine jump commands are bound to their default digits, help shows them as one row "Jump to Section" with keycap "1-9"; otherwise one row each. Every `LiveCommand` still appears exactly once in `layout`.
- `KeyHelp.statusHints` gains "1-9 sections" after "A scroll" when the digits are default, and (rehearsal only, new `kind` parameter) "L loop".
- Titles: `jumpToPassN` "Jump to Section N"; `toggleLoop` "Loop Section (Rehearsal)".
- `guide/src/data/keyboard.json` is generated: run `make guide-keys`, never hand-edit it.

## 15. User guide

Part of this change (guide pages under `guide/src/content/docs/`):

- `go-on-stage.mdx`: new "The section map" section (chips, current pass, played, mode tags, "2 of 3" badges), "Jump to a section" (click a chip or press 1-9, the "Jumped to" note), and a sentence in "Move through the set" that Page Down still turns one screenful then the next song.
- `rehearse.mdx`: "Loop a section" (L, the count-in, it wraps by itself with auto-scroll or on each Page Down, L stops), and "Rehearse one song" (from the library: Rehearse ⌥⌘↩ or Live ⇧⌘↩, not in the gig log, no checklist).
- `metronome.mdx`: the pulse is now four large beat pips with the tempo, bottom right above the footer (beat 1 in coral), Reduce Motion numeral, the loop count-in.
- `sections.mdx` "Repeats on stage": replace the O-key paragraph: the stage writes out every repeat in full; the map and the "2 of 3" badges show where you are.
- `keyboard.mdx` picks up `keyboard.json` (regenerated).
- Do not edit `arrange-sections.mdx` (P8-3 owns it); mention show modes there only if P8-3 asks.
- Screenshots: `stage` and `metronome` (and a new `stage-map` shot if the pages use one) regenerate with `make docs-shots ONLY=stage,metronome,stage-map`, which needs the screen: hand the command to Ryan if the session cannot run it.

## 16. Test plan (R113)

Fast in-process suites carry the behaviour; the layout engine is pure and takes `FixedAdvanceMetrics`.

### 16.1 Core model (`SlotArrangementTests`, extend; `ArrangementResolverTests`, extend; `PassNamingTests`, new)

- v6 codec round trip; `mode` omitted for Full; unknown mode decodes Full; `plays` ignored; `knownParts` absent = the passes' parts.
- Migration 5 -> 6 on a real v5 setlist file: plays 0 -> one Skip pass; plays 2 -> two Full passes; plays absent -> one; `knownParts` = old anchors; written back at 6; an older reader sees `newerSchema`.
- `ShowRecord` 3 -> 4: items and planned arrangements expanded; `arrangementState` kept.
- Validator: all Skip -> `.noShownPass`; 49 passes -> `.tooManyPasses`; the resolver reports such files out of date.
- Resolver: Skip excluded from `order` but resolved; `position` per pass; new section = not in passes and not in `knownParts`; a removed pass does not make a part new; fingerprint mismatch out of date (legacy fingerprint still accepted); `fullSong`.
- `playedSummary`: runs merged into "x2", modes in brackets.
- `PassNaming`: "Chorus 1/3 ... 3/3" across written choruses and `{chorus}` repeats; a label shown once unnumbered; skipped passes named but not numbered; short forms.

### 16.2 LiveLayout (`LiveLayoutPassTests`, new, replacing `LiveLayoutCollapseTests`; extend `LiveLayoutGutterTests`, `AutoScrollTests`, `MetronomeBeatTests`; `StagePassesTests`, new)

- Full song: every repeat written out; `{chorus}` takes its target's lines; `{chorus}` with no target -> one "Repeat chorus" comment row; no `collapsed` content anywhere.
- Arranged: played order, unique block ids, `source` per block, cues on the first shown pass only, skipped parts absent.
- Chords only: one chord row per chorded lyric line, separators, chordless lines dropped, comments and tab lines kept, widths from metrics. First line only: comments before, the first line, "+ 3 more lines (first line only)" and the singular form.
- `plan.passes`: index, position, name, mode, column, monotonic tops in one column, `weight` = block heights, continuation parts included in `bottom`.
- Gutter: badge "2 of 3" and mode tag lines and their roles; continuation shows "(cont.)" only.
- `lineCount` counts performed lines for Chords only and First line passes.
- `StagePasses`: reading line at 0, mid and overflow; current with and without `pinned`; two columns and fitting plans return pinned or 0; progress; jump offset clamped.
- `AutoScroller.instant(reaching:)` and `seek(to:at:holding:)` with scripted instants; `MetronomeTrack.barDuration` for 4/4, 3/4, 6/8.
- `LivePrefs` with `collapseRepeats` decodes and re-encodes without it; `bindings.json` (current version) naming `toggleCollapseRepeats` loads, the binding is skipped and the others apply; an unknown non-retired command still throws.
- `KeyHelpTests`: every command once, "Sections" group, the collapsed "1-9" row, status hints.

### 16.3 SegueUI in-process (`StageMapTests`, `StageLoopTests`, `SingleSongSessionTests`, new; extend `StageMetronomeTests`, `LiveModeTests`, `LiveStageZoomTests`, `MenuAndAboutTests`)

- The map lists the plan's shown passes with the right labels, mode lines and states; current and played follow scripted scroll offsets; the viewport is 58 pt shorter.
- Chip click and keys 1-9 jump (scroll offset, `pinned`, the toast text, the VoiceOver announcement); a digit past the last pass flashes and does not move.
- Loop: `L` in a gig flashes and does nothing; in a rehearsal it loops the current pass; with a scripted scroll clock the wrap seeks to the top and holds for one bar, the metronome grid restarts at the wrap, the click plays only when on; Page Down while looping wraps; Page Down without a loop is unchanged (the existing paging tests stay green); song change, jump elsewhere and `L` clear it.
- Metronome: pips count per meter, numeral beyond 8 and with Reduce Motion, placed at the right end of the status band (not in the header) and hidden while the request panel shows, count-in shows pips with the pulse off.
- Single song: starts with no checklist; no file appears in `shows/`; after End there is no gig log entry, no play in the projection, `countCompletedShow` is not reached, no durations are recorded; the `.song` chrome texts; `onEnd` is called; Library menu items (R158 Q5) enabled only with a focused song and no shown setlist, and never together with Setlist > Rehearse (the clash-test exception asserted by the enablement predicates).

### 16.4 XCUITest (one new class, plus updates)

- **New `SegueStageMapE2ETests.testRehearseOneSongJumpAndLoop`**: fresh library; seed one song with three choruses (two written, one `{chorus}`) and a tempo, as `SegueArrangementE2ETests` seeds its song; select it in the library -> Rehearse (`⌥⌘↩`) -> the stage opens with no checklist -> the map shows "Chorus 1/3" ... "Chorus 3/3" chips and "2 of 3" badges, no "Repeat chorus" text -> press `3` -> "Jumped to ..." appears and chip 3 reads current -> `L` -> the loop pill appears -> `⌘.` then Return -> back in the library; the `shows/` folder holds no new file and the Gig Log has no new entry. Screenshots for the review.
- **Update `SegueArrangementE2ETests`**: disk assertions read `passes` and modes instead of `plays` (until P8-3 rewrites the editor steps); the stage step expects the Chorus written out in full (no "Repeat chorus"), the map chips and badges instead of three "Repeat chorus" lines; schema 6.
- Check `SegueLiveE2ETests` and `SegueMetronomeE2ETests` still pass (the metronome identifier and its place, bottom right above the footer, are unchanged). Run `make e2e-one` once per class added or changed.

## 17. Steps

0. Read this spec, P8-3 section 4 and P8-1 section 3; the open questions are closed by R158 (section 20).
1. **Model**: `PassMode`, `ArrangementPass`, `KnownPart`, `SlotArrangement` v6, validator, `migrateV5`, setlist schema 6 and show record 4 migrations, resolver, `PassNaming`, `playedSummary`, the interim `ArrangementDraft` adapter, `ShowController` copy unchanged. Suites 16.1.
2. **Layout**: delete `RepeatCollapser` and the collapsed paths, passes in `SongPreparation`, modes, gutter badge and tag, `PlanPass`, `StagePasses`, `AutoScroller` additions, `barDuration`; drop `collapseRepeats` from `LayoutRequest` and its call sites; `StageRequest.make`. Suites 16.2.
3. **Commands**: remove the collapse toggle, prefs field and analytics key; retired-binding skip; jump and loop commands, defaults, help, status hints; new analytics keys. Suites: `KeyHelpTests`, the bindings and prefs tests, `LiveModeTests`.
4. **Stage UI**: map strip (both styles), viewport, pass overlay, jump toast, loop (wrap scheduling, count-in, Page Down wrap, marks, pill), metronome pips above the footer. Suites: `StageMapTests`, `StageLoopTests`, `StageMetronomeTests`, `LiveStageZoomTests`.
5. **Single-song sessions**: optional store, `startSongSession`, `StageScope`, entry points, Library menu items, `finishRun` path. Suites: `SingleSongSessionTests`, `MenuAndAboutTests`.
6. **Docs and E2E**: guide pages, `make guide-keys`, brand.md exception, 2-interfaces.md note, WS3 catalogue; new and updated E2E; one `make quick`; `make e2e-one` per changed class; the screenshot command for Ryan if needed.

## 18. Files

- **New**: `SegueCore/Sources/Library/PassNaming.swift`, `LiveLayout/StagePasses.swift`; `SegueUI/Sources/SegueUI/Live/StageMapStrip.swift`, `StagePassOverlay.swift`, `StageJumpToast.swift`, `LiveSession+Passes.swift` (current pass, jump, loop), `StageRequest.swift`, `App/AppModel+SongSession.swift`, `AccessibilityID+StageMap.swift`; tests in section 16; `UITests/SegueStageMapE2ETests.swift`.
- **Changed**: `Library/SlotArrangement.swift`, `Library/ArrangementResolver.swift`, `Library/Sidecar.swift` (LivePrefs), `Setlists/Setlist.swift` (version, migrator), `Shows/ShowRecord.swift` (version), `Shows/ShowStore.swift` (migrator step), `Shows/ShowTypes.swift` (optional store), `Shows/ShowController.swift` (unsaved run), `Shows/LiveCommand.swift` (coordinate the hunk with P8-1's `repeatsWhenHeld`), `Shows/InputBindings.swift`, `Shows/KeyHelp.swift`, `Shows/Metronome.swift` (`barDuration`), `Services/AnalyticsEvent.swift`; `LiveLayout/` (`SongPreparation`, `LayoutRequest`, `LayoutPlan`, `LayoutEngine`, `PlanAssembly`, `GutterLabels`, `SectionLayout`/`LineLayout` for the chord row, `AutoScroll`, `LayoutAudit`); deleted `LiveLayout/RepeatCollapser.swift`; `SegueUI/Live/` (`LiveView`, `StageChrome`, `StageSongBody`, `StageMetronomeView`, `StageMetronome`, `LiveSession`, `LiveSession+Viewport` (relayout via `StageRequest`; P8-1 edits `pageForward`/`pageBack` in the same file: coordinate by hunk), `LiveSession+Commands`, `LiveSession+Metronome`, `Layout/StageTypography`); `App/AppModel+Shows.swift` (`finishRun`, `showEnvironment`), `App/Commands/LibraryCommands.swift`, `App/MenuShortcuts.swift`, `Library/SongDetailPane.swift`, `Library/LibraryViews.swift`; `Setlists/ArrangementDraft.swift` and `ArrangementEditorSheet.swift` (interim adapter and the request call only; P8-3 owns their rewrite); `GigLog/GigDetailView.swift` only if the summary call changes; `docs/brand.md` (section 8 line), `docs/phases/2-interfaces.md` (superseded note), `docs/release/specs/WS3-services.md`; the guide pages in section 15.
- **Order with P8-3**: this workstream's step 1 (model) and step 2 (`StageRequest`, `LayoutPlan.passes`) land before P8-3 starts its sheet; P8-3 then deletes the interim adapter.

## 19. Done criteria

- A v5 setlist and a v3 show record open, read correctly and are written at 6 and 4; an older build opens them read-only; the `.cho` files are untouched.
- The stage never collapses a repeat: every pass is written out, `{chorus}` included; there is no `O` key, no collapse setting, no `RepeatCollapser`; an old `bindings.json` or sidecar mentioning collapse still loads.
- Chords only, First line only and Skip render as section 6.3 on stage and in P8-3's preview.
- The map strip shows in Live and Rehearsal with the transcribed sizes and states, follows the scroll, dims played passes, and carries mode tags; repeated labels carry "2 of 3" badges in the gutter.
- A chip click or 1-9 jumps with the "Jumped to" confirmation; Page Down behaves exactly as before when no loop is on.
- In a rehearsal `L` loops the current pass with a one-bar count-in at each wrap, with auto-scroll and with Page Down; in a gig it does nothing.
- The metronome is four (per meter) 30 pt pips with a 22 pt BPM bottom right in the band above the footer, Reduce Motion numeral; brand.md records the exception.
- Rehearse and Live from the library run one song with no checklist, no file in `shows/`, no gig log entry and no stats; P8-3 can call the same entry point with a slot.
- Guide pages updated, `keyboard.json` regenerated; every new UI is reachable by keyboard and labelled for VoiceOver.
- Targeted suites green per step; one `make quick` green; `make e2e-one` green for `SegueStageMapE2ETests` and `SegueArrangementE2ETests`.

## 20. Closed questions

Closed by Ryan on 2026-10-30 (**R158**; letters refer to the options as they were offered). The body above already reflects each answer.

1. **Metronome placement.** (b) The band above the footer, bottom right, per the mockup; this amends R151's "stage header" (R158 Q1; section 12). This differs from the recommendation.
2. **Current pass when the song does not scroll, or is laid out in 2-3 columns.** (a) Pass 1 is current until a jump pins another; nothing dims (R158 Q2; section 9).
3. **Page Down while a loop is on.** (a) A Page Down that would leave the looped pass wraps to its top with the count-in; in a song that fits, every Page Down wraps (R158 Q3; section 11).
4. **Count-in signal.** (a) The pips show for the count-in bar even when the pulse is off, and the click sounds only if `K` is on; a song without a tempo holds 2 s at the wrap (R158 Q4; section 11).
5. **Single-song shortcuts.** (a) Library menu "Rehearse Song" `⌥⌘↩` (shared with Setlist > Rehearse, never enabled together, one tested clash-test exception) and "Play Song Live" `⇧⌘↩` (R158 Q5; section 13.1).
6. **Map kind stripe colours.** (a) Section band colours on both the editor chips and the map (R158 Q6; section 7.2).
7. **Songs with fewer than two passes.** (a) The 58 pt band stays reserved and empty (R158 Q7; section 7.1).
8. **Single-song sessions: timing and Shortcuts.** (a) No rehearsal timing samples, no pre-show checklist, no Gig Mode Shortcut (R158 Q8; section 13.2).
9. **The PDF export's repeat rule.** (a) Phase 4 gets its own repeats option, default written out in full like the stage; the note is in `docs/phases/4-export.md` rule 6 (R158 Q9).

Related rulings since: R156 ("Rehearse this" in P8-3 passes the slot to `startSongSession`, section 5 item 12, as already specified).
