import AppKit
import CoreText
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Setlists
import Shows
import Support
import SwiftUI
import Synchronization
import Testing

/// Regression tests for the phase 2 review (docs/reviews/phase2-review.md) at the app
/// layer: the real `AppModel`, `LiveSession`, show engine and stores on a temp library.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct LiveHardeningTests {
        // MARK: #1 a failed show write: the stage follows the engine, the problem stays up

        @Test
        func `a failed show write keeps the stage in step and stays reported until saved`(
        ) async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let disk = ToggleFailingFileSystem()
            env.fileSystem = disk
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            live.setViewport(LayoutSize(width: 1390, height: 700))

            disk.failing = [LibraryRoot.showSuffix]
            live.dispatch(.next)
            _ = try await env.waitFor { live.problems[.showFile] }
            // The engine advanced in memory and the stage shows it (no skipped song later).
            #expect(live.positionText == "2 of 3")
            #expect(live.state.current?.item.title == "Bravo")
            #expect(live.state.current?.song?.document.metadata.title == "Bravo")
            // Other commands do not clear it; only a successful write does.
            live.dispatch(.toggleRequests)
            live.dispatch(.toggleRequests)
            #expect(live.problems[.showFile] != nil)
            live.dispatch(.next)
            _ = try await env.waitFor { live.positionText == "3 of 3" ? true : nil }
            #expect(live.state.current?.item.title == "Charlie")
            #expect(live.problems[.showFile] != nil)

            disk.failing = []
            live.dispatch(.previous)
            _ = try await env.waitFor { live.problems[.showFile] == nil ? true : nil }
            #expect(live.positionText == "2 of 3")
            let id = live.state.record.id
            let onDisk = try await Self.reloaded(id, env: env)
            #expect(onDisk?.currentItem?.title == "Bravo")
        }

        @Test
        func `song settings that fail to save are reported until a later save succeeds`(
        ) async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let disk = ToggleFailingFileSystem()
            env.fileSystem = disk
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            live.setViewport(LayoutSize(width: 1390, height: 700))

            disk.failing = [".segue.json"]
            live.dispatch(.zoomIn)
            await live.prefsSaved()
            #expect(live.problems[.songPrefs] != nil)
            live.dispatch(.next)
            _ = try await env.waitFor { live.positionText == "2 of 2" ? true : nil }
            #expect(live.problems[.songPrefs] != nil)

            disk.failing = []
            live.dispatch(.zoomIn)
            await live.prefsSaved()
            #expect(live.problems[.songPrefs] == nil)
            // The failed save went again with the later one.
            let alpha = try await fixture.library.reloadSong(id: fixture.songs[0].id)
            #expect(alpha?.sidecar.live.zoom == 1.1)
        }

        // MARK: #16 per-song settings save in order, latest value last

        @Test
        func `quick setting changes save in order and the last one wins`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            live.setViewport(LayoutSize(width: 1390, height: 700))
            for _ in 0 ..< 6 {
                live.dispatch(.zoomIn)
            }
            live.dispatch(.zoomOut)
            live.dispatch(.cycleColumns)
            await live.prefsSaved()
            let expected = try #require(live.currentPrefs)
            let saved = try await fixture.library.reloadSong(id: fixture.songs[0].id)
            #expect(saved?.sidecar.live == expected)
        }

        // MARK: #2 and the stored review: Save merges into the setlist as it is now

        @Test
        func `the reorder review merges into the edited setlist and survives a relaunch`(
        ) async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
            let session = try #require(app.session)
            let late = try await session.library.createSong(
                source: LiveFixture.source(title: "Added Late", lines: 4, duration: nil),
            )
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            live.perform(.move(fromOffsets: [2], toOffset: 1))
            _ = try await env.waitFor {
                live.state.record.items.map(\.title) == ["Alpha", "Charlie", "Bravo"] ? true : nil
            }
            // Edited in the main window during the show.
            await session.setlists.add(late.id, to: fixture.setlist.id)
            live.dispatch(.endShow)
            live.confirmEnd()
            _ = try await env.waitFor { app.pendingReorderReviews.first }

            // Not answered: a relaunch offers it again.
            let relaunched = try await env.openApp()
            let diff = try #require(relaunched.pendingReorderReviews.first)
            #expect(diff.setlistId == fixture.setlist.id)
            #expect(relaunched.setlistChangedSinceShow(diff))
            await relaunched.resolveReorderReview(save: true, including: [])
            #expect(relaunched.pendingReorderReviews.isEmpty)
            let saved = try #require(await relaunched.session?.stores.setlists.setlist(
                id: fixture.setlist.id,
            ))
            var titles: [String?] = []
            for entry in saved.entries {
                try await titles.append(
                    fixture.library.song(id: entry.songId)?.document.metadata.title,
                )
            }
            #expect(titles == ["Alpha", "Charlie", "Bravo", "Added Late"])

            // Answered: never offered again.
            let again = try await env.openApp()
            #expect(again.pendingReorderReviews.isEmpty)
        }

        // MARK: #3 play now of the current song from search

        @Test
        func `play now of the song on stage does not duplicate it`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            for _ in 0 ..< 2 {
                live.dispatch(.openSearch)
                live.searchAction(.playNow, song: fixture.songs[0].id)
            }
            live.perform(.next)
            _ = try await env.waitFor { live.positionText == "2 of 2" ? true : nil }
            #expect(live.state.record.items.map(\.title) == ["Alpha", "Bravo"])
            #expect(live.state.record.items.allSatisfy { $0.state != .pending })
        }

        // MARK: #4 key auto-repeat never advances songs

        @Test
        func `key repeats scroll but never advance songs or toggle panels`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }

            for _ in 0 ..< 30 {
                #expect(try LiveKeyInput.handle(Self.key(124, repeat: true), session: live))
            }
            #expect(try LiveKeyInput.handle(Self.key(1, "s", repeat: true), session: live))
            try await Task.sleep(for: .milliseconds(200))
            #expect(live.positionText == "1 of 3")
            #expect(!live.showsDrawer)

            #expect(try LiveKeyInput.handle(Self.key(124, repeat: false), session: live))
            _ = try await env.waitFor { live.positionText == "2 of 3" ? true : nil }
        }

        // MARK: #8 Return in quick search never acts on an earlier query's results

        @Test
        func `return during a running search acts on the query as typed`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }

            live.dispatch(.openSearch)
            live.search.query = "charlie"
            _ = try await env.waitFor { live.search.isCurrent ? live.search.results.first : nil }
            // Typing outruns the search: Return lands before "bravo" has results.
            live.search.query = "bravo"
            #expect(!live.search.isCurrent)
            live.submitSearch(.playNow)
            _ = try await env.waitFor { live.state.current?.item.title == "Bravo" ? true : nil }
            #expect(live.overlay == nil)
            #expect(!live.state.record.items
                .contains { $0.title == "Charlie" && $0.state == .current })
        }

        // MARK: Helpers

        static func key(
            _ code: UInt16,
            _ characters: String = "",
            command: Bool = false,
            repeat isRepeat: Bool = false,
        ) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: command ? .command : [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: isRepeat,
                keyCode: code,
            ))
        }

        static func reloaded(_ id: ShowID, env: TestEnvironment) async throws -> ShowRecord? {
            let store = ShowStore(fileSystem: LiveFileSystem(), clock: env.clock, playHistory: nil)
            try await store.load(root: LibraryRoot(url: env.libraryURL))
            return await store.show(id: id)
        }

        /// Waits until no run holds show `id` (the stage let go of it).
        static func waitUntilReleased(_ id: ShowID, env: TestEnvironment) async throws {
            let store = ShowStore(fileSystem: LiveFileSystem(), clock: env.clock, playHistory: nil)
            try await store.load(root: LibraryRoot(url: env.libraryURL))
            let deadline = ContinuousClock.now + .seconds(5)
            while await store.isClaimedElsewhere(id), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(await !store.isClaimedElsewhere(id))
        }

        /// The 13" stage as drawn, to `.build/screenshots/hardening/<name>.png`.
        static func renderStage(_ live: LiveSession, name: String) throws {
            let screen = CGSize(width: 1470, height: 956)
            let view = LiveView(session: live)
                .frame(width: screen.width, height: screen.height)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage, "no image for \(name)")
            try DiagramSnapshotTests.writePNG(
                image,
                to: hardeningDirectory.appending(path: "\(name).png"),
            )
        }

        /// `<repo>/.build/screenshots/hardening`.
        static var hardeningDirectory: URL {
            DiagramSnapshotTests.screenshotDirectory
                .deletingLastPathComponent()
                .appending(path: "hardening", directoryHint: .isDirectory)
        }
    }
}

/// Real IO that fails writes of chosen file kinds on demand (a full or read-only disk).
final class ToggleFailingFileSystem: FileSystem {
    struct Failure: Error, LocalizedError {
        var errorDescription: String? {
            "the disk is full"
        }
    }

    private let live = LiveFileSystem()
    private let suffixes = Mutex<[String]>([])

    /// File name suffixes whose writes fail.
    var failing: [String] {
        get { suffixes.withLock { $0 } }
        set { suffixes.withLock { $0 = newValue } }
    }

    func fileExists(at url: URL) -> Bool {
        live.fileExists(at: url)
    }

    func directoryExists(at url: URL) -> Bool {
        live.directoryExists(at: url)
    }

    func createDirectory(at url: URL) throws {
        try live.createDirectory(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try live.contentsOfDirectory(at: url)
    }

    func readData(at url: URL) throws -> Data {
        try live.readData(at: url)
    }

    func readFiles(_ urls: [URL], in directory: URL) -> [Result<Data, any Error>] {
        live.readFiles(urls, in: directory)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        let name = url.lastPathComponent
        if failing.contains(where: name.hasSuffix) {
            throw Failure()
        }
        try live.writeAtomically(data, to: url)
    }

    func removeItem(at url: URL) throws {
        try live.removeItem(at: url)
    }

    func moveItem(from source: URL, to destination: URL) throws {
        try live.moveItem(from: source, to: destination)
    }

    func attributes(at url: URL) throws -> FileAttributes {
        try live.attributes(at: url)
    }
}
