import Foundation
import Library
@testable import SegueUI
import Setlists
import Support
import Testing

/// Set building on a real app session (P3-12, R84-R88): Pick's tick order, ⌘A, ticks into
/// a selected part, Arrange's keyboard moves and Insert Break (each one undo step), Library
/// multi-select's Add to Setlist, and the missing-lengths list with its inline fill.
@MainActor
struct SetBuilderPickTests {
    private static let fridayID = "01JC0000000000000000000F01"
    private struct Seed {
        var slug: String
        var title: String
        var length: String?
    }

    /// The seeded songs, in library order.
    private static let songs = [
        Seed(slug: "ferry-lights", title: "Ferry Lights", length: "4:40"),
        Seed(slug: "harbour-lights", title: "Harbour Lights", length: nil),
        Seed(slug: "kettle-on", title: "Kettle On", length: "3:05"),
        Seed(slug: "paper-boats", title: "Paper Boats", length: "3:12"),
        Seed(slug: "pyaar-ki-raah", title: "Pyaar Ki Raah", length: nil),
    ]

    private static func id(_ index: Int) -> SongID {
        SongID(ULID(
            string: "01JC0000000000000000000A0\(index)",
        )!) // swiftlint:disable:this force_unwrapping
    }

    private struct Fixture {
        var env: TestEnvironment
        var session: LibrarySession
        var manager: UndoManager
        var friday: SetlistID
    }

    private static func open(entries: [Int] = []) async throws -> Fixture {
        let env = try TestEnvironment()
        try FileManager.default.createDirectory(
            at: env.libraryURL.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: env.libraryURL.appending(path: "setlists", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        for (index, song) in songs.enumerated() {
            let length = song.length.map { "{duration: \($0)}\n" } ?? ""
            try env.write(
                "{title: \(song.title)}\n\(length)[G]La la\n",
                to: "songs/\(song.slug).cho",
            )
            try env.write(
                #"{"schemaVersion": 3, "id": "\#(id(index))", "#
                    + #""createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-01T10:00:00Z"}"#,
                to: "songs/\(song.slug).segue.json",
            )
        }
        let rows = entries.enumerated().map { offset, song in
            #"{"itemId": "01JC0000000000000000000T0\#(offset)", "songId": "\#(id(song))"}"#
        }
        try env.write(
            #"{"schemaVersion": 3, "id": "\#(fridayID)", "name": "Friday", "#
                + #""entries": [\#(rows.joined(separator: ", "))]}"#,
            to: "setlists/friday.setlist.json",
        )
        let app = try await env.openApp()
        let session = try #require(app.session)
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.undoManager = manager
        let friday = try SetlistID(#require(ULID(string: fridayID)))
        return Fixture(env: env, session: session, manager: manager, friday: friday)
    }

    private func step(_ manager: UndoManager, _ action: () async -> Void) async {
        manager.beginUndoGrouping()
        await action()
        manager.endUndoGrouping()
    }

    private func titles(_ fix: Fixture) -> [String] {
        let setlist = fix.session.setlists.setlist(fix.friday)
        return setlist?.entries.map { entry in
            if let info = entry.breakInfo {
                return "[\(info.label)]"
            }
            return entry.songId.flatMap(fix.session.library.song(id:))
                .map(SongSummary.title) ?? "?"
        } ?? []
    }

    @Test
    func `ticks append in tick order, untick removes, and ⌘A adds only what is missing`(
    ) async throws {
        let fix = try await Self.open()
        let setlists = fix.session.setlists

        await step(fix.manager) { await setlists.toggle(Self.id(3), in: fix.friday) }
        await step(fix.manager) { await setlists.toggle(Self.id(0), in: fix.friday) }
        await step(fix.manager) { await setlists.toggle(Self.id(2), in: fix.friday) }
        #expect(titles(fix) == ["Paper Boats", "Ferry Lights", "Kettle On"])

        await step(fix.manager) { await setlists.toggle(Self.id(0), in: fix.friday) }
        #expect(titles(fix) == ["Paper Boats", "Kettle On"])

        var added = 0
        await step(fix.manager) {
            added = await setlists.tickAll((0 ..< 5).map(Self.id), in: fix.friday)
        }
        #expect(added == 3)
        #expect(titles(fix) == [
            "Paper Boats", "Kettle On", "Ferry Lights", "Harbour Lights", "Pyaar Ki Raah",
        ])
        // One ⌘A is one undo step.
        #expect(fix.manager.undoActionName == "Add Songs")
        await step(fix.manager) {
            added = await setlists.tickAll((0 ..< 5).map(Self.id), in: fix.friday)
        }
        #expect(added == 0)
    }

    @Test
    func `arrange moves the selected block and breaks split the set`() async throws {
        let fix = try await Self.open(entries: [0, 1, 2, 3])
        let setlists = fix.session.setlists
        let ids = try #require(setlists.setlist(fix.friday)).entries.map(\.itemId)

        // Rows 3 and 4 selected (⇧-click), ⌥↑ twice.
        setlists.arrangeSelection.select(ids[2])
        setlists.arrangeSelection.extend(to: ids[3], in: ids)
        #expect(setlists.canMoveSelection(in: fix.friday, by: -1))
        await step(fix.manager) { await setlists.moveSelection(in: fix.friday, by: -1) }
        await step(fix.manager) { await setlists.moveSelection(in: fix.friday, by: -1) }
        #expect(titles(fix) == ["Kettle On", "Paper Boats", "Ferry Lights", "Harbour Lights"])
        #expect(!setlists.canMoveSelection(in: fix.friday, by: -1))

        // Insert Break after the selected block: "Set 2", selected afterwards.
        await step(fix.manager) { await setlists.insertBreak(in: fix.friday) }
        #expect(titles(fix) == [
            "Kettle On", "Paper Boats", "[Set 2]", "Ferry Lights", "Harbour Lights",
        ])
        #expect(fix.manager.undoActionName == "Insert Break")

        // With the break selected, a Pick tick lands at the end of its part.
        let breakID = try #require(setlists.arrangeSelection.focus)
        let insertedBreak = try #require(setlists.setlist(fix.friday)?.entry(breakID))
        #expect(insertedBreak.isBreak)
        // "Set 3" right after "Set 2".
        await step(fix.manager) { await setlists.insertBreak(in: fix.friday) }
        setlists.arrangeSelection.select(breakID)
        await step(fix.manager) { await setlists.toggle(Self.id(4), in: fix.friday) }
        #expect(titles(fix) == [
            "Kettle On", "Paper Boats", "[Set 2]", "Pyaar Ki Raah", "[Set 3]", "Ferry Lights",
            "Harbour Lights",
        ])

        fix.manager.undo()
        try await fix.env.waitFor {
            titles(fix).contains("Pyaar Ki Raah") ? nil : true
        }
    }

    @Test
    func `add to setlist with several songs skips the ones already in and says so`() async throws {
        let fix = try await Self.open(entries: [1])
        var result = (added: 0, skipped: 0)
        await step(fix.manager) {
            result = await fix.session.setlists.addSongs(
                [Self.id(0), Self.id(1), Self.id(3)],
                to: fix.friday,
            )
        }

        #expect(result.added == 2)
        #expect(result.skipped == 1)
        #expect(titles(fix) == ["Harbour Lights", "Ferry Lights", "Paper Boats"])
        #expect(LibrarySession.addedMessage(result, setlistName: "Friday")
            == "Added 2 songs to Friday, 1 was already in the set.")
        #expect(LibrarySession.addedMessage((7, 2), setlistName: "Friday")
            == "Added 7 songs to Friday, 2 were already in the set.")
    }

    @Test
    func `the missing-lengths list names exactly the songs without a length and fills them`(
    ) async throws {
        let fix = try await Self.open(entries: [0, 1, 2, 4])
        let library = fix.session.library
        let setlist = try #require(fix.session.setlists.setlist(fix.friday))

        let rows = MissingLengthsList.rows(setlist, within: nil, library: library)
        #expect(rows.map(\.title) == ["Harbour Lights", "Pyaar Ki Raah"])
        #expect(rows.map(\.place) == ["#2", "#4"])

        // The inline field writes {duration} through the song card's path: one edit.
        await step(fix.manager) { await library.editSongSource(id: Self.id(1), .setLength(245)) }
        try await fix.env.waitFor {
            MissingLengthsList.rows(setlist, within: nil, library: library).count == 1
                ? true : nil
        }
        let timing = SetlistTiming(setlist: setlist, songs: library.song(id:), defaultChangeover: 0)
        #expect(timing.totalText == "≥11:50 + 1 unknown")
        #expect(try fix.env.read("songs/harbour-lights.cho").contains("{duration: 4:05}"))
    }
}
