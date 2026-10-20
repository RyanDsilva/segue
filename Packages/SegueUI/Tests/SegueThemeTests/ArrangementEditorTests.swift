import Foundation
import Library
@testable import SegueUI
import Setlists
import Shows
import Support
import Testing

/// Per-slot arrangements on a real app session (P3-16, R122, R123): the sheet's rows and
/// edits (each one undo step, the `.cho` never touched), the slot mark, the missing-lengths
/// row of an arranged slot, the gig log line and Time it for a slot.
@MainActor
struct ArrangementEditorTests {
    private static let fridayID = "01JC0000000000000000000F01"
    private static let songID = "01JC0000000000000000000A00"
    private static let itemID = "01JC0000000000000000000T00"
    private static let song = """
    {title: Soundcheck}
    {duration: 3:20}

    {start_of_verse: Verse 1}
    [G]First verse words
    {end_of_verse}

    {start_of_chorus}
    [C]Chorus words here
    {end_of_chorus}

    {start_of_verse: Verse 2}
    [G]Second verse words
    {end_of_verse}

    {chorus}

    {start_of_bridge}
    [Em]Bridge words
    {end_of_bridge}

    {chorus}
    """

    private struct Fixture {
        var env: TestEnvironment
        var session: LibrarySession
        var manager: UndoManager
        var friday: SetlistID
        var item: SetlistItemID
    }

    private static func open() async throws -> Fixture {
        let env = try TestEnvironment()
        for folder in ["songs", "setlists"] {
            try FileManager.default.createDirectory(
                at: env.libraryURL.appending(path: folder, directoryHint: .isDirectory),
                withIntermediateDirectories: true,
            )
        }
        try env.write(song, to: "songs/soundcheck.cho")
        try env.write(
            #"{"schemaVersion": 3, "id": "\#(songID)", "#
                + #""createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-01T10:00:00Z"}"#,
            to: "songs/soundcheck.segue.json",
        )
        try env.write(
            #"{"schemaVersion": 4, "id": "\#(fridayID)", "name": "Friday", "#
                + #""entries": [{"itemId": "\#(itemID)", "songId": "\#(songID)"}]}"#,
            to: "setlists/friday.setlist.json",
        )
        let app = try await env.openApp()
        let session = try #require(app.session)
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.undoManager = manager
        return try Fixture(
            env: env,
            session: session,
            manager: manager,
            friday: SetlistID(#require(ULID(string: fridayID))),
            item: SetlistItemID(#require(ULID(string: itemID))),
        )
    }

    private func entry(_ fix: Fixture) -> SetlistEntry? {
        fix.session.setlists.setlist(fix.friday)?.entry(fix.item)
    }

    private func units(_ fix: Fixture) throws -> [SongSectionUnit] {
        let songID = try SongID(#require(ULID(string: Self.songID)))
        let record = try #require(fix.session.library.song(id: songID))
        return SongSections.units(of: record.document)
    }

    /// Applies one sheet edit to the saved arrangement, as the sheet does.
    private func edit(
        _ fix: Fixture,
        _ name: String,
        _ change: (inout ArrangementDraft) -> Void,
    ) async throws {
        var draft = try ArrangementDraft(arrangement: entry(fix)?.arrangement, units: units(fix))
        change(&draft)
        fix.manager.beginUndoGrouping()
        await fix.session.setlists.setArrangement(
            draft.arrangement,
            of: fix.item,
            in: fix.friday,
            actionName: name,
        )
        fix.manager.endUndoGrouping()
    }

    @Test
    func `skip, repeat, play again and reorder save as one undo step each`() async throws {
        let fix = try await Self.open()
        let cho = try fix.env.read("songs/soundcheck.cho")
        let draft = try ArrangementDraft(arrangement: nil, units: units(fix))
        #expect(!draft.isCustom)
        #expect(draft.rows.map(\.unit.name) == [
            "Verse 1", "Chorus 1st", "Verse 2", "Chorus 2nd", "Bridge", "Chorus 3rd",
        ])

        // Skip the Bridge: the first edit creates the arrangement.
        try await edit(fix, "Skip Section") { $0.toggle(4) }
        #expect(fix.manager.undoActionName == "Skip Section")
        // Last chorus twice.
        try await edit(fix, "Change Play Count") { $0.setPlays(5, 2) }
        // Play Verse 1 again at the end.
        try await edit(fix, "Play Again Later") { draft in
            draft.playAgainLater(0)
            draft.move(fromOffsets: IndexSet(integer: 1), toOffset: draft.rows.count)
        }
        let saved = try #require(entry(fix)?.arrangement)
        #expect(saved.playedSummary
            == "Verse 1, Chorus, Verse 2, Chorus 2nd, Chorus 3rd x2, Verse 1")
        #expect(try ArrangementDraft.markText(saved, units: units(fix))
            == "Custom · 5 of 6 sections · Chorus 3rd x2")
        let json = try fix.env.read("setlists/friday.setlist.json")
        #expect(json.contains("\"schemaVersion\" : 5"))
        #expect(json.contains("\"arrangement\""))
        // The song file is never changed.
        #expect(try fix.env.read("songs/soundcheck.cho") == cho)

        // At least one section plays: the last played row cannot be skipped.
        var lone = try ArrangementDraft(
            arrangement: SlotArrangement(steps: [
                ArrangementStep(
                    anchor: units(fix)[0].anchor,
                    fingerprint: units(fix)[0].fingerprint,
                ),
            ]),
            units: units(fix),
        )
        let toggled = lone.toggle(0)
        #expect(!toggled)

        fix.manager.undo()
        try await fix.env.waitFor {
            let summary = entry(fix)?.arrangement?.playedSummary
            return summary == "Verse 1, Chorus, Verse 2, Chorus 2nd, Chorus 3rd x2" ? true : nil
        }
        // Reset to Full Song removes the override.
        fix.manager.beginUndoGrouping()
        await fix.session.setlists.setArrangement(
            nil,
            of: fix.item,
            in: fix.friday,
            actionName: "Reset to Full Song",
        )
        fix.manager.endUndoGrouping()
        #expect(entry(fix)?.arrangement == nil)
        #expect(fix.manager.undoActionName == "Reset to Full Song")
        #expect(try !fix.env.read("setlists/friday.setlist.json").contains("\"arrangement\""))
    }

    @Test
    func `an arranged slot without its own length is unknown and listed, then filled`(
    ) async throws {
        let fix = try await Self.open()
        try await edit(fix, "Skip Section") { $0.toggle(4) }
        let library = fix.session.library
        var setlist = try #require(fix.session.setlists.setlist(fix.friday))
        // The song has {duration: 3:20}, but the slot plays something else: unknown.
        let rows = MissingLengthsList.rows(setlist, within: nil, library: library)
        #expect(rows.map(\.isArranged) == [true])
        var timing = SetlistTiming(setlist: setlist, songs: library.song(id:), defaultChangeover: 0)
        #expect(timing.unknownCount == 1)

        try await edit(fix, "Set Slot Length") { $0.length = 160 }
        setlist = try #require(fix.session.setlists.setlist(fix.friday))
        timing = SetlistTiming(setlist: setlist, songs: library.song(id:), defaultChangeover: 0)
        #expect(timing.totalText == "2:40")
        #expect(MissingLengthsList.rows(setlist, within: nil, library: library).isEmpty)
        // The song keeps its own length.
        #expect(try fix.env.read("songs/soundcheck.cho").contains("{duration: 3:20}"))
    }

    @Test
    func `a changed song makes the arrangement out of date and Update clears it`() async throws {
        let fix = try await Self.open()
        try await edit(fix, "Skip Section") { $0.toggle(4) }
        try fix.env.write(
            Self.song.replacingOccurrences(of: "Verse 2}", with: "Verse Two}"),
            to: "songs/soundcheck.cho",
        )
        await fix.session.library.refresh()
        let saved = try #require(entry(fix)?.arrangement)
        let units = try units(fix)
        #expect(ArrangementResolver.resolve(saved, units: units).isOutOfDate)

        let draft = ArrangementDraft(arrangement: saved, units: units)
        #expect(draft.missingNames == "Verse 2")
        // The renamed section shows as new (unticked), the rest keep their choices.
        #expect(draft.rows.filter(\.isNew).map(\.unit.name) == ["Verse Two"])
        #expect(draft.rows.first { $0.unit.title == "Bridge" }?.plays == 0)

        try await edit(fix, "Update Arrangement") { _ in }
        let updated = try #require(entry(fix)?.arrangement)
        #expect(!ArrangementResolver.resolve(updated, units: units).isOutOfDate)
    }

    @Test
    func `the gig log says what an arranged slot played`() {
        let anchor = SectionAnchor.section(SectionRef(label: "Chorus", occurrence: 3))
        var item = ShowItem(
            itemId: SetlistItemID(ULID(
                milliseconds: 1,
                randomness: Array(repeating: 1, count: 10),
            )),
            songId: SongID(ULID(milliseconds: 1, randomness: Array(repeating: 2, count: 10))),
            title: "Soundcheck",
            origin: .setlist,
            arrangement: SlotArrangement(steps: [
                ArrangementStep(anchor: .loose(after: nil, block: 1)),
                ArrangementStep(anchor: anchor, plays: 2),
            ]),
        )
        item.arrangementState = .applied
        #expect(GigPlayedListLines.arrangementLine(item)
            == "Custom arrangement: Lead-in, Chorus 3rd x2")
        item.arrangementState = .outOfDate
        #expect(GigPlayedListLines.arrangementLine(item) == "Full song (arrangement out of date)")
    }

    @Test
    func `time it runs for one slot at a time, apart from songs`() {
        let clock = ManualClock()
        let timeIt = TimeItModel(clock: clock)
        let slot = TimeItTarget.slot(SetlistItemID(ULID(
            milliseconds: 1,
            randomness: Array(repeating: 3, count: 10),
        )))
        let song = SongID(ULID(milliseconds: 1, randomness: Array(repeating: 4, count: 10)))
        #expect(timeIt.start(slot))
        #expect(!timeIt.start(song))
        #expect(timeIt.isTimingOther(than: song))
        clock.advance(by: 95)
        #expect(timeIt.stop(slot) == 95)
        #expect(timeIt.start(song))
    }
}
