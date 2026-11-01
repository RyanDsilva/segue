import AppKit
import Foundation
import Library
@testable import SegueUI
import Setlists
import Support
import SwiftUI
import Testing

/// Medleys in the setlist builder on a real app session (P9-3 6.1-6.5): Make Medley from
/// non-adjacent rows, member edits, transitions and renames as one undo step each, Pick
/// ticks around a medley, the row order the keyboard walks, the no-time list, and the group
/// card rendered light and dark into `.build/screenshots/p9-3/` for review.
@MainActor
struct MedleyBuilderTests {
    private static let fridayID = "01JC0000000000000000000F01"
    private struct Seed {
        var slug: String
        var title: String
        var key: String
        var tempo: Int?
        var capo = 0
    }

    private static let songs = [
        Seed(slug: "kettle-on", title: "Kettle On, Lights Low", key: "G", tempo: 104, capo: 3),
        Seed(slug: "harbour-lights", title: "Harbour Lights", key: "G", tempo: 96, capo: 2),
        Seed(slug: "kesariya", title: "Kesariya", key: "G", tempo: 92),
        Seed(slug: "kitaabon", title: "Kitaabon Wali Gali", key: "Am", tempo: 84),
        Seed(slug: "tum-hi-ho", title: "Tum Hi Ho", key: "A", tempo: 120, capo: 2),
        Seed(slug: "channa-mereya", title: "Channa Mereya", key: "D", tempo: nil),
        Seed(slug: "saltwater", title: "Saltwater Telegraph", key: "Am", tempo: 110),
    ]

    private static func id(_ index: Int) -> SongID {
        SongID(ULID(
            string: "01JC0000000000000000000A0\(index)",
        )!) // swiftlint:disable:this force_unwrapping
    }

    @MainActor
    private struct Fixture {
        var env: TestEnvironment
        var session: LibrarySession
        var manager: UndoManager
        var friday: SetlistID

        var setlists: SetlistsViewModel {
            session.setlists
        }

        var setlist: Setlist? {
            setlists.setlist(friday)
        }

        func item(_ position: Int) throws -> SetlistItemID {
            try #require(setlist).entries[position].itemId
        }

        func titles() -> [String] {
            setlist?.entries.map { entry in
                if let medley = entry.medley {
                    let members = medley.members.map {
                        session.library.song(id: $0.songId).map(SongSummary.title) ?? "?"
                    }
                    return "{\(members.joined(separator: " / "))}"
                }
                return entry.songId.flatMap(session.library.song(id:))
                    .map(SongSummary.title) ?? "?"
            } ?? []
        }
    }

    /// Friday holds all seven songs as slots, in order.
    private static func open() async throws -> Fixture {
        let env = try TestEnvironment()
        for folder in ["songs", "setlists"] {
            try FileManager.default.createDirectory(
                at: env.libraryURL.appending(path: folder, directoryHint: .isDirectory),
                withIntermediateDirectories: true,
            )
        }
        for (index, song) in songs.enumerated() {
            let tempo = song.tempo.map { "{tempo: \($0)}\n" } ?? ""
            let capo = song.capo > 0 ? "{capo: \(song.capo)}\n" : ""
            let chords = String(repeating: "[\(song.key)]La la [\(song.key)]la\n", count: 24)
            try env.write(
                "{title: \(song.title)}\n{key: \(song.key)}\n\(capo)\(tempo)\n"
                    + "{start_of_verse: Verse 1}\n\(chords){end_of_verse}\n",
                to: "songs/\(song.slug).cho",
            )
            try env.write(
                #"{"schemaVersion": 3, "id": "\#(id(index))", "#
                    + #""createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-01T10:00:00Z"}"#,
                to: "songs/\(song.slug).segue.json",
            )
        }
        let rows = songs.indices.map { offset in
            #"{"itemId": "01JC0000000000000000000T0\#(offset)", "songId": "\#(id(offset))"}"#
        }
        try env.write(
            #"{"schemaVersion": 6, "id": "\#(fridayID)", "name": "Friday Set", "#
                + #""venue": "The Anchor", "targetDuration": 2700, "#
                + #""entries": [\#(rows.joined(separator: ", "))]}"#,
            to: "setlists/friday.setlist.json",
        )
        let app = try await env.openApp()
        let session = try #require(app.session)
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.undoManager = manager
        let friday = try SetlistID(#require(ULID(string: fridayID)))
        session.setlists.selection = friday
        session.setlists.builderMode = .arrange
        return Fixture(env: env, session: session, manager: manager, friday: friday)
    }

    private func step(_ manager: UndoManager, _ action: () async -> Void) async {
        manager.beginUndoGrouping()
        await action()
        manager.endUndoGrouping()
    }

    /// Rows 3, 5 and 6 (Kesariya, Tum Hi Ho, Channa Mereya) made into one medley.
    private func makeLoveMedley(_ fix: Fixture) async throws -> SetlistItemID {
        let ids = try #require(fix.setlist).entries.map(\.itemId)
        fix.setlists.arrangeSelection.select(ids[2])
        fix.setlists.arrangeSelection.toggle(ids[4], in: ids)
        fix.setlists.arrangeSelection.toggle(ids[5], in: ids)
        #expect(fix.setlists.medleyCandidateSongCount(in: fix.friday) == 3)
        await step(fix.manager) { await fix.setlists.makeMedley(in: fix.friday) }
        let medley = try #require(fix.setlist?.entries[2])
        #expect(medley.isMedley)
        return medley.itemId
    }

    @Test
    func `make medley from non-adjacent rows is one undo step and selects the medley`()
        async throws
    {
        let fix = try await Self.open()
        let medley = try await makeLoveMedley(fix)

        #expect(fix.titles() == [
            "Kettle On, Lights Low", "Harbour Lights", "{Kesariya / Tum Hi Ho / Channa Mereya}",
            "Kitaabon Wali Gali", "Saltwater Telegraph",
        ])
        #expect(fix.manager.undoActionName == "Make Medley")
        #expect(fix.setlists.arrangeSelection.ordered(in: [medley]) == [medley])
        let json = try fix.env.read("setlists/friday.setlist.json")
        #expect(json.contains("\"schemaVersion\" : 7"))
        #expect(json.contains("\"medley\" : {"))
        // Its time is its members' sum; Channa Mereya has no tempo: a lower bound.
        let timing = try SetlistTiming(
            setlist: #require(fix.setlist),
            library: fix.session.library,
            defaultChangeover: 0,
        )
        #expect(!timing.items[2].timeText.contains("≥"))
        #expect(timing.unknownCount == 1)
        let missing = try MissingTimesList.rows(
            #require(fix.setlist),
            within: nil,
            library: fix.session.library,
        )
        #expect(missing.map(\.title) == ["Channa Mereya (in Medley)"])
        #expect(missing.map(\.place) == ["#3c"])

        fix.manager.undo()
        try await waitUntil { fix.setlist?.entries.count == 7 }
        #expect(fix.setlist?.entries.allSatisfy { !$0.isMedley } == true)
    }

    @Test
    func `make medley is refused with a break or a single row selected`() async throws {
        let fix = try await Self.open()
        let ids = try #require(fix.setlist).entries.map(\.itemId)
        fix.setlists.arrangeSelection.select(ids[0])
        #expect(fix.setlists.medleyCandidates(in: fix.friday) == nil)
        fix.setlists.arrangeSelection.select(ids[1])
        await step(fix.manager) { await fix.setlists.insertBreak(in: fix.friday) }
        let withBreak = try #require(fix.setlist).entries.map(\.itemId)
        fix.setlists.arrangeSelection.select(withBreak[1])
        fix.setlists.arrangeSelection.toggle(withBreak[2], in: withBreak)
        #expect(fix.setlists.medleyCandidates(in: fix.friday) == nil)
    }

    @Test
    func `member edits, transitions and renames are one undo step each`() async throws {
        let fix = try await Self.open()
        let medley = try await makeLoveMedley(fix)
        let members = try #require(fix.setlist?.entry(medley)?.medley?.members.map(\.itemId))

        await step(fix.manager) {
            await fix.setlists.setTransition(
                "Hold the D, drums fill",
                member: members[1],
                in: fix.friday,
            )
        }
        #expect(fix.manager.undoActionName == "Edit Transition")
        await step(fix.manager) {
            await fix.setlists.renameMedley(medley, to: "Love medley", in: fix.friday)
        }
        #expect(fix.manager.undoActionName == "Rename Medley")
        #expect(fix.setlist?.entry(medley)?.medley?.displayTitle == "Love medley")

        // ⌥↓ on the last member beeps (false); ⌥↑ moves it.
        var moved = true
        await step(fix.manager) {
            moved = await fix.setlists.moveMember(members[2], by: 1, in: fix.friday)
        }
        #expect(!moved)
        await step(fix.manager) {
            moved = await fix.setlists.moveMember(members[2], by: -1, in: fix.friday)
        }
        #expect(moved)
        #expect(fix.manager.undoActionName == "Move Song in Medley")
        #expect(fix.setlist?.entry(medley)?.medley?.members.map(\.itemId)
            == [members[0], members[2], members[1]])

        // A member's key edits like a slot's.
        var slot = try #require(fix.setlist?.songSlot(members[0])?.asEntry)
        slot.overrides = SetlistOverrides(transpose: 2)
        await step(fix.manager) { await fix.setlists.updateSongSlot(slot, in: fix.friday) }
        #expect(fix.setlist?.songSlot(members[0])?.overrides.transpose == 2)

        // Remove from Medley: the member is a slot right after the medley.
        await step(fix.manager) { await fix.setlists.removeFromMedley(members[1], in: fix.friday) }
        #expect(fix.manager.undoActionName == "Remove from Medley")
        #expect(fix.setlist?.entries[3].itemId == members[1])

        // ⌫ on a member: one left, so the medley becomes that song's slot.
        await step(fix.manager) { await fix.setlists.removeMember(members[2], in: fix.friday) }
        #expect(fix.manager.undoActionName == "Remove Song")
        #expect(fix.setlist?.entries[2].itemId == members[0])
        #expect(fix.setlist?.entries.allSatisfy { !$0.isMedley } == true)
        fix.manager.undo()
        try await waitUntil { fix.setlist?.entry(medley)?.isMedley == true }
    }

    @Test
    func `pick ticks a reprise of a member, unticks only the slot, numbers a medley once`()
        async throws
    {
        let fix = try await Self.open()
        _ = try await makeLoveMedley(fix)
        let kesariya = Self.id(2)
        #expect(fix.setlist?.hasSlot(for: kesariya) == false)
        await step(fix.manager) { await fix.setlists.toggle(kesariya, in: fix.friday) }
        #expect(fix.setlist?.entries.last?.songId == kesariya)
        #expect(fix.setlist?.occurrences(of: kesariya).map(\.label) == ["3a", "6"])
        let setlist = try #require(fix.setlist)
        #expect(RepriseMark.forSlot(kesariya, in: setlist)?.text == "reprise of 3a")
        #expect(RepriseMark.forMember(kesariya, in: setlist)?.text == "also 6")
        await step(fix.manager) { await fix.setlists.toggle(kesariya, in: fix.friday) }
        #expect(fix.setlist?.occurrences(of: kesariya).map(\.label) == ["3a"])
    }

    @Test
    func `the keyboard walks header and members; a collapsed medley is one row`() async throws {
        let fix = try await Self.open()
        let medley = try await makeLoveMedley(fix)
        let setlist = try #require(fix.setlist)
        let members = try #require(setlist.entry(medley)?.medley?.members.map(\.itemId))
        let order = fix.setlists.rowOrder(of: setlist)
        #expect(Array(order[2 ... 5]) == [medley] + members)
        fix.setlists.setCollapsed(medley, true)
        #expect(fix.setlists.rowOrder(of: setlist).count == 5)
        fix.setlists.setCollapsed(medley, false)
        fix.setlists.arrangeSelection.select(members[1])
        #expect(fix.setlists.selectedMember(in: fix.friday) == members[1])
        #expect(fix.setlists.selectedMedley(in: fix.friday) == medley)
        #expect(fix.setlists.canMoveMember(by: 1, in: fix.friday))
        #expect(fix.setlists.arrangeableSelection == members[1])
    }

    // MARK: - Screenshots

    @Test
    func `the group card and its collapsed row render light and dark`() async throws {
        let fix = try await Self.open()
        let medley = try await makeLoveMedley(fix)
        let members = try #require(fix.setlist?.entry(medley)?.medley?.members.map(\.itemId))
        await step(fix.manager) {
            await fix.setlists.renameMedley(medley, to: "Love medley", in: fix.friday)
        }
        await step(fix.manager) {
            await fix.setlists.setTransition(
                "Hold the D, drums fill, straight into the chorus",
                member: members[1],
                in: fix.friday,
            )
        }
        await step(fix.manager) { await fix.setlists.toggle(Self.id(2), in: fix.friday) }
        fix.setlists.arrangeSelection = ListSelection()
        for collapsed in [false, true] {
            fix.setlists.setCollapsed(medley, collapsed)
            for dark in [false, true] {
                let setlist = try #require(fix.setlist)
                let view = SetEntriesList(
                    setlist: setlist,
                    model: fix.setlists,
                    library: fix.session.library,
                )
                .frame(width: 1180, height: collapsed ? 520 : 640)
                .background(Theme.color.ground)
                let name = (collapsed ? "builder-collapsed" : "builder") +
                    (dark ? "-dark" : "-light")
                try Self.render(
                    view,
                    size: CGSize(width: 1180, height: collapsed ? 520 : 640),
                    dark: dark,
                    name: name,
                )
            }
        }
    }

    static func render(_ view: some View, size: CGSize, dark: Bool, name: String) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = try #require(rep.cgImage)
        try DiagramSnapshotTests.writePNG(
            image,
            to: DiagramSnapshotTests.screenshotDirectory
                .deletingLastPathComponent()
                .appending(path: "p9-3/\(name).png"),
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

/// R188 (beside the main suite, at its length limit).
extension MedleyBuilderTests {
    @Test
    func `delete asks first and names the row; a missing member names its file (R188)`()
        async throws
    {
        let fix = try await Self.open()
        let medley = try await makeLoveMedley(fix)
        await step(fix.manager) {
            await fix.setlists.renameMedley(medley, to: "Love medley", in: fix.friday)
        }
        let setlist = try #require(fix.setlist)
        let members = try #require(setlist.entry(medley)?.medley?.members.map(\.itemId))
        let member = try #require(PendingRemoval(
            members[1],
            in: setlist,
            library: fix.session.library,
        ))
        #expect(member.question == "Remove Tum Hi Ho from Love medley?")
        #expect(member.buttonTitle == "Remove Song")
        let slot = try #require(PendingRemoval(
            setlist.entries[0].itemId,
            in: setlist,
            library: fix.session.library,
        ))
        #expect(slot.question == "Remove Kettle On, Lights Low?")
        #expect(slot.buttonTitle == "Remove from Setlist")

        // The song's file goes while Segue runs: the checklist names medley, slot and file.
        try FileManager.default.removeItem(
            at: fix.env.libraryURL.appending(path: "songs/tum-hi-ho.cho"),
        )
        await fix.session.library.reload()
        let slots = setlist.songSlotLabels.filter { $0.slot.songId == Self.id(4) }
        #expect(AppModel.missingMembers(
            slots.map(\.slot),
            labels: slots.map(\.label),
            in: setlist,
            library: fix.session.library,
        ) == ["Love medley, 3b: tum-hi-ho.cho is missing"])
    }
}
