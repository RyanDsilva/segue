import Foundation
import Library
@testable import SegueUI
import Testing

/// Smart filters in a real in-process session (P3-6): what the sidebar section drives
/// (selecting a filter or the built-in "Missing essentials" narrows the song list), the
/// editor sheet's draft, undo of filter and tag edits, and restore on relaunch.
@MainActor
struct SmartFilterSessionTests {
    /// Kept alive here: the session holds its undo manager weakly (the window owns it).
    private static let managers = UndoManagerBox()

    private static func session(_ env: TestEnvironment) async throws -> (AppModel, LibrarySession) {
        env.libraryLock = .unlocked
        let app = try await env.openApp()
        let session = try #require(app.session)
        let manager = UndoManager()
        manager.groupsByEvent = false
        managers.keep(manager)
        session.undoManager = manager
        for (title, extra, tags) in [
            ("Harbour", "{key: G}\n{tempo: 96}\n{duration: 3:30}", ["upbeat"]),
            ("Lantern", "{key: Am}\n{tempo: 70}\n{duration: 5:00}", ["ballad"]),
            ("Unfinished", "", ["upbeat"]),
        ] {
            let song = try await session.library
                .createSong(source: "{title: \(title)}\n\(extra)\nLa\n")
            _ = try await session.stores.library.updateMetadata(
                id: song.id,
                SongMetadata(tags: tags),
            )
        }
        await session.library.reload()
        return (app, session)
    }

    /// Runs `edit` as one undo group (no event loop in tests).
    private static func grouped(_ session: LibrarySession, _ edit: () async -> Void) async {
        session.undoManager?.beginUndoGrouping()
        await edit()
        session.undoManager?.endUndoGrouping()
    }

    private static func titles(_ session: LibrarySession) -> [String] {
        session.library.results.compactMap(\.document.metadata.title)
    }

    @Test
    func `selecting a smart filter narrows the list and the Library shows every song`(
    ) async throws {
        let env = try TestEnvironment()
        let (_, session) = try await Self.session(env)
        await Self.grouped(session) {
            await session.createSmartFilter(
                name: "Upbeat",
                conditions: SmartFilterConditions(anyTags: ["upbeat"]),
            )
        }
        let filter = try #require(session.smartFilters.filters.first)
        #expect(env.exists("filters/upbeat.filter.json"))
        #expect(session.section == .smartFilter(filter.id))
        try await env.waitFor { Self.titles(session) == ["Harbour", "Unfinished"] ? true : nil }
        #expect(session.library.scope.title == "Upbeat")

        session.section = .missingEssentials
        try await env.waitFor { Self.titles(session) == ["Unfinished"] ? true : nil }
        #expect(SmartFiltersViewModel.missingEssentialsCount(in: session.library.catalog) == 1)

        session.section = .library
        try await env.waitFor { Self.titles(session).count == 3 ? true : nil }
        #expect(session.library.scope == .all)
    }

    @Test
    func `editing and deleting a filter undo, and a deleted selection falls back`() async throws {
        let env = try TestEnvironment()
        let (_, session) = try await Self.session(env)
        await Self.grouped(session) {
            await session.createSmartFilter(
                name: "Slow",
                conditions: SmartFilterConditions(tempo: SmartFilterRange(max: 80)),
            )
        }
        let filter = try #require(session.smartFilters.filters.first)
        try await env.waitFor { Self.titles(session) == ["Lantern"] ? true : nil }

        await Self.grouped(session) {
            await session.smartFilters.save(
                filter.id,
                name: "Slow songs",
                conditions: SmartFilterConditions(
                    tempo: SmartFilterRange(max: 100),
                ),
            )
        }
        try await env.waitFor { Self.titles(session) == ["Harbour", "Lantern"] ? true : nil }
        session.undoManager?.undo()
        try await env.waitFor { session.smartFilters.filters.first?.name == "Slow" ? true : nil }

        await Self.grouped(session) { await session.smartFilters.delete(filter.id) }
        #expect(session.smartFilters.filters.isEmpty)
        #expect(!env.exists("filters/slow.filter.json"))
        #expect(session.section == .library)
        session.undoManager?.undo()
        try await env.waitFor { session.smartFilters.filters.first?.id == filter.id ? true : nil }
        #expect(env.exists("filters/slow.filter.json"))
    }

    @Test
    func `renaming a tag rewrites songs and filters in one undo step`() async throws {
        let env = try TestEnvironment()
        let (_, session) = try await Self.session(env)
        await Self.grouped(session) {
            await session.createSmartFilter(
                name: "Lively",
                conditions: SmartFilterConditions(allTags: ["upbeat"]),
            )
        }
        await Self.grouped(session) { await session.renameTag("upbeat", to: "lively") }
        #expect(session.library.tagNames.contains("lively"))
        #expect(!session.library.tagNames.contains("upbeat"))
        #expect(session.smartFilters.filters.first?.conditions.allTags == ["lively"])

        session.undoManager?.undo()
        try await env.waitFor { session.library.tagNames.contains("upbeat") ? true : nil }
        try await env.waitFor {
            session.smartFilters.filters.first?.conditions.allTags == ["upbeat"] ? true : nil
        }
        session.undoManager?.redo()
        try await env.waitFor { session.library.tagNames.contains("lively") ? true : nil }

        await Self.grouped(session) { await session.deleteTag("ballad") }
        #expect(!session.library.tagNames.contains("ballad"))
        session.undoManager?.undo()
        try await env.waitFor { session.library.tagNames.contains("ballad") ? true : nil }
    }

    @Test
    func `a smart filter section is restored on relaunch`() async throws {
        let env = try TestEnvironment()
        let (_, session) = try await Self.session(env)
        await Self.grouped(session) {
            await session.createSmartFilter(name: "Any", conditions: SmartFilterConditions())
        }
        let filter = try #require(session.smartFilters.filters.first)
        session.restore?.write(session.currentRestoredState)

        let again = try #require(try await env.openApp().session)
        #expect(again.section == .smartFilter(filter.id))
        #expect(again.library.scope == .smartFilter(filter))
    }

    @Test
    func `the draft round trips conditions and rejects bad values`() {
        let conditions = SmartFilterConditions(
            anyTags: ["upbeat", "cover"],
            noneTags: ["ballad"],
            proficiencies: [.pro, .ready],
            keys: ["G", "Em"],
            tempo: SmartFilterRange(min: 90),
            length: SmartFilterRange(min: 150, max: 300),
            neverPlayed: true,
        )
        var draft = SmartFilterDraft(name: "Openers", conditions: conditions)
        #expect(draft.rows.map(\.kind) == [
            .anyTags,
            .noneTags,
            .proficiency,
            .keys,
            .tempo,
            .length,
            .neverPlayed,
        ])
        #expect(draft.rows[5].lower == "2:30")
        var expected = conditions
        expected.proficiencies = [.ready, .pro]
        #expect(draft.conditions == expected)
        #expect(draft.problem == nil)

        draft.rows[5].upper = "4.5"
        #expect(draft.problem == "Enter lengths as m:ss, for example 3:30.")
        draft.rows[5].upper = ""
        draft.name = "  "
        #expect(draft.problem == "Give the filter a name.")

        let fresh = SmartFilterDraft(name: "", conditions: SmartFilterConditions())
        #expect(fresh.rows.map(\.kind) == [.anyTags])
        #expect(fresh.conditions.isEmpty)
        var full = fresh
        while !full.unusedKinds().isEmpty {
            full.addRow(after: nil)
        }
        #expect(full.rows.count == SmartFilterDraft.Kind.allCases.count)
        full.removeRow(full.rows[0].id)
        #expect(full.rows.count == SmartFilterDraft.Kind.allCases.count - 1)
    }
}

/// Holds test undo managers for the test process's lifetime.
@MainActor
final class UndoManagerBox {
    private var managers: [UndoManager] = []

    func keep(_ manager: UndoManager) {
        managers.append(manager)
    }
}
