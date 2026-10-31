import AppKit
import Foundation
import Library
@testable import SegueUI
import SetAssistant
import Setlists
import Support
import SwiftUI
import Testing

/// The set assistant on a real app session (P3-7, R114-R116): instant lexicon chips, Build
/// filling the open setlist as one undo step, saved locks honoured by Rebuild, scores per
/// row, R107's left-out songs, no model asked without a local one, and the command bar and
/// breakdown rendered in light and dark.
@MainActor
struct SetAssistantUITests {
    private static let setlistID = "01JC0000000000000000000F01"
    private static let keys = ["G", "D", "A", "E", "C", "Am", "Em", "Bm"]
    private static let tags = ["upbeat", "ballad", "cover", "singalong"]

    private static func id(_ index: Int) -> SongID {
        SongID(ULID(
            milliseconds: 1_000_000,
            randomness: [UInt8](repeating: 0, count: 9)
                + [UInt8(index)],
        ))
    }

    private struct Fixture {
        var env: TestEnvironment
        var session: LibrarySession
        var manager: UndoManager
        var setlist: SetlistID
        var assistant: SetAssistantModel
    }

    /// 40 songs: every 7th has no length, every 5th is Learning, tags and keys rotate.
    private static func open() async throws -> Fixture {
        let env = try TestEnvironment()
        for folder in ["songs", "setlists"] {
            try FileManager.default.createDirectory(
                at: env.libraryURL.appending(path: folder, directoryHint: .isDirectory),
                withIntermediateDirectories: true,
            )
        }
        for index in 0 ..< 40 {
            let seconds = 180 + (index * 37) % 120
            let length = index % 7 == 3 ? "" : "{duration: \(seconds / 60):"
                + String(format: "%02d", seconds % 60) + "}\n"
            // P8-8: every 4th song is Arijit Singh's from Kalank, the next a legacy duo.
            let credits = index.isMultiple(of: 4) ? "{artist: Arijit Singh}\n{album: Kalank}\n"
                : index % 4 == 1 ? "{artist: Vishal & Shekhar}\n" : ""
            try env.write(
                "{title: Song \(index)}\n\(credits){key: \(keys[index % keys.count])}\n"
                    + "{tempo: \(70 + index * 2)}\n\(length)[G]La la\n",
                to: "songs/song-\(index).cho",
            )
            let level = index.isMultiple(of: 5) ? "learning"
                : index.isMultiple(of: 2) ? "pro" : "ready"
            let tag = tags[index % tags.count]
            try env.write(
                #"{"schemaVersion": 3, "id": "\#(id(index))", "tags": ["\#(tag)"], "#
                    + #""proficiency": "\#(level)", "createdAt": "2026-10-01T10:00:00Z", "#
                    + #""updatedAt": "2026-10-01T10:00:00Z"}"#,
                to: "songs/song-\(index).segue.json",
            )
        }
        try env.write(
            #"{"schemaVersion": 3, "id": "\#(setlistID)", "name": "Friday", "entries": []}"#,
            to: "setlists/friday.setlist.json",
        )
        let app = try await env.openApp()
        let session = try #require(app.session)
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.undoManager = manager
        let setlist = try SetlistID(#require(ULID(string: setlistID)))
        let assistant = SetAssistantModel(
            setlists: session.setlists,
            library: session.library,
            idleDelay: .milliseconds(10),
        )
        return Fixture(
            env: env, session: session, manager: manager, setlist: setlist, assistant: assistant,
        )
    }

    private func build(_ fix: Fixture, rebuild: Bool = false) async {
        fix.manager.beginUndoGrouping()
        await fix.assistant.build(into: fix.setlist, rebuild: rebuild, defaultChangeover: 0)
        fix.manager.endUndoGrouping()
    }

    @Test
    func `chips appear as typed and Build fills the open setlist as one undo step`(
    ) async throws {
        let fix = try await Self.open()
        fix.assistant.text = "30 min set, songs I know well, no covers"
        #expect(fix.assistant.chips.map(\.kind) == [
            .length(1800), .proficiency(.ready), .excludeTag("cover"),
        ])
        #expect(fix.assistant.chips.map { $0.kind.title() } == ["30 min", "Ready+", "no cover"])

        await build(fix)
        let setlist = try #require(fix.session.setlists.setlist(fix.setlist))
        #expect(fix.manager.undoActionName == "Build Set")
        #expect(setlist.targetDuration == 1800)
        let records = setlist.entries.compactMap(\.songId).compactMap(fix.session.library.song)
        #expect(Set(records.map(\.id)).count == records.count)
        let total = records.compactMap(\.document.metadata.duration).reduce(0, +)
        #expect(abs(total - 1800) <= 180)
        for record in records {
            #expect(record.sidecar.proficiency != .learning)
            #expect(!record.sidecar.tags.contains("cover"))
        }
        // Every row has a score, and the breakdown adds up.
        let breakdowns = fix.assistant.breakdowns(for: setlist)
        #expect(breakdowns.count == records.count)
        for breakdown in breakdowns.values {
            #expect(abs(breakdown.contributions.map(\.value).reduce(0, +) - breakdown.total)
                < 1e-9)
        }
        // R107: the matched songs without a length are named.
        let result = try #require(fix.assistant.result)
        #expect(!result.leftOutNoLength.isEmpty)
        #expect(result.leftOutNoLength.allSatisfy {
            fix.session.library.song(id: $0)?.document.metadata.duration == nil
        })

        fix.manager.undo()
        try await fix.env.waitFor {
            fix.session.setlists.setlist(fix.setlist)?.entries.isEmpty == true ? true : nil
        }
    }

    @Test
    func `locks are saved and Rebuild keeps them in place`() async throws {
        let fix = try await Self.open()
        fix.assistant.text = "40 minutes"
        await build(fix)
        let built = try #require(fix.session.setlists.setlist(fix.setlist))
        let first = built.entries[0]
        let third = built.entries[2]
        fix.manager.beginUndoGrouping()
        await fix.session.setlists.setLocked([first.itemId, third.itemId], true, in: fix.setlist)
        fix.manager.endUndoGrouping()
        #expect(fix.manager.undoActionName == "Lock Songs")
        let file = try String(
            contentsOf: fix.env.libraryURL.appending(path: "setlists/friday.setlist.json"),
            encoding: .utf8,
        )
        #expect(file.contains("\"locked\" : true"))
        #expect(file.contains("\"schemaVersion\" : 6"))

        await build(fix, rebuild: true)
        let rebuilt = try #require(fix.session.setlists.setlist(fix.setlist))
        #expect(fix.manager.undoActionName == "Rebuild Set")
        #expect(rebuilt.entries[0].songId == first.songId)
        #expect(rebuilt.entries[0].locked)
        #expect(rebuilt.entries[2].songId == third.songId)
        #expect(rebuilt.songEntries.map(\.songId) != built.songEntries.map(\.songId))

        fix.manager.beginUndoGrouping()
        await fix.session.setlists.toggleLock(first.itemId, in: fix.setlist)
        fix.manager.endUndoGrouping()
        #expect(fix.session.setlists.setlist(fix.setlist)?.entries[0].locked == false)
    }

    @Test
    func `no model is asked without a local model; chips stay the lexicon's`() async throws {
        let fix = try await Self.open()
        fix.assistant.text = "45 min, pub night"
        try await Task.sleep(for: .milliseconds(60))
        await fix.assistant.suggestNow()
        #expect(fix.assistant.suggested.isEmpty)
        #expect(!fix.assistant.isSuggesting)
        #expect(fix.assistant.chips.map(\.kind) == [.length(2700)])
        // Removing a stated chip stops it applying; editing the text keeps it removed.
        let length = try #require(fix.assistant.chips.first)
        fix.assistant.remove(length)
        #expect(fix.assistant.chips.isEmpty)
        #expect(!fix.assistant.canBuild)
        fix.assistant.add(.songCount(6))
        #expect(fix.assistant.request.songCount == 6)
    }

    @Test
    func `NL picks: the stage reads the lexicon with no model, the library narrows its search`(
    ) async throws {
        let fix = try await Self.open()
        // Stage: "ballads in Am" -> only Am ballads, then the plain text hits (none here).
        let (found, chips) = try await QuickSearchModel.lexiconSearch(
            "ballads in Am", in: fix.session.stores.library,
        )
        #expect(chips == ["ballad", "in Am"])
        #expect(!found.records.isEmpty)
        for record in found.records {
            #expect(record.sidecar.tags == ["ballad"])
            #expect(record.document.metadata.key == "Am")
        }
        // A plain title search is unchanged.
        let (plain, none) = try await QuickSearchModel.lexiconSearch(
            "Song 12", in: fix.session.stores.library,
        )
        #expect(none.isEmpty)
        #expect(plain.records.first?.document.metadata.title == "Song 12")

        // Library: the lexicon narrows the filter; the words it did not read stay the text.
        let tags = fix.session.library.tags.map(\.tag)
        #expect(LibraryLexicon.chips("songs I know cold under 100 bpm", knownTags: tags)
            == [.proficiency(.pro), .tempo(TempoRange(max: 100))])
        let filter = SongFilterState(query: "Lala no covers under 100 bpm").filter(knownTags: tags)
        #expect(filter.text == "Lala")
        #expect(filter.excludedTags == ["cover"])
        #expect(filter.tempo == SongFilter.Bounds(upper: 100))
        #expect(SongFilterState(query: "Let It Be").filter(knownTags: tags).text == "Let It Be")
    }

    /// P8-8 section 3.5.2: the library's artists and movies reach every lexicon (the
    /// assistant, the library search and the stage), any artist matching.
    @Test
    func `requests by artist and movie read as chips in the assistant, library and stage`(
    ) async throws {
        let fix = try await Self.open()
        let library = fix.session.library
        fix.assistant.text = "ballads by arijit, not from kalank"
        try await Task.sleep(for: .milliseconds(60))
        let kinds = fix.assistant.chips.map(\.kind)
        #expect(kinds.contains(.artist("Arijit Singh")))
        #expect(kinds.contains(.excludeAlbum("Kalank")))

        let tags = library.tags.map(\.tag)
        #expect(LibraryLexicon.chips(
            "shekhar songs",
            knownTags: tags,
            credits: library
                .lexiconCredits,
        ) == [.artist("Shekhar")])
        let filter = library.songFilter(SongFilterState(query: "from kalank"))
        let matching = library.catalog.filter(filter.matches)
        #expect(matching.count == 10)
        #expect(matching.allSatisfy { $0.document.metadata.album == "Kalank" })
        let duo = library.catalog.filter(library.songFilter(SongFilterState(query: "by shekhar"))
            .matches)
        #expect(duo.count == 10)

        let (found, chips) = try await QuickSearchModel.lexiconSearch(
            "by arijit", in: fix.session.stores.library,
        )
        #expect(chips == ["by Arijit Singh"])
        #expect(found.records.count == 10)
        #expect(found.records.allSatisfy { $0.document.metadata.artists == ["Arijit Singh"] })
    }

    @Test
    func `the command bar and a breakdown render in light and dark`() async throws {
        let fix = try await Self.open()
        fix.assistant.text = "35 min, songs I know well, upbeat start, no covers"
        await build(fix)
        let setlist = try #require(fix.session.setlists.setlist(fix.setlist))
        let breakdown = try #require(fix.assistant
            .breakdowns(for: setlist)[setlist.entries[0].itemId])
        for dark in [false, true] {
            let view = VStack(spacing: 0) {
                AssistantCommandBar(
                    setlist: setlist, model: fix.assistant, library: fix.session.library,
                )
                ScoreBreakdownView(title: "Song 2", breakdown: breakdown)
            }
            .frame(width: 900)
            .background(Theme.color.ground)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = try #require(rep.cgImage)
            #expect(image.width >= 900)
            try DiagramSnapshotTests.writePNG(
                image,
                to: DiagramSnapshotTests.screenshotDirectory
                    .deletingLastPathComponent()
                    .appending(path: "set-assistant/bar-\(dark ? "dark" : "light").png"),
            )
        }
    }
}
