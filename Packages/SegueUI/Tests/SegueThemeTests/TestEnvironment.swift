import AppKit
import Foundation
import Library
@testable import SegueUI
import Setlists
import Shows
import Support
import Testing

/// A temp library folder plus an isolated defaults suite, removed afterwards.
@MainActor
final class TestEnvironment {
    let scratch: URL
    let libraryURL: URL
    let suiteName: String
    let defaults: UserDefaults
    let clock = ManualClock()
    let ids: ULIDGenerator
    /// The file system apps made by this environment use (a failing one in some tests).
    /// Deleted items go to `trashURL`, never the user's Trash.
    var fileSystem: any FileSystem
    /// `bindings.json` for live mode; nil uses the default keys.
    var bindingsURL: URL?
    /// The real library lock by default; `.unlocked` for tests that run several in-process
    /// app instances on this library on purpose.
    var libraryLock: LibraryLockPolicy = .exclusive

    init() throws {
        scratch = FileManager.default.temporaryDirectory
            .appending(path: "SegueUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        libraryURL = scratch.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        suiteName = "dev.ryandsilva.segue.tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        ids = ULIDGenerator(clock: clock, seed: 7)
        fileSystem = LiveFileSystem(trash: .directory(
            scratch.appending(path: "Trash", directoryHint: .isDirectory),
        ))
    }

    /// The stand-in Trash folder.
    var trashURL: URL {
        scratch.appending(path: "Trash", directoryHint: .isDirectory)
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: libraryURL.appending(path: relativePath).path)
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
            fileSystem: fileSystem,
            clock: clock,
            ids: ids,
            location: location,
            libraryOverride: override,
            rememberLibraryOverride: remember,
            live: liveDependencies(),
            libraryLock: libraryLock,
        )
    }

    /// Live mode with this environment's defaults, the manual clock, a charger that is
    /// connected and a Shortcut runner that only records. The Gig Mode Shortcuts are set up
    /// as a configured user would have them (they are off by default, R18).
    func liveDependencies() -> LiveDependencies {
        let settings = LiveSettingsStore(defaults: defaults)
        if settings.settings.startShortcut == nil, settings.settings.endShortcut == nil {
            settings.settings.startShortcut = LiveSettings.suggestedStartShortcut
            settings.settings.endShortcut = LiveSettings.suggestedEndShortcut
        }
        return LiveDependencies(
            settings: settings,
            shortcuts: RecordingShortcutRunner(log: shortcutLog),
            power: FixedPowerSource(onCharger: true),
            scrollClock: clock,
            bindingsURL: bindingsURL,
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

    /// Polls `value` on the main actor until it is non-nil (a 30 s hang backstop, not
    /// pacing; await the real work where possible).
    @discardableResult
    func waitFor<T>(_ value: () -> T?) async throws -> T {
        let deadline = ContinuousClock.now + .seconds(30)
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
        let store = LibraryStore(
            fileSystem: LiveFileSystem(trash: .directory(trashURL)),
            clock: clock,
            ids: ids,
        )
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
