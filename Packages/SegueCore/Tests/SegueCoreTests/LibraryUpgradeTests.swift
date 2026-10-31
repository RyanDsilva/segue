import ChordPro
import Editing
import Foundation
import Library
import Support
import Testing

/// The first open with this build (P8-8 sections 5.7, 5.8, R173): `{duration}` is ignored
/// and stays byte-for-byte, the one-time cleanup removes only those lines, and an old
/// `timings/` folder goes to the Trash once (never deleted).
struct LibraryUpgradeTests {
    static let song = """
    {title: Kept}
    {duration: 4:05}
    {tempo: 96}
    [G]Words {duration: inline} here
    {Duration: 3:00}
    """

    @Test
    func `a duration line is ignored: no field, no diagnostic, and other edits keep it`() throws {
        let (document, diagnostics) = ChordProParser.parse(Self.song)
        #expect(document.metadata.tempo == 96)
        #expect(document.metadata.extra["duration"] == nil)
        let snapshot = SourceSnapshot(text: Self.song)
        #expect(!diagnostics.contains { $0.message.contains("uration") })
        let change = try DocumentEditor.change(
            for: .setDirective(name: "key", value: "G"),
            in: snapshot,
        )
        let edited = Self.song.applying(change.edits)
        #expect(edited.contains("{duration: 4:05}\n"))
        #expect(edited.contains("{Duration: 3:00}"))
    }

    @Test
    func `the cleanup removes every duration line and nothing else, as one edit`() throws {
        let change = try DocumentEditor.change(
            for: .removeDirectives(name: "duration"),
            in: SourceSnapshot(text: Self.song),
        )
        #expect(change.actionName == "Remove Duration Lines")
        #expect(Self.song.applying(change.edits) == """
        {title: Kept}
        {tempo: 96}
        [G]Words {duration: inline} here
        """)
    }

    @Test
    func `the offer counts editable songs with a duration line and is made once`() throws {
        let lib = try TestLibrary()
        func record(_ source: String, _ byte: UInt8, readOnly: Bool = false) throws
            -> SongRecord
        {
            var record = try TestSongs.record(
                source: source,
                id: SongID(ULID(milliseconds: 1, randomness: Array(repeating: byte, count: 10))),
            )
            record.readOnly = readOnly ? .newerSchema(found: 99, supported: 4) : nil
            return record
        }
        let records = try [
            record(Self.song, 1),
            record("{title: None}\n[G]la\n", 2),
            record("{title: Locked}\n{duration: 1:00}\n", 3, readOnly: true),
            record("{title: Spaced}\n  { duration : 2:00 }\n", 4),
        ]
        #expect(LibraryUpgrade.songsWithDurationLines(records) == [records[0].id, records[3].id])

        #expect(!LibraryUpgrade.state(root: lib.root, fileSystem: lib.fileSystem)
            .durationCleanupOffered)
        try LibraryUpgrade.save(
            LibraryUpgradeState(durationCleanupOffered: true),
            root: lib.root,
            fileSystem: lib.fileSystem,
        )
        #expect(LibraryUpgrade.state(root: lib.root, fileSystem: lib.fileSystem)
            .durationCleanupOffered)
        #expect(lib.exists(".segue/upgrades.json"))
    }

    @Test
    func `an old timings folder moves to the Trash once; a failed move leaves it`() throws {
        let lib = try TestLibrary()
        // Nothing to move: no note.
        #expect(!LibraryUpgrade.moveTimingsToTrash(
            root: lib.root,
            fileSystem: lib.fileSystem,
            trash: { _ = try lib.fileSystem.trashItem(at: $0) },
        ))
        try lib.write("{}", to: "timings/01JOLD.rehearsal.json")

        struct NoTrash: Error {}
        #expect(!LibraryUpgrade.moveTimingsToTrash(
            root: lib.root,
            fileSystem: lib.fileSystem,
            trash: { _ in throw NoTrash() },
        ))
        #expect(try lib.read("timings/01JOLD.rehearsal.json") == "{}")

        #expect(LibraryUpgrade.moveTimingsToTrash(
            root: lib.root,
            fileSystem: lib.fileSystem,
            trash: { _ = try lib.fileSystem.trashItem(at: $0) },
        ))
        #expect(!lib.exists("timings"))
        #expect(lib.trashedNames().contains("timings"))
        // Moved: the next open finds nothing and shows no note.
        #expect(!LibraryUpgrade.moveTimingsToTrash(
            root: lib.root,
            fileSystem: lib.fileSystem,
            trash: { _ = try lib.fileSystem.trashItem(at: $0) },
        ))
    }
}
