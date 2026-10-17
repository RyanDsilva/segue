import AppKit
import Foundation
import Library
@testable import SegueUI
import Setlists
import Shows
import Support
import Testing

/// Regression tests for the phase 0 review (docs/reviews/phase0-review.md) at the app layer:
/// the real `AppModel`, view models and stores on a temp library folder, with an isolated
/// `UserDefaults` suite for the library bookmark.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct AppHardeningTests {
        // MARK: #6 the library is found again on the next launch

        @Test
        func `first launch has no library, and a remembered folder resolves on relaunch`() throws {
            let env = try TestEnvironment()
            #expect(env.location().resolveStored() == .notChosen)

            try env.location().remember(env.libraryURL)

            let relaunched = env.location()
            guard case let .resolved(url) = relaunched.resolveStored() else {
                Issue.record("stored bookmark did not resolve")
                return
            }
            #expect(url.resolvingSymlinksInPath() == env.libraryURL.resolvingSymlinksInPath())
            relaunched.endAccess()
        }

        @Test
        func `a moved library folder is still found through its bookmark`() throws {
            let env = try TestEnvironment()
            try env.location().remember(env.libraryURL)
            let moved = env.scratch.appending(path: "Moved Library", directoryHint: .isDirectory)
            try FileManager.default.moveItem(at: env.libraryURL, to: moved)

            let location = env.location()
            guard case let .resolved(url) = location.resolveStored() else {
                Issue.record("moved folder was not found")
                return
            }
            #expect(url.resolvingSymlinksInPath() == moved.resolvingSymlinksInPath())
            location.endAccess()
        }

        @Test
        func `a deleted library folder or a corrupt bookmark asks for the folder again`() throws {
            let env = try TestEnvironment()
            try env.location().remember(env.libraryURL)
            try FileManager.default.removeItem(at: env.libraryURL)
            guard case .lost = env.location().resolveStored() else {
                Issue.record("deleted folder still resolved")
                return
            }

            env.defaults.set(Data("not a bookmark".utf8), forKey: LibraryLocation.bookmarkKey)
            #expect(env.location().resolveStored() == .lost(nil))
        }

        @Test
        func `a second launch opens the library from the stored bookmark`() async throws {
            let env = try TestEnvironment()
            let first = env.app(override: env.libraryURL, remember: true)
            await first.start()
            let session = try #require(first.session)
            _ = try await session.library.createSong(source: "{title: Kept}\nStill here\n")
            #expect(session.library.errorMessage == nil)

            let second = env.app()
            await second.start()

            let reopened = try #require(second.session)
            #expect(reopened.root == LibraryRoot(url: env.libraryURL))
            #expect(reopened.library.catalog.map(\.document.metadata.title) == ["Kept"])
        }

        // MARK: #13 a failed remember() keeps the opened library

        @Test
        func `a folder that can't be remembered stays open with a warning`() async throws {
            let env = try TestEnvironment()
            let location = LibraryLocation(defaults: env.defaults) { _ in
                throw CocoaError(.fileWriteNoPermission)
            }
            let app = AppModel(dependencies: env.dependencies(
                location: location,
                override: env.libraryURL,
                remember: true,
            ))

            await app.start()

            let session = try #require(app.session)
            #expect(session.library.errorMessage?.contains("could not remember") == true)
            #expect(location.resolveStored() == .notChosen)
        }

        // MARK: #5 missing songs are announced before the stage opens

        @Test
        func `start lists missing songs in the checklist and leaves them out`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let session = try #require(app.session)
            let first = try await session.library.createSong(source: "{title: First}\nOne\n")
            let gone = try await session.library.createSong(source: "{title: Gone}\nTwo\n")
            let third = try await session.library.createSong(source: "{title: Third}\nThree\n")
            let setlist = try #require(await session.setlists.create(name: "Friday"))
            for song in [first, gone, third] {
                await session.setlists.add(song.id, to: setlist.id)
            }
            let saved = try #require(session.setlists.selected)
            try FileManager.default
                .removeItem(at: env.libraryURL.appending(path: gone.relativePath))

            // Cancel at the checklist: nothing starts and Gig Mode is undone.
            let cancelled = Task { await app.startShow(saved, kind: .gig) }
            let checklist = try await env.waitFor { app.preShow }
            #expect(checklist.missingPositions == [2])
            #expect(checklist.focus == .ran(LiveSettings.defaultStartShortcut))
            checklist.answer(false)
            #expect(await cancelled.value == false)
            #expect(app.live == nil)
            #expect(try env.shortcutsRun() == ["Gig Mode On", "Gig Mode Off"])

            // Start: the missing entry is left out.
            let started = Task { await app.startShow(saved, kind: .gig) }
            try await env.waitFor { app.preShow }.answer(true)
            #expect(await started.value)
            let live = try #require(app.live)
            #expect(live.state.record.items.map(\.songId) == [first.id, third.id])
            #expect(app.isPerforming)
            StageWindowController.shared.close()
            #expect(app.live == nil)
        }

        @Test
        func `a setlist whose songs are all gone does not start`() async throws {
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let session = try #require(app.session)
            let gone = try await session.library.createSong(source: "{title: Gone}\nTwo\n")
            let setlist = try #require(await session.setlists.create(name: "Empty"))
            await session.setlists.add(gone.id, to: setlist.id)
            try FileManager.default
                .removeItem(at: env.libraryURL.appending(path: gone.relativePath))

            #expect(try await app
                .startShow(#require(session.setlists.selected), kind: .gig) == false)
            #expect(app.preShow == nil)
            #expect(app.startFailure?.contains("None of the songs") == true)
            #expect(try env.shortcutsRun().isEmpty)
        }

        // MARK: #7 presenting the stage again keeps the performance

        @Test
        func `presenting the stage twice keeps the performance until it is closed`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let session = try #require(app.session)
            let song = try await session.library.createSong(source: "{title: Stage}\nLights\n")
            let setlist = try #require(await session.setlists.create(name: "Stage"))
            await session.setlists.add(song.id, to: setlist.id)
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(try await app.startShow(#require(session.setlists.selected), kind: .rehearsal))
            let live = try #require(app.live)
            let stage = StageWindowController.shared
            let firstWindow = try #require(stage.stageWindow)
            #expect(live.isKeepingAwake)

            stage.present(app)

            #expect(app.live === live)
            let secondWindow = try #require(stage.stageWindow)
            #expect(secondWindow !== firstWindow)
            #expect(!firstWindow.isVisible)

            stage.close()
            #expect(app.live == nil)
            #expect(stage.stageWindow == nil)
            #expect(!live.isKeepingAwake)
        }

        // MARK: #2 unreadable song files are surfaced

        @Test
        func `song files that can't be loaded are listed in the library`() async throws {
            let env = try TestEnvironment()
            let songs = env.libraryURL.appending(path: "songs", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: songs, withIntermediateDirectories: true)
            let locked = songs.appending(path: "locked.cho")
            try Data("{title: Locked}\n".utf8).write(to: locked)
            try Data("{title: Fine}\n".utf8).write(to: songs.appending(path: "fine.cho"))
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644],
                    ofItemAtPath: locked.path,
                )
            }

            let app = try await env.openApp()

            let library = try #require(app.session?.library)
            #expect(library.catalog.map(\.document.metadata.title) == ["Fine"])
            #expect(library.loadIssues.map(\.relativePath) == ["songs/locked.cho"])
        }

        // MARK: #1 saving over an external edit asks first

        @Test
        func `an external edit while editing raises a conflict and save as copy keeps both`(
        ) async throws {
            let env = try TestEnvironment()
            let library = try await env.openLibrary()
            let song = try await library.createSong(source: "{title: Shared}\nOriginal\n")
            library.beginEditing(song)
            let editor = try #require(library.editor)
            let external = "{title: Shared}\nEdited in another app\n"
            try env.write(external, to: song.relativePath)

            editor.sourceTextDidChange("{title: Shared}\nMy edit\n")
            await library.saveEditor()

            #expect(library.saveConflict?.kind == .sourceChanged)
            #expect(library.editor === editor)
            #expect(try env.read(song.relativePath) == external)

            await library.resolveSaveConflict(.saveAsCopy)

            #expect(library.saveConflict == nil)
            #expect(library.editor == nil)
            #expect(try env.read(song.relativePath) == external)
            let copy = try #require(library.catalog.first { $0.id != song.id })
            #expect(copy.source == "{title: Shared}\nMy edit\n")
            #expect(library.selection == copy.id)
        }

        @Test
        func `a conflict can be resolved by overwriting or by reloading`() async throws {
            let env = try TestEnvironment()
            let library = try await env.openLibrary()
            let song = try await library.createSong(source: "{title: Shared}\nOriginal\n")

            library.beginEditing(song)
            try env.write("{title: Shared}\nTheirs\n", to: song.relativePath)
            library.editor?.sourceTextDidChange("{title: Shared}\nMine\n")
            await library.saveEditor()
            await library.resolveSaveConflict(.overwrite)
            #expect(library.editor == nil)
            #expect(try env.read(song.relativePath) == "{title: Shared}\nMine\n")

            let current = try #require(library.song(id: song.id))
            library.beginEditing(current)
            try env.write("{title: Shared}\nTheirs again\n", to: song.relativePath)
            library.editor?.sourceTextDidChange("{title: Shared}\nMine again\n")
            await library.saveEditor()
            #expect(library.saveConflict?.kind == .sourceChanged)
            await library.resolveSaveConflict(.reload)
            #expect(library.editor?.source == "{title: Shared}\nTheirs again\n")
            #expect(library.editor?.hasUnsavedChanges == false)
            #expect(try env.read(song.relativePath) == "{title: Shared}\nTheirs again\n")
        }

        // MARK: #10 edits survive an external delete and a slow save

        @Test
        func `editing a song deleted on disk keeps the edits and saves them as a new song`(
        ) async throws {
            let env = try TestEnvironment()
            let library = try await env.openLibrary()
            let song = try await library.createSong(source: "{title: Doomed}\nOriginal\n")
            library.beginEditing(song)
            let editor = try #require(library.editor)
            editor.sourceTextDidChange("{title: Doomed}\nUnsaved work\n")
            try FileManager.default
                .removeItem(at: env.libraryURL.appending(path: song.relativePath))

            await library.refresh()

            #expect(library.editor === editor)
            #expect(library.isEditingDeletedSong)
            await library.saveEditor()
            #expect(library.saveConflict?.kind == .deleted)
            await library.resolveSaveConflict(.saveAsCopy)
            let saved = try #require(library.catalog.first)
            #expect(saved.id != song.id)
            #expect(saved.source == "{title: Doomed}\nUnsaved work\n")
            #expect(library.editor == nil)
        }

        @Test
        func `text typed while a save is in flight stays in the editor as unsaved`() async throws {
            let env = try TestEnvironment()
            let library = try await env.openLibrary()
            library.beginNewSong()
            let editor = try #require(library.editor)
            editor.sourceTextDidChange("{title: Racing}\nFirst line\n")

            let save = Task { await library.saveEditor() }
            // Once `isSaving` is up the save has taken its text and is waiting on the store.
            let deadline = ContinuousClock.now + .seconds(10)
            while !editor.isSaving, ContinuousClock.now < deadline {
                await Task.yield()
            }
            #expect(editor.isSaving, "the save never started")
            editor.sourceTextDidChange("{title: Racing}\nFirst line\nTyped during the save\n")
            await save.value

            let record = try #require(library.catalog.first)
            #expect(record.source == "{title: Racing}\nFirst line\n")
            let open = try #require(library.editor)
            #expect(open.mode == .edit(record.id))
            #expect(open.source == "{title: Racing}\nFirst line\nTyped during the save\n")
            #expect(open.hasUnsavedChanges)

            // And the follow-up save goes through (no false conflict with its own first save).
            await library.saveEditor()
            #expect(library.saveConflict == nil)
            #expect(library.editor == nil)
            #expect(try env.read(record.relativePath).contains("Typed during the save"))
        }

        // MARK: #13 search spinner

        @Test
        func `the searching flag is up until the newest search lands`() async throws {
            let env = try TestEnvironment()
            let library = try await env.openLibrary(debounce: .milliseconds(30))
            _ = try await library.createSong(source: "{title: Needle}\nHay\n")

            library.query = "nee"
            #expect(library.isSearching)
            library.query = "needle"
            #expect(library.isSearching)
            let deadline = ContinuousClock.now + .seconds(10)
            while library.isSearching, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(!library.isSearching, "the search never landed")
            #expect(library.results.map(\.document.metadata.title) == ["Needle"])
        }
    }
}

/// A temp library folder plus an isolated defaults suite, removed afterwards.
@MainActor
final class TestEnvironment {
    let scratch: URL
    let libraryURL: URL
    let suiteName: String
    let defaults: UserDefaults
    let clock = ManualClock()
    let ids: ULIDGenerator

    init() throws {
        scratch = FileManager.default.temporaryDirectory
            .appending(path: "SegueUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        libraryURL = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        suiteName = "dev.ryandsilva.segue.tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        ids = ULIDGenerator(clock: clock, seed: 7)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: scratch)
    }

    func location() -> LibraryLocation {
        LibraryLocation(defaults: defaults)
    }

    func dependencies(location: LibraryLocation, override: URL?, remember: Bool)
        -> AppDependencies
    {
        AppDependencies(
            fileSystem: LiveFileSystem(),
            clock: clock,
            ids: ids,
            location: location,
            libraryOverride: override,
            rememberLibraryOverride: remember,
            live: liveDependencies(),
        )
    }

    /// Live mode with this environment's defaults, the manual clock, a charger that is
    /// connected and a Shortcut runner that only records.
    func liveDependencies() -> LiveDependencies {
        LiveDependencies(
            settings: LiveSettingsStore(defaults: defaults),
            shortcuts: RecordingShortcutRunner(log: shortcutLog),
            power: FixedPowerSource(onCharger: true),
            scrollClock: clock,
        )
    }

    /// Where `RecordingShortcutRunner` writes.
    var shortcutLog: URL {
        scratch.appending(path: "shortcuts.log", directoryHint: .notDirectory)
    }

    /// The Shortcuts live mode ran, in order.
    func shortcutsRun() throws -> [String] {
        guard FileManager.default.fileExists(atPath: shortcutLog.path) else { return [] }
        return try String(contentsOf: shortcutLog, encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    /// Polls `value` on the main actor until it is non-nil (5 s at most).
    @discardableResult
    func waitFor<T>(_ value: () -> T?) async throws -> T {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if let found = value() {
                return found
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try #require(value(), "timed out waiting")
    }

    func app(override: URL? = nil, remember: Bool = false) -> AppModel {
        AppModel(dependencies: dependencies(
            location: location(),
            override: override,
            remember: remember,
        ))
    }

    /// An app started on the temp library (as the E2E `-SegueLibraryPath` does).
    func openApp() async throws -> AppModel {
        let app = app(override: libraryURL)
        await app.start()
        _ = try #require(app.session)
        return app
    }

    func openLibrary(debounce: Duration = .milliseconds(200)) async throws -> LibraryViewModel {
        let store = LibraryStore(fileSystem: LiveFileSystem(), clock: clock, ids: ids)
        try await store.open(root: LibraryRoot(url: libraryURL))
        let library = LibraryViewModel(store: store, debounce: debounce)
        await library.reload()
        return library
    }

    func write(_ text: String, to relativePath: String) throws {
        try Data(text.utf8).write(to: libraryURL.appending(path: relativePath))
    }

    func read(_ relativePath: String) throws -> String {
        try String(contentsOf: libraryURL.appending(path: relativePath), encoding: .utf8)
    }
}

/// A power source that always reports `onCharger`.
struct FixedPowerSource: PowerSourceReading {
    let onCharger: Bool?

    func isOnCharger() -> Bool? {
        onCharger
    }
}
