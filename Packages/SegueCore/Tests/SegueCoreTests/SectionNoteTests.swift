import ChordPro
import Editing
import Foundation
import Library
import Testing

/// Section notes (P3-13, R87, R106) over a real temp library: `{comment}` lines and sidecar
/// cues read as one grouped list; the "Show on stage only" toggle moves a note between the
/// `.cho` and the sidecar and back with the lyrics byte-identical; orphaned cues stay
/// listed; every write goes through the real store and survives a relaunch.
struct SectionNoteTests {
    static let song = """
    {title: Kettle On}
    {comment: Capo 2, strum DDU}
    [G]Loose intro line

    {start_of_verse: Verse 1}
    [G]Morning light on the [C]window
    {comment: Soft, fingers only}
    [D]Kettle singing low
    {end_of_verse}

    {start_of_chorus}
    {ci: Big}
    [C]Put the kettle [G]on
    {end_of_chorus}

    {start_of_verse: Verse 2}
    [G]Evening falls on the [C]garden
    {end_of_verse}

    {chorus}

    """

    static let cues = [
        SongCue(section: "Chorus", text: "Watch Ravi for the stop"),
        SongCue(section: "verse 2", text: "Half time"),
        SongCue(section: "Bridge", text: "Key change"),
        SongCue(section: "Chorus", occurrence: 2, text: "Last time, slow down"),
    ]

    private static func lyrics(_ source: String) -> [String] {
        ChordProParser.parse(source).0.plainLyrics.components(separatedBy: "\n")
    }

    private struct Fixture {
        let lib: TestLibrary
        let store: LibraryStore
        let record: SongRecord
    }

    private func store(cues: [SongCue] = Self.cues) async throws -> Fixture {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.song)
        let record = try await store.updateSectionNotes(id: song.id, source: nil, cues: cues)
        return Fixture(lib: lib, store: store, record: record)
    }

    /// Plans `edit` on `record` and writes it through the store, as the library pane does.
    @discardableResult
    private func apply(
        _ edit: SectionNoteEdit,
        to record: SongRecord,
        in store: LibraryStore,
    ) async throws -> SongRecord {
        let change = try SectionNotes.change(
            edit,
            in: SourceSnapshot(text: record.source),
            cues: record.sidecar.cues,
        )
        return try await store.updateSectionNotes(
            id: record.id,
            source: change.source.map { record.source.applying($0.edits) },
            cues: change.cues,
            basedOn: record.revision,
        )
    }

    private static func notes(_ record: SongRecord) -> SectionNotes {
        SectionNotes(document: record.document, cues: record.sidecar.cues)
    }

    @Test
    func `the merged list holds every comment and cue grouped by section in song order`(
    ) async throws {
        let fixture = try await store()
        let (lib, record) = (fixture.lib, fixture.record)
        defer { withExtendedLifetime(lib) {} }
        let notes = Self.notes(record)

        #expect(notes.groups.map(\.title) == [
            "Before the first section", "Verse 1", "Chorus", "Verse 2", "Bridge",
        ])
        #expect(notes.groups.map(\.kind) == [.loose, .section, .section, .section, .orphaned])
        #expect(notes.groups.map { $0.notes.map(\.text) } == [
            ["Capo 2, strum DDU"],
            ["Soft, fingers only"],
            ["Big", "Watch Ravi for the stop", "Last time, slow down"],
            ["Half time"],
            ["Key change"],
        ])
        #expect(notes.all.map(\.isStageOnly) == [false, false, false, true, true, true, true])
        // The chorus is written once and repeated once: two occurrences.
        let chorus = try #require(notes.groups.first { $0.title == "Chorus" })
        #expect(chorus.occurrences == 2)
        #expect(chorus.acceptsChartNotes && chorus.acceptsStageNotes)
        #expect(notes.groups[0].acceptsStageNotes == false)
        // Badges: Verse 1 has its comment; the written chorus its comment plus the every-time
        // cue; Verse 2 its cue.
        let headers = notes.groups.flatMap(\.headers)
        #expect(headers.map { notes.count(forSectionAt: $0) } == [1, 2, 1])
    }

    @Test
    func `stage only moves a chart note to the sidecar and back with the lyrics untouched`(
    ) async throws {
        let fixture = try await store()
        let (lib, store, record) = (fixture.lib, fixture.store, fixture.record)
        let verseNote = try #require(Self.notes(record).groups[1].notes.first)
        #expect(verseNote.sources == [.chart(BlockPath(block: 4, item: 1))])

        let staged = try await apply(.setStageOnly(verseNote.id, true), to: record, in: store)
        #expect(!staged.source.contains("Soft, fingers only"))
        #expect(staged.source == Self.song.replacingOccurrences(
            of: "{comment: Soft, fingers only}\n",
            with: "",
        ))
        #expect(staged.sidecar.cues.contents.last == "Verse 1|*|Soft, fingers only")
        #expect(Self.lyrics(staged.source) == Self.lyrics(Self.song))
        let moved = try #require(Self.notes(staged).groups[1].notes.first)
        #expect(moved.isStageOnly && moved.text == "Soft, fingers only")

        let back = try await apply(.setStageOnly(moved.id, false), to: staged, in: store)
        #expect(back.sidecar.cues.contents == Self.cues.contents)
        #expect(back.sidecar.cues.map(\.id) == Self.cues.map(\.id))
        #expect(Self.lyrics(back.source) == Self.lyrics(Self.song))
        // The note returns as the first line inside its section.
        #expect(back.source
            .contains("{start_of_verse: Verse 1}\n{comment: Soft, fingers only}\n[G]Morning"))

        // Both files survive a relaunch.
        let relaunched = try await lib.openStore()
        let reloaded = try #require(try await relaunched.song(id: record.id))
        #expect(reloaded.source == back.source)
        #expect(reloaded.sidecar.cues == back.sidecar.cues)
    }

    @Test
    func `a note on a repeated label keeps its occurrence across the toggle`() throws {
        let source = """
        {start_of_chorus}
        [C]First chorus
        {end_of_chorus}

        {start_of_chorus}
        {comment: Second time only}
        [C]Second chorus
        {end_of_chorus}

        """
        let snapshot = SourceSnapshot(text: source)
        let notes = SectionNotes(document: snapshot.document, cues: [])
        let note = try #require(notes.all.first)
        #expect(note.occurrence == 2)
        let change = try SectionNotes.change(
            .setStageOnly(note.id, true),
            in: snapshot,
            cues: [],
        )
        #expect(change.cues.contents == ["Chorus|2|Second time only"])
        #expect(change.resultID == .stage(change.cues[0].id))
        let staged = try source.applying(#require(change.source).edits)
        #expect(staged == source.replacingOccurrences(
            of: "{comment: Second time only}\n",
            with: "",
        ))

        let back = try SectionNotes.change(
            .setStageOnly(.stage(change.cues[0].id), false),
            in: SourceSnapshot(text: staged),
            cues: change.cues,
        )
        #expect(back.cues.isEmpty)
        #expect(try staged.applying(#require(back.source).edits) == source)
    }

    @Test
    func `a stage note on a chorus repeat becomes a chart note in the chorus it repeats`(
    ) async throws {
        let fixture = try await store()
        let (lib, store, record) = (fixture.lib, fixture.store, fixture.record)
        defer { withExtendedLifetime(lib) {} }
        let last = try #require(Self.notes(record).all.first { $0.text == "Last time, slow down" })
        let charted = try await apply(.setStageOnly(last.id, false), to: record, in: store)
        // After the chorus's existing note (R144: appended, never inserted above).
        #expect(charted.source
            .contains("{start_of_chorus}\n{ci: Big}\n{comment: Last time, slow down}\n[C]Put"))
        #expect(!charted.sidecar.cues.contains { $0.text == "Last time, slow down" })
        #expect(Self.lyrics(charted.source) == Self.lyrics(Self.song))
    }

    @Test
    func `orphaned cues stay listed and cannot become chart notes`() async throws {
        let fixture = try await store()
        let (lib, store, record) = (fixture.lib, fixture.store, fixture.record)
        defer { withExtendedLifetime(lib) {} }
        let notes = Self.notes(record)
        let bridge = try #require(notes.groups.last)
        #expect(bridge.kind == .orphaned && bridge.notes.map(\.text) == ["Key change"])
        let note = try #require(bridge.notes.first)
        #expect(throws: SectionNoteError.noAnchor) {
            try SectionNotes.change(
                .setStageOnly(note.id, false),
                in: SourceSnapshot(text: record.source),
                cues: record.sidecar.cues,
            )
        }
        // Re-pinning it to a section that exists brings it back under that section.
        let pinned = try await apply(
            .pin(note.id, section: "Verse 1", occurrence: nil),
            to: record,
            in: store,
        )
        let regrouped = Self.notes(pinned)
        #expect(regrouped.groups.map(\.title).contains("Bridge") == false)
        #expect(regrouped.groups[1].notes.map(\.text) == ["Soft, fingers only", "Key change"])
    }

    @Test
    func `loose chart notes cannot be stage only`() throws {
        let snapshot = SourceSnapshot(text: Self.song)
        let notes = SectionNotes(document: snapshot.document, cues: [])
        let loose = try #require(notes.groups.first?.notes.first)
        #expect(throws: SectionNoteError.noAnchor) {
            try SectionNotes.change(.setStageOnly(loose.id, true), in: snapshot, cues: [])
        }
    }

    @Test
    func `add, edit and delete write only the note's own line or cue`() async throws {
        let fixture = try await store(cues: [])
        let (lib, store, record) = (fixture.lib, fixture.store, fixture.record)
        defer { withExtendedLifetime(lib) {} }
        let chorus = try #require(Self.notes(record).groups.first { $0.title == "Chorus" })

        let added = try await apply(
            .add(group: chorus.id, text: "  Everyone\nsings ", stageOnly: false, placement: nil),
            to: record,
            in: store,
        )
        #expect(added.source == Self.song.replacingOccurrences(
            of: "{ci: Big}\n",
            with: "{ci: Big}\n{comment: Everyone sings}\n",
        ))
        let staged = try await apply(
            .add(group: chorus.id, text: "Lights down", stageOnly: true, placement: nil),
            to: added,
            in: store,
        )
        #expect(staged.source == added.source)
        #expect(staged.sidecar.cues.contents == ["Chorus|*|Lights down"])

        let ci = try #require(Self.notes(staged).all.first { $0.text == "Big" })
        let edited = try await apply(.setText(ci.id, "Bigger"), to: staged, in: store)
        // The comment keeps its own spelling (`{ci}`).
        #expect(edited.source.contains("{ci: Bigger}\n"))
        let cue = try #require(Self.notes(edited).all.first { $0.isStageOnly })
        let renamed = try await apply(.setText(cue.id, "Lights up"), to: edited, in: store)
        #expect(renamed.sidecar.cues.map(\.text) == ["Lights up"])

        let first = try #require(Self.notes(renamed).all.first { $0.text == "Everyone sings" })
        let deleted = try await apply(.delete(first.id), to: renamed, in: store)
        let gone = try #require(Self.notes(deleted).all.first { $0.isStageOnly })
        let cleared = try await apply(.delete(gone.id), to: deleted, in: store)
        #expect(cleared.sidecar.cues.isEmpty)
        #expect(cleared.source == Self.song.replacingOccurrences(
            of: "{ci: Big}",
            with: "{ci: Bigger}",
        ))
    }

    @Test(arguments: ["", "   ", "\n\n"])
    func `text that is not one comment is refused`(text: String) throws {
        let snapshot = SourceSnapshot(text: Self.song)
        let notes = SectionNotes(document: snapshot.document, cues: [])
        let chorus = try #require(notes.groups.first { $0.title == "Chorus" })
        #expect(throws: SectionNoteError.invalidText) {
            try SectionNotes.change(
                .add(group: chorus.id, text: text, stageOnly: false, placement: nil),
                in: snapshot,
                cues: [],
            )
        }
    }
}
