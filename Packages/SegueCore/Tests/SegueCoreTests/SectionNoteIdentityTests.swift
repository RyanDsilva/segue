import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Support
import Testing

/// Shared fixture for the P3-17 section note suites: Chorus #1, Verse, Chorus #2 and a
/// `{chorus}` repeat of #2, plus helpers that plan and apply edits as the hosts do.
enum NoteFix {
    static let song = """
    {title: Placement}
    {start_of_chorus}
    [C]Hold the line
    {end_of_chorus}

    {start_of_verse}
    [G]Walking home
    {end_of_verse}

    {start_of_chorus}
    [C]Hold it now
    {end_of_chorus}

    {chorus}

    """

    static func notes(_ text: String, _ cues: [SongCue] = []) -> SectionNotes {
        SectionNotes(document: SourceSnapshot(text: text).document, cues: cues)
    }

    static func chorus(_ text: String, _ cues: [SongCue] = []) throws -> SectionNoteGroup {
        try #require(notes(text, cues).groups.first { $0.title == "Chorus" })
    }

    static func lyrics(_ source: String) -> String {
        ChordProParser.parse(source).0.plainLyrics
    }

    /// Plans `edit` and applies it, as the hosts do.
    static func apply(
        _ edit: SectionNoteEdit,
        to text: String,
        cues: [SongCue] = [],
    ) throws -> Applied {
        let change = try SectionNotes.change(edit, in: SourceSnapshot(text: text), cues: cues)
        return Applied(
            text: change.source.map { text.applying($0.edits) } ?? text,
            cues: change.cues,
            change: change,
        )
    }

    /// The note the change left (`resultID`), read back from the changed song.
    static func result(
        _ applied: Applied,
    ) throws -> SectionNote {
        let id = try #require(applied.change.resultID)
        return try #require(notes(applied.text, applied.cues).note(id))
    }

    /// The text of the section block that starts at the `number`-th `{start_of_chorus}`.
    static func chorusBlock(_ number: Int, in text: String) -> String {
        let parts = text.components(separatedBy: "{start_of_chorus}\n")
        return parts[number].components(separatedBy: "{end_of_chorus}")[0]
    }
}

/// Stable note identity (P3-17, R144, R145): edits resolve their note by ID when planned,
/// chart note IDs survive edits elsewhere in their section, and placed cues re-anchor by
/// section fingerprint.
struct SectionNoteIdentityTests {
    // MARK: IDs

    @Test
    func `queued edits by ID never hit the wrong note`() throws {
        let cues = ["One", "Two", "Three"].map { SongCue(section: "Verse", text: $0) }
        // Both deletes are queued before either applies (the sheet's queue): each resolves
        // its note when it is planned.
        let first = try NoteFix.apply(.delete(.stage(cues[0].id)), to: NoteFix.song, cues: cues)
        let second = try NoteFix.apply(
            .delete(.stage(cues[2].id)),
            to: first.text,
            cues: first.cues,
        )
        #expect(second.cues.map(\.text) == ["Two"])
        #expect(throws: SectionNoteError.notFound) {
            try SectionNotes.change(
                .delete(.stage(cues[2].id)),
                in: SourceSnapshot(text: NoteFix.song),
                cues: second.cues,
            )
        }

        // A chart note keeps its ID when a note is added before it in its section.
        let text = """
        {start_of_verse}
        [G]Line one
        {comment: Watch the drummer}
        {end_of_verse}

        """
        let verse = try #require(NoteFix.notes(text).groups.first)
        let target = try #require(verse.notes.first).id
        let added = try NoteFix.apply(
            .add(group: verse.id, text: "Soft", stageOnly: false, placement: nil),
            to: text,
        )
        #expect(NoteFix.notes(added.text).all.map(\.text) == ["Soft", "Watch the drummer"])
        let edited = try NoteFix.apply(.setText(target, "Watch the bass"), to: added.text)
        #expect(edited.text.contains("{comment: Soft}\n[G]Line one\n{comment: Watch the bass}"))
        // The result ID follows the new text, so the sheet keeps the row.
        let note = try NoteFix.result(edited)
        #expect(note.text == "Watch the bass")
    }

    // MARK: Fingerprints (R145 question 5)

    @Test
    func `a placed cue re-anchors when an earlier section shifts its occurrence`() throws {
        let chorus = try NoteFix.chorus(NoteFix.song)
        let placed = try NoteFix.apply(
            .add(group: chorus.id, text: "Watch Ravi", stageOnly: true, placement: .instance(2)),
            to: NoteFix.song,
        )
        #expect(placed.cues[0].fingerprint != nil)
        // A new chorus inserted before: "Hold it now" is now the third chorus.
        let shifted = NoteFix.song.replacingOccurrences(
            of: "{start_of_verse}",
            with: "{start_of_chorus}\n[C]Brand new\n{end_of_chorus}\n\n{start_of_verse}",
        )
        let note = try #require(NoteFix.notes(shifted, placed.cues).note(.stage(placed.cues[0].id)))
        #expect(note.placement == .instance(3) && !note.needsPlacementCheck)
        // Live mode follows the re-anchored occurrence.
        let sections = RenderModel(
            document: SourceSnapshot(text: shifted).document,
            options: DisplayOptions(),
        ).sections
        let third = try #require(SongSections.units(of: sections).first {
            $0.anchor == .section(SectionRef(label: "Chorus", occurrence: 3))
        })
        #expect(SectionNotes.pin(placed.cues, to: sections).pinned[third.index] == [0])
        // Any write stores the corrected occurrence.
        let written = try NoteFix.apply(
            .setText(note.id, "Watch Ravi now"),
            to: shifted,
            cues: placed.cues,
        )
        #expect(written.cues.contents == ["Chorus|3|Watch Ravi now"])

        // Lyrics edited so no chorus matches: the occurrence stays, marked for a check.
        let rewritten = NoteFix.song.replacingOccurrences(of: "Hold it now", with: "Hold it later")
        let cueID = SectionNoteID.stage(placed.cues[0].id)
        let unsure = try #require(NoteFix.notes(rewritten, placed.cues).note(cueID))
        #expect(unsure.placement == .instance(2) && unsure.needsPlacementCheck)
        // Re-placing it there confirms it.
        let confirmed = try NoteFix.apply(
            .place(unsure.id, .instance(2)),
            to: rewritten,
            cues: placed.cues,
        )
        let checked = NoteFix.notes(rewritten, confirmed.cues).note(unsure.id)
        #expect(checked?.needsPlacementCheck == false)
    }

    @Test
    func `notes and arrangements name the same section for an instance`() throws {
        let sections = RenderModel(
            document: SourceSnapshot(text: NoteFix.song).document,
            options: DisplayOptions(),
        ).sections
        let units = SongSections.units(of: sections)
        let cue = SongCue(section: "Chorus", occurrence: 2, text: "Here")
        let pinned = SectionNotes.pin([cue], to: sections).pinned
        let second = SectionAnchor.section(SectionRef(label: "Chorus", occurrence: 2))
        let unit = try #require(units.first { $0.anchor == second })
        #expect(pinned[unit.index] == [0])
        let third = SectionAnchor.section(SectionRef(label: "Chorus", occurrence: 3))
        let repeatUnit = try #require(units.first { $0.anchor == third })
        #expect(repeatUnit.isRepeat)
    }

    @Test
    func `a cue on a chorus repeat shows its callout on the written-out repeat`() {
        let model = LiveLayoutSupport.model(source: NoteFix.song)
        let cue = SongCue(section: "Chorus", occurrence: 3, text: "Last time")
        let (plan, _) = LiveLayoutSupport.plan(model, cues: [cue])
        #expect(plan.blocks.flatMap(\.cues).map(\.text) == ["Last time"])
    }
}

/// Sidecar schema 4 (P3-17): stable cue IDs, derived deterministically for files without
/// them, repaired when hand-edited, and read-only for newer files.
struct SectionNoteSidecarTests {
    @Test
    func `a version 3 sidecar migrates with stable derived cue IDs`() async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        let v3 = """
        {"schemaVersion": 3, "id": "\(id)", "tags": [],
         "cues": [{"section": "Chorus", "text": "Big"},
                  {"section": "Chorus", "occurrence": 2, "text": "Big"},
                  {"section": "Verse", "text": "Soft"}],
         "createdAt": "2025-06-01T10:00:00.000Z", "updatedAt": "2025-06-02T10:00:00.000Z"}
        """
        try lib.write(NoteFix.song, to: "songs/placement.cho")
        try lib.write(v3, to: "songs/placement.segue.json")

        let store = try await lib.openStore()
        let record = try #require(try await store.song(id: id))
        let ids = record.sidecar.cues.map(\.id)
        #expect(Set(ids).count == 3)
        #expect(!ids.contains(.unassigned))
        #expect(ids.allSatisfy { $0.ulid.milliseconds == 1_748_772_000_000 })
        // Re-reading the unsaved file (a relaunch) yields the same IDs.
        let again = try #require(try await lib.openStore().song(id: id))
        #expect(again.sidecar.cues.map(\.id) == ids)
        #expect(try lib.read("songs/placement.segue.json") == v3)

        // Saving writes schema 4 with those IDs.
        _ = try await store.updateSectionNotes(id: id, source: nil, cues: record.sidecar.cues)
        let saved = try lib.read("songs/placement.segue.json")
        #expect(saved.contains("\"schemaVersion\" : 4"))
        for cueID in ids {
            #expect(saved.contains("\"id\" : \"\(cueID)\""))
        }
        let reopened = try #require(try await lib.openStore().song(id: id))
        #expect(reopened.sidecar.cues.map(\.id) == ids)
    }

    @Test
    func `missing and duplicate cue IDs are repaired deterministically`() async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        let kept = CueID(lib.ids.next())
        let v4 = """
        {"schemaVersion": 4, "id": "\(id)", "tags": [],
         "cues": [{"id": "\(kept)", "section": "Chorus", "text": "A"},
                  {"id": "\(kept)", "section": "Chorus", "text": "B"},
                  {"id": "not-a-ulid", "section": "Verse", "text": "C"},
                  {"section": "Verse", "text": "D"}],
         "createdAt": "2025-06-01T10:00:00.000Z", "updatedAt": "2025-06-02T10:00:00.000Z"}
        """
        try lib.write(NoteFix.song, to: "songs/placement.cho")
        try lib.write(v4, to: "songs/placement.segue.json")
        let first = try #require(try await lib.openStore().song(id: id))
        let second = try #require(try await lib.openStore().song(id: id))
        let ids = first.sidecar.cues.map(\.id)
        #expect(ids[0] == kept)
        #expect(Set(ids).count == 4)
        #expect(second.sidecar.cues.map(\.id) == ids)
        #expect(first.readOnly == nil)
    }

    @Test
    func `a newer sidecar opens read-only and keeps its cues`() async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        let v5 = """
        {"schemaVersion": 5, "id": "\(id)", "tags": [],
         "cues": [{"id": "\(CueID(lib.ids.next()))", "section": "Chorus", "text": "A", "glow": 1}],
         "createdAt": "2025-06-01T10:00:00.000Z", "updatedAt": "2025-06-02T10:00:00.000Z"}
        """
        try lib.write(NoteFix.song, to: "songs/placement.cho")
        try lib.write(v5, to: "songs/placement.segue.json")
        let record = try #require(try await lib.openStore().song(id: id))
        #expect(record.readOnly == .newerSchema(found: 5, supported: 4))
        #expect(record.sidecar.cues.map(\.text) == ["A"])
    }
}

/// A planned section note change applied to the song, as the hosts apply it.
struct Applied {
    var text: String
    var cues: [SongCue]
    var change: SectionNoteChange
}

extension [SongCue] {
    /// "section|occurrence|text" per cue ("*" = every occurrence), identity and fingerprint
    /// ignored.
    var contents: [String] {
        map { "\($0.section)|\($0.occurrence.map(String.init) ?? "*")|\($0.text)" }
    }
}
