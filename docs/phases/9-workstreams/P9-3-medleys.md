# P9-3 - Medleys: several songs in one setlist slot, with written transitions

Phase 9 workstream (new, 2026-10-31). Rulings: `docs/release/decisions.md` **R176** (the first App Store release is v1.0 and builds Medleys before submission, specced with its open questions closed first), **R178** (this spec's questions closed, section 21), **R181** (the spec-fold choices confirmed: a song at most twice in a set, two medleys sharing a song refused, Rebuild drops an unlocked reprise with a note), **R138** / **R140** (Medleys are in the release; the one store media pass comes after it), and `docs/00-vision.md:91` ("Medleys - several songs joined into one set slot with a written transition"). Built on Phase 8 and earlier: **R122** / **R149** (per-slot arrangements, pass show modes), **R147** / **R148** (every pass written out, section map, jump and loop), **R150** / **R156** (single-song sessions, Rehearse this), **R153** / **R157** (set composer, `RomanNormalizer`), **R154** (pedal safety, serialized undo), **R167** / **R168** Q3 (one `SongTimeline`; the metronome switches tempo and meter at pass boundaries), **R169** (a walk-up into a key change is planned in the new key), **R172** / **R173** (slot time = tempo x played bars, unknown never invented, "~" when estimated), **R85** / **R86** / **R105** (breaks, changeover, intermission), **R115** (locked slots), **R16** (builder undo), **R113** (test budget), **R39** (design directions before new UI), **R79** (accessibility walk), the walkthrough rule "a song appears at most once per setlist" (with R178's one exception, the medley reprise, decision 8), and the owner's romanized Hindi rule (spell-check and autocorrect off in typed text; nothing "corrects" romanized Hindi).

**Sibling specs in this folder, written in parallel:** **P9-1** (PDF export) prints medleys in the songbook through section 13's interface; **P9-2** (singer view) adds `LayoutRequest.view`, which applies to every medley member (P9-2 section 6.12).

**Build order:** after Phase 8 has landed. Four sessions (section 18): **P9-3a** (core: model, schemas, timing, store) may start at once; **P9-3b** (builder UI) follows P9-3a and its step 0 design pick; **P9-3c** (stage) follows P9-3a and **P9-2a** (both edit `LayoutRequest`, `SongPreparation`, `StageRequest`); **P9-3d** (composer, assistant, Gig Log, sessions, guide, E2E) follows P9-3b and P9-3c. All before the R140 store media pass.

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling workstreams (P9-1, P9-2, others) edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks, keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`). The model, migrations, timing, the composer grammar and the stage layout are pure and get in-process tests; builder and stage behaviour gets in-process SegueUI tests. Exactly **one** new XCUITest class for the workstream (section 17.5, in P9-3d). At the end of each session ONE `make quick`, plus ONE `make e2e-one` per existing UI test class the session changed (section 17.6). No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- Before using any Apple API not already in the codebase, run the `apple-api-check` skill.
- Ryan's real library is never opened by a test or a session (section 8.4 proves the migration on a copy).
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any case section 21's closed questions do not cover.

## 1. Goal

A band plays "Kesariya into Tum Hi Ho into Channa Mereya" as one block: one row in the set, one chart on stage that flows from song to song without a song change, each song in its own key and capo with its own arrangement (usually a verse and a chorus each), and a written transition between them ("hold the D, drums fill, straight into the chorus"). The set's time, the assistant, the Gig Log and the songbook all understand the block as one slot made of several songs.

**In scope:** the medley slot in the setlist schema; members with their own key, capo, note and arrangement; transitions; the builder (make a medley from selected rows, reorder members, add and remove members, ungroup, rename, edit transitions); the stage (one plan through every member, the section map across members, header, pedal and keys, up-next, auto-scroll, metronome, play-along, singer view); slot time; the set composer and the set assistant; the show record and the Gig Log; Rehearse Medley; the songbook interface for P9-1; analytics; accessibility; guide; one E2E.

**Not in scope:** a medley as a library object reused across setlists (a medley lives in its setlist slot, like an arrangement, R122); crossfading audio; partial-song "snippets" other than arrangements (a member plays what its arrangement says, P8-3); a medley inside a medley.

## 2. Terms

- **Medley**: one setlist slot (`SetlistEntryKind.medley`) holding an ordered list of two or more **members**.
- **Member**: one song inside a medley, with its own stable item id, overrides (transpose, capo), slot note and slot arrangement.
- **Transition**: optional text written between two members, stored on the later member ("into this member"), shown on stage between them.
- **Segment**: a member's part of the stage plan (its passes laid out in a row of the one plan).
- **Member header**: the block the stage draws at the start of each segment: the member's title, its key line and, from the second member on, the transition.
- **Slot**: a song entry or a medley entry; a set row. Songs in a set = slot songs plus every member.

## 3. Current code (verified 2026-10-31)

Setlist model and store:

- `SetlistEntryKind { song(SongID), break(SetlistBreak) }`: `Packages/SegueCore/Sources/Setlists/Setlist.swift:151-154`. `SetlistEntry { itemId, kind, overrides, note, locked, arrangement }` with `songId`, `breakInfo`, `isBreak`, the song and break inits, and the codec (`songId` / `break` / `overrides` / `note` / `locked` / `arrangement` keys): `:157-282`.
- `Setlist.currentSchemaVersion = 6` and the version history: `:276-287`; `entry(_:)`: `:346`; `songEntries`, `songCount`: `:358-366`; `breakLabel(at:)`, `renumberBreaks()`: `:370-394`; `repeatedEntries` (the one-song-once rule for old files): `:398-403`.
- Migrator steps 0-5 (`5`: arrangement `steps` -> `passes`, `SlotArrangement.migrateV5`): `Setlists/SetlistStore.swift:461-497`. `insertSongs` (skips songs already in the set): `:237-256`; `addSong`: `:137`; `insertSong(_:overrides:into:at:)` (the composer's one-write add): `SetlistStore+Entries.swift:51`.
- `SetlistOverrides { transpose, capo }` and `applied(to:songCapo:)`: `Setlist.swift:77-112`.
- `entry.songId` and `case .song` are read in about 40 source files (`git grep -n "\.songId\b\|songEntries\|case \.song\|case let \.song" -- 'Packages/*/Sources/*'`): the heaviest are `Setlist.swift`, `AnalyticsEvent.swift`, `AppModel+Shows.swift`, `SetBuilder.swift`, `Packer.swift`, `SetlistsViewModel+Composer.swift`, `ShowRecord+Transitions.swift`, `SetlistStore.swift`, `SetEntriesList.swift`, `ShowController.swift`, `ReorderDiff.swift`, `SetRequest.swift`, `SetlistTiming.swift`, `SetlistEntryDisplay.swift`, `MissingTimesList.swift`, `BuilderLibraryColumn.swift`, `ArrangementEditorSheet.swift`. Each is audited in P9-3a step 2.

Builder:

- Arrange mode's multi-selection `arrangeSelection` (⇧ extends; ⌥↑/⌥↓ move rows): `Packages/SegueUI/Sources/SegueUI/Setlists/SetEntriesList.swift:20, 82-98, 168, 213`. Rows: `SetEntryRow.swift`, `SetBreakRow.swift`; the slot popover `SetEntryEditor.swift`; the arrangement mark `SlotArrangementMark.swift`.
- `ArrangingSlot { setlist, item }` and `openArrangement` / `setArrangement` (requires `entry.songId != nil`): `Setlists/SetlistsViewModel+Arrangement.swift:6-60`; the sheet is presented from `SetlistBuilderView.swift:107-118`.
- Menu shortcuts: `App/MenuShortcuts.swift:136-152` (Setlist menu: Start Show ⌘↩, Rehearse ⌥⌘↩, New Setlist ⇧⌘N, Pick ⌘1, Arrange ⌘2, Insert Break ⇧⌘B, Add Song by Name ⌘L, Arrange Sections ⇧⌘A, Move Up/Down ⌥↑/⌥↓). **⇧⌘M is free** (check `MenuAndAboutTests` at build time).

Time:

- `SlotTime { known(seconds:bars:tempo:estimated:), unknown(UnknownTime) }` and `SlotTimes.song` / `.slot(_:arrangement:)` / `.time(of:)`: `Packages/SegueCore/Sources/Library/Timing/SlotTime.swift:18-90`.
- `SetlistTiming.init(entries:times:target:changeover:)` (per-slot `times`, changeover after every song but the last of each part, unknown slots as lower bounds): `Setlists/SetlistTiming.swift:147-200+`; `ItemTiming`: `:98-145`.

Show and Gig Log:

- `ShowItemID = SetlistItemID`: `Shows/ShowRecord.swift:59`. `ShowItem { itemId, songId, title, origin, requestId, overrides, note, state, arrangement, arrangementState }`: `:100-117`. `ShowRecord.currentSchemaVersion = 4`, `planned: [SetlistEntry]`, `items`: `:301-313`. Show store migrator (step 3: `migrateV5` on items and planned): `Shows/ShowStore.swift:58-63`.
- `ShowController.start` turns each song entry into one `ShowItem` (breaks are skipped; they stay in `planned`): `Shows/ShowController.swift:79-100`; `missingEntries`: `:60`.
- Transitions: `advance`, `goBack`, `jump`, `insertNext` (after current), `playNow` (jumps to a pending item of the same song, else inserts before current and interrupts it), `move`: `Shows/ShowRecord+Transitions.swift:127, 298, 329, 336, 348, 416`; `insertionIndex(afterCurrent:)`: `:272`.
- `PlayedSong`, `GigLogEntry`, `playRecords` (the plays projection): `Shows/GigLog.swift:8-36, 134`. The Played list and its arrangement line: `Packages/SegueUI/Sources/SegueUI/GigLog/GigDetailView.swift:227-270`. `ReorderDiff`: `Shows/ReorderDiff.swift:8`.

Stage:

- `StageSlot { overrides, note, arrangement }` and `StageRequest.make` / `walkUps` / `renderModel` / `resolution`: `Packages/SegueUI/Sources/SegueUI/Live/StageRequest.swift:12-128`.
- `LayoutRequest { model, viewport, minLyricSize, zoom, columns, cues, notes, passes, style, walkUps }`: `Packages/SegueCore/Sources/LiveLayout/LayoutRequest.swift:340-364`. `SongPreparation.measure()` (one song's passes, walk-ups annotated across the played order, pass naming): `LiveLayout/SongPreparation.swift:14-58`. `PlanPass`, `StagePasses` (reading line, current pass, progress): `LiveLayout/LayoutPlan.swift`, `StagePasses.swift`.
- `LiveSession.relayout()` (up-next model, the request, the timeline, the scroller kept while `laidOutItem` is the same item): `Live/LiveSession+Viewport.swift:44-140`; `pageForward` performs `.next` at the bottom: `:251-270`. Header and footer: `Live/StageChrome.swift:9, 213, 241-256, 304-323`. Map strip: `Live/StageMapStrip.swift`. Play-along on stage: `Live/LiveSession+PlayAlong.swift:58, 155`.
- Single-song sessions: `AppModel.startSongSession(_:kind:slot:onEnd:)`: `App/AppModel+SongSession.swift:33-45`.

Composer and assistant:

- `SetComposerLine { empty, breakRow, song(query:key:keyToken:) }`, `parse(_:)` (never rewrites the typed text): `Setlists/SetComposerLine.swift:6-30`; `SetComposer.resolve`: `Setlists/SetComposer.swift:45-75`.
- `SetBuilder.build` and `withSlotTimes` (an arranged slot counts its arrangement's time): `SetAssistant/SetBuilder.swift:140, 205`; `RebuildLayout { entries, locked }`: `:53`; `Scorer.flow(from:to:)` (key and tempo flow between neighbours): `SetAssistant/Scorer.swift:224`; `AssistantSong`: `SetAssistant/AssistantSong.swift:9-31`.

## 4. Decisions

1. **A medley is a setlist entry kind**, `SetlistEntryKind.medley(SetlistMedley)`, holding its members inline. Rejected: a "joins the previous row" flag on ordinary song entries (every move, the assistant's Rebuild, the composer, show reorders and the reorder review would each have to keep members contiguous; one forgotten path splits a medley silently). The entry kind makes a split medley unrepresentable.
2. **Members keep everything a song slot has**: a stable `itemId` (unique in the setlist, also the show item id), `songId`, `overrides`, `note`, `arrangement`. The medley entry itself has an `itemId`, a `locked` flag and an optional `title`; it has no overrides, note or arrangement of its own.
3. **Transitions live on the later member** (`transition`, "into this member"). A medley of three songs has two transitions; the first member's is ignored and never written.
4. **In a show, members are items.** `ShowController.start` expands a medley into one `ShowItem` per member, in order, each carrying a `ShowMedleyRef` (slot id, title, index, count, transition). So the Gig Log, plays, per-song stats, requests, skip and "played" all stay per song, and the stage groups consecutive items with the same slot id into one plan (R178).
5. **One stage plan per medley.** The stage lays every member's passes into one plan, one segment per member, each with its own key, capo, arrangement, cues, notes, walk-ups and tempo; the map strip spans all of them; a member header opens each segment. Moving from member to member is scrolling, not a song change.
6. **The current member follows the reading line** and is committed to the show record (as `.next` / `.previous`) once the reading line has stayed in the new member for 1 s, or at once on a key (R178).
7. **Slot time is the sum of the members' slot times** (R172: each member's tempo x the bars of its played passes); no changeover between members; a member with an unknown time adds nothing and makes the medley's time a lower bound; "~" when any member is estimated (R173). Transitions add no time (none is ever invented).
8. **One song once per setlist, with one exception: the medley reprise** (R178, confirmed by R181). A song that is a medley member may also appear once elsewhere in the set as an ordinary song slot (a reprise), before or after the medley. Everything else stays refused: a song twice as a slot, a song in two medleys, a song twice in one medley. So a song appears at most twice in a set, and only as one member plus one slot. Every duplicate check asks `Setlist.canAdd(_:as:)` (5.1) instead of "is it in the set".
9. **Two to twelve members.** The editor refuses an edit that leaves a medley with more than 12 members, and a medley left with one member becomes that song's slot (auto-ungroup) in the same undo step.

## 5. Data model and schema

### 5.1 Types (SegueCore `Setlists/SetlistMedley.swift`, new)

```swift
/// A medley slot (P9-3): two or more songs played as one block.
public struct SetlistMedley: Sendable, Hashable, Codable {
    public static let maxMembers = 12
    /// Shown in the builder, on stage and in the Gig Log; nil = "Medley".
    public var title: String?
    public var members: [MedleyMember]
    public init(title: String? = nil, members: [MedleyMember])
    /// "Medley" when untitled; the title trimmed otherwise.
    public var displayTitle: String { get }
    /// The member titles joined " / " (needs the library: `memberLine(_ titles:)`).
    public static func memberLine(_ titles: [String]) -> String
}

/// One song in a medley: everything a song slot has, plus the transition into it.
public struct MedleyMember: Sendable, Hashable, Codable, Identifiable {
    public var itemId: SetlistItemID          // stable, unique in the setlist
    public var songId: SongID
    public var overrides: SetlistOverrides    // key and capo for this member
    public var note: String?                  // its slot note (the stage notes block)
    public var arrangement: SlotArrangement?  // its slot arrangement (R122, R149)
    public var transition: String?            // into this member; ignored for the first
    public var id: SetlistItemID { itemId }
}

public enum SetlistEntryKind: Sendable, Hashable {
    case song(SongID)
    case `break`(SetlistBreak)
    case medley(SetlistMedley)                // new
}
```

On `SetlistEntry`: `medley: SetlistMedley?` (accessor), `isMedley`, and **`songIds: [SongID]`** (a song slot: its song; a medley: its members in order; a break: none), which replaces `songId` at every call site that means "the songs this row plays" (5.5). `songId` stays and is nil for a medley. On `Setlist`: `songCount` counts members (a three-song medley is three songs; "12 songs"), new `slotCount`; `member(_ itemId:) -> (entry: SetlistEntry, index: Int)?`; `songSlot(_ itemId:) -> SongSlotRef?` (`.entry(SetlistEntry)` or `.member(entryId:, MedleyMember)`), used by the arrangement editor and the slot popover so a member is edited exactly like a song slot; `repeatedEntries` checks members too, under decision 8's rule (a member plus one slot of the same song is not repeated). New: `occurrences(of song: SongID) -> [SongOccurrence]` (`.slot(itemId, number)` / `.member(entryId, itemId, label)` in set order) and `canAdd(_ song: SongID, as: AddRole) -> AddVerdict` (`AddRole` `.slot` or `.member(of: entryId)`; `AddVerdict` `.ok`, `.reprise(of: SongOccurrence)` or `.refused(SongOccurrence)`), pure, the one place decision 8 is written.

### 5.2 JSON (setlist schema 7)

```json
{
  "itemId": "01JB7Q3M5D0Z8V4W9K2N6R1TXA",
  "medley": {
    "title": "Love medley",
    "members": [
      {"itemId": "01JB7Q3M5D0Z8V4W9K2N6R1TXB", "songId": "01HZ...K1",
       "overrides": {"transpose": 2}, "arrangement": {"passes": [...], "knownParts": [...]}},
      {"itemId": "01JB7Q3M5D0Z8V4W9K2N6R1TXC", "songId": "01HZ...K2",
       "transition": "Hold the D, drums fill, straight into the chorus"},
      {"itemId": "01JB7Q3M5D0Z8V4W9K2N6R1TXD", "songId": "01HZ...K3",
       "overrides": {"capo": 2}, "note": "Last chorus twice"}
    ]
  },
  "locked": true
}
```

- A medley entry is recognised by the `medley` key (checked after `break`, before `songId`). `title`, `overrides`, `note`, `arrangement`, `transition` are omitted when empty or nil, as for song entries; member codec keys are the song entry's keys plus `transition`.
- Member ids are new ULIDs from the store's id generator when a medley is made; making a medley from existing slots **keeps each slot's `itemId` as its member id**, so arrangements, notes and the composer's "already in set at number N" stay attached.
- `history`: "7 = medley slots (P9-3)". `Setlist.currentSchemaVersion = 7`.

### 5.3 Lenient decoding

- An unknown key in a medley or member is ignored. A member without a decodable `songId` or `itemId` is dropped (counted in the load report as one unreadable row, as other bad entries are).
- A medley with **one** member loads as a medley of one: it plays and times like that song, and the builder shows it with a quiet "Add a song or Ungroup" hint. A medley with **zero** members loads, is shown in the builder as "Empty medley" (removable, nothing else), and is left out of shows, timing and the assistant.
- A member whose song is also a slot elsewhere in the set is a reprise and loads normally (decision 8). A file that breaks decision 8 (the song in two medleys, twice in one medley, or twice as a slot; a hand-edited file) loads as saved and the extra rows are marked by `repeatedEntries`, as old duplicates are today.
- An empty or whitespace `title` or `transition` reads as nil.

### 5.4 Migrations

- **Setlist 6 -> 7**: migrator step `6: { _ in }` (additive). Old files read unchanged and are written at 7 on their next save. **An older build opens a v7 file read-only** (`VersionedJSON`), so it can never drop a medley by rewriting a file it does not understand.
- **Show record 4 -> 5**: `ShowItem` gains `medley: ShowMedleyRef?` (absent when nil) and `planned` may hold medley entries. Migrator step `4: { _ in }`. An older build opens a v5 record read-only. A running show from the previous build resumes unchanged (it has no medleys).
- `ShowMedleyRef { slot: SetlistItemID, title: String?, index: Int, count: Int, transition: String? }`: copied at show start like `overrides`, so the Gig Log stays truthful after the setlist is edited.

### 5.5 The `songId` audit (P9-3a step 2)

Every consumer found by the grep in section 3 is classified and changed in one step, with a test where behaviour changes:

| Kind of use | Change |
| --- | --- |
| "Which songs does this set contain" (smart filter "in setlist", Welcome seeding, analytics song counts) | `songIds` (a reprised song is counted once where the question is "which songs"; `songCount` counts it twice, as two plays) |
| "May this song be added here" (duplicate checks, "In set" ticks, the composer's already-in-set, `repeatedEntries`, drag in, the assistant's candidates) | `canAdd(_:as:)` / `occurrences(of:)` (decision 8) |
| "Build show items" (`ShowController.start`, `missingEntries`) | expand members (section 9.1) |
| "Time a row" (`SetlistTiming`, `SetlistEntryDisplay`, `MissingTimesList`, `SetBuilder.withSlotTimes`, `Packer`) | section 7 |
| "Edit one song slot" (slot popover, arrangement editor, "Rehearse this", key and capo commands) | `songSlot(_:)`, so a member edits like a slot |
| "Order of slots" (moves, reorder review, Rebuild layout) | unchanged: a medley is one slot |

A consumer that does not fit a row stops the step and goes to the orchestrator.

### 5.6 Store operations (SegueCore `Setlists/SetlistStore+Medleys.swift`, new; each one write)

`makeMedley(from items: [SetlistItemID], in:)` (two or more song slots or medleys, breaks refused; members in set order, a selected medley's members spliced in place; the medley sits where the first selected row was; the other rows are removed), `ungroup(_ medley:, in:)` (members become slots in place, transitions dropped), `addToMedley(_ songID: SongID, overrides:, medley:, at:, in:)`, `moveIntoMedley(_ item:, medley:, at:, in:)` (an existing slot joins), `removeFromMedley(_ member:, in:)` (the member becomes a slot right after the medley; one member left -> auto-ungroup), `moveMember(_ member:, to offset:, in:)`, `renameMedley`, `setTransition(_ text: String?, member:, in:)`, and `setMemberOverrides` / `setMemberNote` / `setMemberArrangement` behind `songSlot`. Each refuses (throws `SetlistError.medley(...)`) an add `canAdd` refuses (decision 8: a song already in another medley or in this one becomes a member; a song already a slot becomes a slot), a 13th member, or a break. Adding a member whose song is a slot elsewhere, or a slot whose song is a member, is allowed (a reprise). `makeMedley` refuses a selection holding the same song twice. `renumberBreaks()` is unaffected (a medley is not a break).

## 6. Builder UI

### 6.1 Making a medley

- In **Arrange** (or Pick's set column), select two or more song rows (click, ⇧-click, ⇧↑/⇧↓) and choose **Setlist > Make Medley** ⇧⌘M, or right-click > "Make Medley from 3 Songs". Disabled with fewer than two song slots selected, with a break selected, or read-only. Undo "Make Medley".
- The new medley row is selected; its title is empty (shows "Medley" in muted text); the title field takes focus only on double-click or Return on the selected row.
- Dragging a library song (Pick) or a set row onto a medley's member area adds it as a member at the drop point (a set row moves in; a library song already in a medley is refused with the composer's "already 4b" text as the help line; a library song that is a slot elsewhere joins as a member, and the help line reads "Also number 9: a reprise"). Undo "Add to Medley".

### 6.2 The medley row (direction picked in step 0, section 16)

Baseline anatomy, which every direction keeps:

- **Header line**, aligned with `SetEntryRow`'s columns: the slot number; a "MEDLEY" eyebrow (11 pt bold, 0.08 em tracking, `muted`); the title (double-click to rename; autocorrect and spell-check off; placeholder "Medley"); "3 songs"; the key path "G -> A -> D" (each member's displayed key, `SetlistEntryDisplay`); the medley's time (section 7); the lock (R115); a disclosure chevron (expanded by default; remembered per medley in memory only).
- **Member rows**, indented 24 pt, numbered "4a", "4b", "4c" (R178): each is a full `SetEntryRow` (title, key, capo, time, arrangement mark, quiet essentials dot) with the slot popover (key, capo, note, Sections...) exactly as a song slot.
- **Transition rows** between members: a "↳" glyph, a one-line text field (wraps to two lines when not editing), placeholder "Add a transition" (`muted`), autocorrect, spell-check and text completion off, at most 280 characters (refused beyond, with a beep), committed on Return or focus loss as one undo step "Edit Transition"; to its right the **derived change line**, muted 12 pt, only for what changes: "G -> A", "capo 2 -> no capo", "96 -> 120 BPM", "4/4 -> 6/8". A capo change gets the essentials-dot colour so a mid-medley capo move is never missed.
- **Reprises** (decision 8): a member whose song is also a slot, and that slot, each carry a quiet muted mark naming the other occurrence ("also 9" on the member, "reprise of 4a" on the slot), with help "This song is also in the set at 9"; VoiceOver reads it in the row label.
- Breaks cannot go inside a medley; a medley cannot go inside a medley.

### 6.3 Keyboard and menus

| Action | Keys / menu | Undo name |
| --- | --- | --- |
| Make Medley | ⇧⌘M, context menu | "Make Medley" |
| Ungroup Medley | Setlist > Ungroup Medley (⌥⇧⌘M), context menu on the header | "Ungroup Medley" |
| Move the medley | ⌥↑ / ⌥↓ on the header (one slot, like any row) | "Move Song" (today's) |
| Move a member within the medley | ⌥↑ / ⌥↓ on a member; at the medley's edge a beep, it never leaves | "Move Song in Medley" |
| Remove from Medley | context menu on a member; dragging it out of the medley | "Remove from Medley" |
| Remove the member from the set | ⌫ on a member (today's row delete) | "Remove Song" |
| Rename | double-click the title, or Return on the selected header | "Rename Medley" |
| Edit a transition | click its row, or Tab from the member above | "Edit Transition" |
| Arrange a member's sections | ⇧⌘A on a member (today's command) | P8-3's |
| Rehearse Medley | context menu on the header | none (section 12) |

↑/↓ move the selection through header, members and on to the next slot; ← / → on a header collapse and expand it. Every action is in a menu or context menu as well as on a key. Each is one builder undo step (R16), saved through the serialized snapshot path (R154).

### 6.4 Pick mode

The library column's tick reflects the song's plain slot, as today. A song that is only a medley member shows unticked with a quiet "In Love medley" mark; ticking it appends a reprise slot (the tick then shows on), and unticking removes that slot only, never the member (members are removed in the builder). Ticking a song appends a slot as today (never a member).

### 6.5 Accessibility

The medley header is a container "Love medley, medley of 3 songs, 7 minutes 40 seconds" with actions Ungroup, Rename, Rehearse Medley, Collapse; each member "4b, Tum Hi Ho, key A, in Love medley" with today's slot actions plus Move Earlier in Medley, Move Later in Medley, Remove from Medley; each transition field "Transition into Tum Hi Ho". Identifiers: `segue.setlist.medley`, `.medley.title`, `.medley.member`, `.medley.transition`, `.medley.changes`. New UI joins the R79 walk.

## 7. Slot time (R172, R173)

- `SlotTimes.medley(_ members: [(record: SongRecord?, member: MedleyMember)]) -> MedleyTime` (pure, `Library/Timing/SlotTime.swift`): each member's `SlotTimes.slot(record, arrangement: member.arrangement)`; a member whose song is missing from the library is unknown with a new reason `UnknownTime.missingSong` ("no chords" or "no tempo" would be false).
- `MedleyTime { members: [SlotTime]; known: TimeInterval; unknownMembers: [Int]; estimated: Bool }`: `known` sums the known members, no changeover between them, no transition time.
- `SetlistTiming` takes a medley's `MedleyTime` in a new `medleyTimes: [SetlistItemID: MedleyTime]` input; the medley row's `ItemTiming` gets `time = known` (nil when no member is known), `memberTimings` (start and time per member, for the nested rows), `unknownMembers` and `estimated`. Starts after a medley with an unknown member are lower bounds ("≥"), as after any unknown slot. A changeover is added after the medley as after any slot (R86).
- `unknownCount` and `unknownItemIds` count **members** (songs without a time), so the header's "2 unknown" and the no-time list (P8-8 5.5) list "Tum Hi Ho (in Love medley)" with its Tempo field, exactly like a song slot.
- Row text: all known "7:40", help "Kesariya 2:40, Tum Hi Ho 2:10, Channa Mereya 2:50"; some unknown "≥5:30", help "1 of 3 songs has no time: no tempo"; any estimated "~7:40" (and "~" before "≥" when both, as P8-8 5.3). VoiceOver: "7 minutes 40 seconds, medley of 3 songs" / "at least 5 minutes 30 seconds, incomplete: 1 song has no time".
- The `SongTimeCache` (P8-8 5.9) memoises per member (song, content hash, timing, arrangement), so a medley costs the same as its members as slots.

## 8. Show record and Gig Log

### 8.1 Show start

`ShowController.start` turns a medley entry into one `ShowItem` per member, in order, with `itemId = member.itemId`, `overrides`, `note`, `arrangement` from the member and `medley = ShowMedleyRef(slot: entry.itemId, title:, index:, count:, transition:)`. A member whose song is missing is omitted (listed by `missingEntries` and the pre-show checklist as "Love medley: Tum Hi Ho is missing"); `count` and `index` are over the members that remain. A medley left with no playable member is omitted as a whole. Breaks behave as today.

### 8.2 Transitions inside a running show (`ShowRecord+Transitions.swift`)

- `next` / `previous` / `jump` / `skipCurrent` work per member as on any item (the stage drives them as in section 9.6).
- **Insert Next, Play Now and Play Request while the current item is a medley member** place the new item **right after the medley's last member** (never between members) and do not interrupt the medley; the stage flashes "Plays after the medley" (R178). With the current item outside a medley they behave as today. `insertionIndex(afterCurrent:)` gains this rule.
- `playNow` of a song that is a pending member jumps to that member (today's "jump to a pending item of the song"), and the stage opens the medley plan scrolled to it. With a reprise both occurrences may be pending: Play Now, a request and search's jump take the **first pending occurrence after the current item** (else the first pending one); search lists both rows ("Kesariya, 4a in Love medley" and "Kesariya, 9") so the performer can pick the other.
- **`move`** (the drawer's reorder) moves a medley's members as one block: the drawer lists the medley as a group (header plus nested members, members not draggable during a show), and a drop is translated to a block move.
- The end-of-show **reorder review** (`ReorderDiff`) compares slots: consecutive items with the same `medley.slot` are one slot keyed by that id, so a medley that played in its planned place reads "unchanged" and saving a new order writes the medley entry back whole.

### 8.3 Gig Log

- `PlayedSong` is unchanged (one per member, so plays, "last played" and per-song stats count every member song). A reprised song played twice in one gig has two `PlayedSong`s: play counts count both, "last played" is the later one, and any figure that counts gigs a song was played in counts that gig once (P9-3a step 3 audits the `playRecords` consumers for this). `GigLogEntry` gains `slots: [PlayedSlot]` (`.song(PlayedSong)` or `.medley(title:, members: [PlayedSong], skipped: [ShowItem])`), built from consecutive played items with the same `medley.slot`.
- **The Played list nests members under the medley** (the owner's parent/child rule): "4  Love medley" (header row, start time of its first member, a "Medley · 3 songs" detail), then "4a Kesariya", "4b Tum Hi Ho", "4c Channa Mereya" indented, each with its own arrangement line (`GigPlayedListLines.arrangementLine`). A skipped member shows under its medley as "skipped" in `muted`, and in the Skipped list as "Tum Hi Ho (in Love medley)".
- Gig Log text export and copy (if present) use the same nesting with indentation. No played-length column (R173 / R174).

### 8.4 Migration proof on a copy

P9-3a's last step copies Ryan's library folder to the session scratchpad (never the original), opens it with the new build and records in the commit: no setlist or show file changes on open; a setlist edited without making a medley is written at 7 with identical entries; a medley made, saved, and reopened round-trips; the copy opened by the previous build (if available) shows the v7 file read-only. If the library path is not known, ask the orchestrator.

## 9. The stage

### 9.1 One plan per medley

- `LayoutRequest` gains `segments: [LayoutSegment]`; today's single-song fields become the one-segment case through a convenience initializer, so existing call sites (the stage, P8-3's preview, tests) do not change.

```swift
public struct LayoutSegment: Sendable, Equatable {
    public var model: RenderModel           // the member's model with its overrides
    public var passes: [PlayedPass]?        // its applied arrangement, nil = full song
    public var cues: [SongCue]
    public var notes: [String]              // its song note and its member note
    public var walkUps: BassLineContext?
    public var header: MemberHeader?        // nil for a plain song
}
public struct MemberHeader: Sendable, Equatable {
    public var title: String                // the member's display title
    public var keyLine: String              // "A, capo 2, 120" (P9-2: "Key A, 120" in singer view)
    public var index: Int, count: Int        // "2 of 3"
    public var transition: String?          // from the second member on
    public var changes: [String]            // the derived change line, "G -> A", "capo 2 -> no capo"
}
```

- `StageRequest.make(medley:...)` (new) builds one segment per consecutive item with the same `medley.slot`, using each member's song, `StageSlot(item)` and `StageRequest.renderModel`; resolutions are per member (an out-of-date member plays its full song, R122, and the pre-show checklist lists it).
- `SongPreparation` measures each segment as it measures a song today (cues pinned per member's own sections, passes, walk-ups, pass naming) and concatenates the measured sections, inserting a **member header block** (new `LayoutBlock.Content.memberHeader`, new text roles `.memberTitle`, `.memberKey`, `.transition`, `.memberChanges`) before each segment. The notes block: the first member's notes at the top as today; a later member's notes inside its header block, under the transition.
- **Pass naming across members**: passes are numbered within their member ("Chorus 2/3" counts that member's choruses only); `PlanPass` gains `segment: Int`. Keys 1-9 and chip clicks address the medley's shown passes in played order (the first nine).
- **One lyric size** for the whole plan (`FitSearch` over all segments), so the chart does not jump in size between songs. Columns as the first member's `LivePrefs` choice, else the Settings default.
- **Walk-ups** (bass view): each member's walk-ups as today, plus, at a member boundary, the walk-up from the member's last chord into the next member's first chord, planned in the next member's key (the R169 rule) and drawn like any walk-up (R178). Fills stay within a member (they are saved per song).

### 9.2 Member header block (stage)

Drawn full width at the start of each segment (exact look from step 0): the member title (bold, 0.75 ly, `ink`) with "2 of 3" (semibold 12, `muted`), the key line (`muted`), then, from the second member on, the transition text in the cue style (the stage's cue callout colours, never colour alone: a "↳" glyph leads it) and the change line ("G -> A · capo 2 -> no capo · 96 -> 120 BPM"; a capo change in `cueText`). A one-line rule above it separates it from the previous member's last pass.

### 9.3 Section map across members

The map strip lists every shown pass of every member in played order. A member boundary is marked (direction in step 0): baseline, an 8 pt gap with a 1 pt `lineStrong` divider and the member's short title in the first chip's mode line when the pass is Full ("TUM HI HO" in the mode line's style). Current, played and looping states, progress bar, number hints and accessibility as P8-2 section 7; each chip's label adds the member ("Chorus, 2 of 3, Tum Hi Ho"). Chips that do not fit scroll, keeping the current chip in view (P8-2 7.2).

### 9.4 Header and footer

- **Header**: the current member's title with a "Medley 2 of 3" chip (identifier `segue.live.medley`, label "Love medley, song 2 of 3"), the current member's key line, "Arranged" / "Full song" for that member; progress dots: one per slot, a medley's dot drawn as a short bar split into its members' ticks (the current tick lit).
- **Footer up-next**: inside a medley before its last member: "Next in medley" (label) + the next member's title + its key line, then the transition's first line (tail-truncated). On the last member: the next slot as today; when the next slot is a medley: "Up next: Love medley" + "Kesariya + 2 more" + the first member's key line.
- **Metronome**: the current member's tempo and meter; it switches at the member boundary on the beat grid, as at pass boundaries (R168 Q3).

### 9.5 Pedal and keys

- **Page Down / pedal (`pageForward`)**: one screenful at a time through the whole medley, across member boundaries, with no stop; at the bottom of the medley, the next slot (as at the bottom of a song). **Page Up / `pageBack`** mirrors it. P8-1's guards apply (held or repeating keys never advance, a page-forward during an in-flight change is ignored, the last slot stays put).
- **→ / Space (`next`)**: the next member's header (seek to its top minus 14 pt, the jump offset); on the last member, the next slot. **← (`previous`)**: the current member's header if the reading line is past it, else the previous member's; on the first member, today's previous slot.
- **`x` (Skip Song)**: skips the current member only (marked skipped) and seeks to the next member (R178).
- **1-9, chip clicks, `L` loop**: as P8-2, across members; a loop stays inside one pass.
- **Home**: the medley's top. **Search, requests, drawer**: as 8.2.

### 9.6 Following the current member (pure `LiveLayout/MedleyFollow.swift`)

- `MedleyFollow.member(at readLine:, plan:) -> Int` from `plan.passes[].segment` and the header blocks' tops.
- `LiveSession` commits a change of member to the show record when the reading line has been in the new member for **1.0 s** on the scroll clock (so a quick scroll past a boundary does not log a play), or **at once** on `→`, `←`, `x`, a jump or a chip click. Forward by one = `.next` (the previous member marked played); back by one = `.previous`; further = `.jump`. The plan and the scroller are **not** rebuilt for a member change: `laidOutItem` is keyed on the medley slot, so `relayout()` keeps the plan while the current item moves inside it.
- Auto-advance never crosses out of the medley: leaving it is today's song change (bottom of the medley, `→` on the last member).

### 9.7 Auto-scroll

Piecewise: `AutoScroller` gains `segments: [ScrollSegment { fromOffset, speed }]`. Each member's speed = its segment height / its slot time (`SlotTimes.slot` of the member's played passes, P8-8 5.6), so a slow song into a fast one scrolls at the right speed in each (R178). A member with no time scrolls at the medley's average known speed, or, with no member known, at the default speed with P8-8's add-a-tempo hint. `[` and `]` scale every segment. `instant(reaching:)` (the loop wrap) integrates over the segments.

### 9.8 Play-along (Rehearsal, P8-6b, P8-7)

`P` plays the medley as one timeline: each member's `SongTimeline` (its key, tempo, meter, corrections, walk-up density, saved fills) concatenated in order, with the boundary walk-up of 9.1 when the bass view and walk-ups are on. No gap and no count-in between members (one count-in at the start, R162 Q5 rule for the stage's start); the click switches tempo at the boundary. A member with no tempo stops play-along at its header with the flash "No tempo for Tum Hi Ho: play-along stops here". Audio drives the scroll (R162 Q4) across members; the follow model of 9.6 commits members as the audio crosses them. Live stays silent.

### 9.9 Singer view (P9-2)

`LayoutRequest.view` applies to every segment; member headers keep their title, transition and the singer key line, and drop the capo from the change line.

### 9.10 Reprises on stage (decision 8)

- A reprise is an ordinary show item with its own item id: it has its own progress dot, its own played / skipped state and its own place in up-next. The member and the reprise slot each use their own overrides, note and arrangement, so a reprise can be a different key or just the last chorus.
- Per-song stage memory (`LivePrefs`: zoom, columns) is per song, so the two occurrences share it.
- Up-next and the pre-show checklist name the occurrence ("Kesariya (reprise)") when the song has already been played or is pending in a medley, so the band is never surprised by a repeated title.
- Requests, Play Now and search follow 8.2's first-pending-occurrence rule.

## 10. Set composer (R153)

- Grammar (`SetComposerLine`): a line containing **" + "** (space, plus, space) is a medley: `case medley([SongPart])` where each part is parsed as today's song query with its own optional key token ("kesariya in A + tum hi ho + channa mereya (Am)"). Titles containing "+" without spaces ("C++ Blues") stay one song; a title that really contains " + " is found by typing it without the spaces around "+" (the matcher's word rules ignore the "+"). The typed text is never rewritten (P8-5 rule).
- Resolution: each part resolves with `SetComposer.resolve`; the ghost shows a medley preview: "Medley · Kesariya (A) + Tum Hi Ho (G) + Channa Mereya (Am) · 7:40". ↑/↓ and Tab cycle the alternatives of the part the caret is in. Return appends one medley slot (one write, one undo step "Add Medley"), only when every part resolves, `canAdd(_:as: .member)` passes for every part (no part already in another medley) and no two parts name the same song; otherwise the status line names the first failing part ("No song matches 'chana' (song 3)", "Tum Hi Ho is already 4b") and nothing is added. A part that is a slot elsewhere is allowed, and the ghost marks it "(reprise of 9)".
- A plain song line whose song is only a medley member is allowed as a reprise (decision 8): the ghost reads "Kesariya · also 4a in Love medley: adds a reprise"; a song already a slot is refused as today.
- A single " + " part list of one song is just a song.
- Analytics: row 24's `segue.action` gains `medley`; new `segue.members` (SmallBucket) on that action only.

## 11. Set assistant

- **Rebuild keeps every medley in place**, locked or not, and never changes its members (the assistant cannot compose medleys); its lock control shows on and disabled with the help "Medleys stay in place on Rebuild" (R178).
- The assistant never makes a reprise: member songs are never candidates for other slots. A reprise slot the user made is kept when locked (R115) and otherwise left out like any unpicked slot, with the draft's note "Kesariya's reprise was left out: lock it to keep it" (R181).
- **Time**: a medley counts its `MedleyTime.known` toward the target; with unknown members it counts what is known and the draft's note says "1 song in a medley has no time" (the left-out list does not apply: the medley is kept, not left out).
- **Flow** (`Scorer.flow`): the slot before a medley flows into its **first** member; the slot after it flows from its **last** member; `SlotContext` for a medley's neighbours uses those members' keys and tempos.
- New sets from a request never contain medleys. Requests can name a medley member like any song (it is still in the library); the request rules of decision 8 apply (a member song may be requested as a reprise slot; a song already a slot is excluded).

## 12. Rehearse Medley and single-song sessions

- `AppModel.startSongSession` generalises to `startSlotSession(_ entry: SetlistEntry, kind: ShowKind, onEnd:)`, which builds the in-memory one-entry setlist from a song entry or a medley entry (unsaved environment, no checklist, nothing logged, R150 / R158 P8-2 Q8). `startSongSession` becomes a wrapper (library songs, the full song as written).
- **Rehearse Medley** (the header's context menu and VoiceOver action; no shortcut, so ⌥⌘↩ keeps meaning Setlist > Rehearse and the P8-2 clash-test exception is unchanged) rehearses the whole medley as arranged. When it ends, the builder reselects the medley.
- **Rehearse this** in a member's Arrange Sections sheet (P8-3) rehearses that member alone, as arranged (R178).

## 13. PDF songbook: interface for P9-1

P9-3 provides, P9-1 consumes:

1. `Setlist.printSlots -> [PrintSlot]` with `PrintSlot.song(SetlistEntry)` and `.medley(SetlistEntry, members: [MedleyMember])`, in set order, breaks as today.
2. `MemberHeader.make(member:previous:record:previousRecord:)` (pure, SegueCore): the title, key line, transition and change line exactly as the stage draws them (9.2), so print and stage say the same thing.
3. `MedleyTime` for the setlist page's time column.

Print behaviour (closed by R178 with P9-1 section 18):

- **Setlist page**: the medley is one numbered row ("4  Love medley") with its members indented under it, each with its key, capo, time and page link numbered "4a", "4b" (R178).
- **Table of contents and PDF outline**: the medley is a parent entry with the members as children, each pointing at its member header's page.
- **Body**: members **flow on without page breaks** after the medley's first page, with the transition between them (R178; P9-1 section 9). Each member opens with its member header block and transition; each member uses its own overrides and, if P9-1 prints arrangements, its own arrangement; P9-1's keep-together rules apply to the member header (never orphaned at a page bottom: it needs at least two line pairs of its member with it).
- **Single chart export of a medley** (row context menu "Export Medley PDF...", if P9-1 offers per-slot export): the same body alone.
- Singer view printing (P9-2 section 8) applies member by member.

## 14. Analytics (non-PII, closed vocabulary, WS3)

| Signal | Params | When | Throttle | Question |
| --- | --- | --- | --- | --- |
| Next free row: `Segue.Setlist.medley` | `segue.action` (`created`, `ungrouped`, `memberAdded`, `memberRemoved`, `memberMoved`, `renamed`, `transitionEdited`), `segue.members` (SmallBucket, after the action), `segue.entry` (`menu`, `contextMenu`, `composer`, `drag`, `key`) | each builder medley action | daily per (action, entry) | Are medleys used, how big, which entry point, and are transitions written at all |

- `FeatureKey.medley` (row 8): context `stage` once per run that shows a medley; `builder` for Rehearse Medley.
- Row 30 `Segue.Setlist.timed` gains `segue.medleys` (SmallBucket) and `segue.medleyUnknown` (Bool: a medley has a member without a time).
- Row 24 (composer): `segue.action` gains `medley`, `segue.members` (SmallBucket, medley only).
- Never titles, transition text, ids or keys. Update `AnalyticsEvent` (new `AnalyticsEvent+Medley.swift`), the throttle cases, `ServicesVocabularyTests` and the WS3 table in the same change.

## 15. Guide pages

- New `guide/src/content/docs/medleys.mdx`: making a medley (select, ⇧⌘M), the medley row, keys and capo per song, arranging each song's sections, transitions and the change line, reordering, ungrouping, the composer's " + ", the stage (one chart, the map across songs, pedal and → behaviour, up-next), rehearsing a medley, time, the Gig Log. Real screenshots (`make docs-shots ONLY=medley-builder,medley-stage` once the UI lands; the full re-capture is R140's pass).
- Edits: `build-a-set.mdx` (a short "Medleys" paragraph linking the page), `go-on-stage.mdx` (pedal through a medley), `running-time.mdx` (a medley's time is its songs' times, no changeover between them), `set-assistant.mdx` (medleys stay in place), `gig-log.mdx` (nested members), `arrange-sections.mdx` (arranging a member), `rehearse.mdx` (Rehearse Medley, play-along across songs), `keyboard.mdx` via `make guide-keys`. Keep pages short (the owner's rule on copy).
- `SegueLinks.medleys` -> `/guide/medleys`; verify against the local build and the live site once deployed.

## 16. Design directions (step 0 of P9-3b, R39)

Rendered in the session scratchpad `p9-3/` on real material (a three-song Bollywood medley with key and capo changes, one member arranged to Verse 1 + Chorus, transitions written), light and dark builder, stage theme, for Ryan to pick before any UI step:

- **Builder row**: **A - Group card**: the medley as one card (`surfaceAlt`, 10 pt radius) holding header, members and transition rows. **B - Bracket**: ordinary rows joined by a 3 pt left bracket in the section band colour, transitions as slim rows inside the bracket. **C - Collapsed chip row**: one row showing the members as chips ("Kesariya · Tum Hi Ho · Channa Mereya"), expanding in place to A's layout to edit.
- **Stage map**: **A - Dividers** (9.3 baseline). **B - Member groups**: each member's chips inside a faint container with its short title as a tab above (costs no height: the tab sits in the 10 pt gap). **C - Two tiers**: the member names as a thin row, the current member's passes below.
- **Member header on stage**: a quiet rule plus title line (as 9.2), versus a full-width transition card.

Recommendation: builder **A** (one block reads as one slot, matching the decision that a medley is one entry), map **B**, header as 9.2.

## 17. Test plan (R113)

### 17.1 SegueCore model and store (`SetlistMedleyTests`, `SetlistStoreMedleyTests`, new; extend `SetlistTests`, `ShowRecordTests`)

- v7 codec round trip; omitted empty keys; member order; `transition` ignored on the first member; unknown keys ignored; a member without `songId` dropped; one-member and zero-member medleys load as 5.3; a v6 file reads and writes at 7 unchanged otherwise; an older reader sees `newerSchema`.
- `songIds`, `songCount` (members counted), `slotCount`, `songSlot`, `member`, `repeatedEntries` with members; `canAdd` and `occurrences` table-driven over decision 8 (member plus slot allowed either way round; two slots, two medleys, twice in one medley refused).
- Store: make from slots (ids kept, position, splicing a selected medley), refuse breaks, decision 8 duplicates and a 13th member, allow a reprise either way round, ungroup in place, remove leaving one auto-ungroups, move within, move into, add from library, rename, transitions trimmed and capped; each one write.
- Show record 4 -> 5; `ShowController.start` expands members with refs, omits missing members, omits an all-missing medley.
- Transitions: insert next, play now and play request inside a medley land after its last member and do not interrupt; play now of a pending member jumps; with a reprise pending twice, play now and requests take the first pending occurrence after the current item; drawer move moves the block; `ReorderDiff` treats a medley as one slot.
- Gig Log: `slots` grouping, skipped members, plays per member, a reprise played twice (two plays, one gig).

### 17.2 Time (`MedleyTimeTests`, new, table-driven)

All known (sum, no changeover inside, one changeover after); one unknown (lower bound, unknown count by member, "≥" after); estimated ("~"); missing song (`missingSong`); arranged members (Skip passes add nothing, P8-8 5.2); a medley in each part of a set with breaks.

### 17.3 Composer and assistant (`SetComposerLineTests`, `SetComposerResolveTests`, `SetBuilderTests`, extend)

" + " parsing with per-part keys, "C++ Blues" stays one song, failing part reported with its number, duplicate parts refused, a part that is a slot elsewhere allowed as a reprise, a plain line for a member-only song adds a reprise; Rebuild keeps medleys, excludes members from candidates, and keeps a locked reprise; flow uses first and last members; target counts known time.

### 17.4 Stage layout and session (`LiveLayoutMedleyTests`, `MedleyFollowTests`, new; `StageMedleyTests`, new SegueUI)

- Plan: segments in order, member header blocks, pass naming per member, `PlanPass.segment`, one lyric size, keys 1-9 across members, the boundary walk-up in the next member's key, singer view per segment.
- `MedleyFollow`: member at reading line; 1 s dwell commit with a scripted scroll clock; immediate commit on keys; no relayout on a member change (the scroller's offset is kept).
- Pedal: Page Down crosses members without a song change and leaves at the bottom; → / ← / `x` per 9.5; P8-1 guards still hold.
- Piecewise auto-scroll speeds and `instant(reaching:)` over segments.
- Header chip, footer "Next in medley" and the next-slot-is-a-medley text, metronome tempo switch at the boundary; a reprise slot after its medley gets its own dot and the "(reprise)" up-next label.
- Play-along timeline concatenation; stop at a member without tempo.

### 17.5 XCUITest (one new class, P9-3d)

**`SegueMedleyE2ETests.testMakeMedleyAndPlayThrough`**: fresh library; seed three songs with tempos in different keys and a setlist holding them as slots (as `SegueSetlistBuilderE2ETests` seeds); Arrange -> select rows 1-2 with ⇧↓ -> ⇧⌘M -> the medley row shows "2 songs" and "G -> A" -> type a transition -> on disk the setlist is schema 7 with one medley of two members and the transition -> the set total equals the sum of the three times plus one changeover -> Start Show through the checklist -> the map lists both members' passes, the header reads "Medley 1 of 2" -> → -> the second member's header and transition are visible, and the footer now reads "Up next" with song 3 (it read "Next in medley" on the first member) -> Page Down to the bottom -> song 3 -> End Show -> the Gig Log lists the medley with two nested members. Screenshots for the review.

### 17.6 Existing UI tests changed

`SegueSetlistBuilderE2ETests` (only if row identifiers or numbering it asserts change), `SegueSetComposerE2ETests` (only if the composer row's ids change), `SegueSetlistGigLogE2ETests` (only if the Played list's structure it reads changes): one `make e2e-one` each, in the session that changes them.

## 18. Build sessions and steps

**P9-3a - core** (SegueCore only):

1. Types, codec, lenient decoding, schema 7 and show record 5 migrations; suites 17.1 (model part).
2. The `songId` audit (5.5), one classified change per consumer, with tests where behaviour changes.
3. Store operations (5.6); `ShowController.start`; transitions (8.2); `ReorderDiff`; Gig Log `slots`; suites 17.1.
4. `MedleyTime` and `SetlistTiming`; suites 17.2. Migration proof on a copy (8.4). One `make quick`.

**P9-3b - builder** (after P9-3a):

0. Design directions (section 16) rendered; Ryan picks; record the pick here.
5. Medley row, member rows, transition rows, change line, selection and keys, menus and context menus, drag in and out, Pick ticks, undo names, accessibility; in-process builder tests (extend `SetBuilderPickTests` and the builder view model tests). One `make quick`; `make e2e-one` for any changed class (17.6).

**P9-3c - stage** (after P9-3a and P9-2a):

6. `LayoutSegment`, `MemberHeader`, segments in `SongPreparation` and plan assembly, `StageRequest.make(medley:)`, boundary walk-ups; `LiveLayoutMedleyTests`.
7. `MedleyFollow`, session wiring (no relayout on member change), pedal and keys, header and footer, map across members (picked direction), piecewise auto-scroll, metronome; `MedleyFollowTests`, `StageMedleyTests`.
8. Play-along across members; extend the play-along tests. One `make quick`.

**P9-3d - the rest** (after P9-3b and P9-3c):

9. Composer " + "; assistant rules; `startSlotSession` and Rehearse Medley; Gig Log nested list; suites 17.3 and the session tests.
10. Analytics (section 14), WS3 table, vocabulary test.
11. Guide pages and `SegueLinks`; `make guide-keys`; the E2E (17.5); one `make quick`; one `make e2e-one SegueMedleyE2ETests`; screenshot commands for Ryan if the session cannot run them.

## 19. Files

- **New**: `SegueCore/Sources/Setlists/SetlistMedley.swift`, `SetlistStore+Medleys.swift`; `LiveLayout/LayoutSegment.swift`, `MedleyFollow.swift`; `Services/AnalyticsEvent+Medley.swift`; `SegueUI/Sources/SegueUI/Setlists/MedleyRow.swift`, `MedleyTransitionRow.swift`, `SetlistsViewModel+Medley.swift`; `Live/StageMedleyHeader.swift`, `LiveSession+Medley.swift`; `GigLog/GigMedleyRows.swift`; `AccessibilityID+Medley.swift`; tests in section 17; `UITests/SegueMedleyE2ETests.swift`; `guide/src/content/docs/medleys.mdx`.
- **Changed**: `Setlists/Setlist.swift`, `SetlistStore.swift` (version, migrator), `SetlistTiming.swift`, `SetComposerLine.swift`, `SetComposer.swift`; `Library/Timing/SlotTime.swift`; `Shows/ShowRecord.swift`, `ShowStore.swift`, `ShowController.swift`, `ShowRecord+Transitions.swift`, `ReorderDiff.swift`, `GigLog.swift`; `SetAssistant/SetBuilder.swift`, `Packer.swift`, `Scorer.swift`; `LiveLayout/LayoutRequest.swift`, `SongPreparation.swift`, `PlanAssembly.swift`, `LayoutPlan.swift`, `AutoScroll.swift`, `StagePasses.swift`; every consumer of the 5.5 audit; `SegueUI/Setlists/SetEntriesList.swift`, `SetEntryRow.swift`, `SetEntryEditor.swift`, `SetlistEntryDisplay.swift`, `MissingTimesList.swift`, `SetlistsViewModel+Arrangement.swift`, `SetlistsViewModel+Composer.swift`, `SetComposerRow.swift`, `BuilderLibraryColumn.swift`; `Live/StageRequest.swift`, `LiveSession+Viewport.swift`, `LiveSession+PlayAlong.swift`, `StageChrome.swift`, `StageMapStrip.swift`, `StagePanels.swift` (drawer); `App/AppModel+SongSession.swift`, `App/Commands/SetlistCommands.swift`, `App/MenuShortcuts.swift`, `App/SegueLinks.swift`; `GigLog/GigDetailView.swift`; `docs/release/specs/WS3-services.md`; `UITests/e2e-map.tsv`; guide pages in section 15.

## 20. Done criteria

- A medley is made from selected rows (adjacent or not) in one action, shows as one slot with nested members and transitions, and every member keeps its own key, capo, note and arrangement; reorder, add, remove, ungroup and rename are one undo step each.
- Setlist schema 7 and show record 5 load leniently; old files are unchanged on open; an older build opens new files read-only; the migration is proved on a copy of Ryan's library.
- On stage a medley is one chart: member headers with transitions and change lines, the map across members, Page Down through it without a song change, → / ← per member, the up-next "Next in medley", the metronome and auto-scroll per member; the Gig Log records each member played or skipped and nests them under the medley.
- Slot time is the members' sum, lower-bounded and flagged when a member has no time, "~" when estimated; the composer's " + " adds a medley; a medley member may also appear once as a reprise slot, and every duplicate check follows decision 8; Rebuild keeps medleys and flows through their first and last members; Rehearse Medley plays it unlogged; play-along runs across members.
- P9-1 has `printSlots`, `MemberHeader.make` and `MedleyTime` to print medleys.
- Analytics, accessibility, guide pages and `keyboard.json` updated; targeted suites green per step; one `make quick` per session; `make e2e-one` green for `SegueMedleyE2ETests` and any changed class.

## 21. Closed questions (R178 and R181, 2026-11-01)

1. **How a medley exists in a running show:** one show item per member, grouped into one plan (R178; decision 4).
2. **When the current member changes:** it follows the reading line, after a 1 s settle, at once on a key (R178; 9.6).
3. **Requests and Play Now during a medley:** queued after the medley (R178; 8.2).
4. **Rebuild and medleys:** Rebuild always keeps medleys (R178; section 11).
5. **Walk-up into the next member:** yes, in the next member's key (R178; 9.1).
6. **Composer syntax:** songs joined with " + " (R178; section 10).
7. **Auto-scroll across members:** per member (R178; 9.7).
8. **A song in a medley and again in the set:** allowed as a reprise; the once-per-set rule and its duplicate checks make that one exception. A song appears at most twice, once as a member and once as a plain slot; two medleys sharing a song are refused; Rebuild drops an unlocked reprise with a "lock it to keep it" note (R178, differing from the spec's recommendation; the details confirmed by R181; decision 8, 5.1, 5.3, 5.5, 5.6, 6.1, 6.4, 8.2, 8.3, sections 10 and 11).
9. **Member numbering:** 4a, 4b, 4c (R178; 6.2).
10. **Medleys in the printed songbook:** members flow on without page breaks, with the transition note between them (R178; section 13, P9-1 section 9).
11. **Gig Log presentation:** members nested under the medley (R178; 8.3).
12. **`x` on a member:** skips the current member only (R178; 9.5).
13. **Rehearse this from a member's Arrange sheet:** plays that member (R178; section 12).
14. **Non-adjacent rows:** a medley may be made from non-adjacent rows (R178; 5.6, 6.1).

No questions remain open.
