import Synchronization

// Plugin seam for restricted, personal-build-only modules. Core defines the protocols;
// `SeguePersonalModules` implements them. Core never knows that package exists. The two
// capabilities are web page import and song search (P9-4 spec 4.2; value types in
// `PluginTypes.swift`). Every call is cancellable: `Task` cancellation maps to `.cancelled`.

/// Common identity of every plugin.
public protocol Plugin: Sendable {
    /// Stable reverse-DNS identifier, e.g. `dev.ryandsilva.segue.lrclib`.
    var id: String { get }
    /// Name shown in the UI.
    var displayName: String { get }
}

/// Turns a page address or a saved page file into text the ingest pipeline reads.
public protocol SongImporter: Plugin {
    /// Cheap and offline: whether this importer takes the input, and which reader it will try.
    func accepts(_ input: ImportInput) -> ReaderKind?
    func importSong(_ input: ImportInput) async throws(ImportFailure) -> ImportedSong
}

/// One searchable source; the results show grouped by `group`, in its fixed order (R182).
public protocol SongSearchSource: Plugin {
    var group: SearchGroup { get }
    func search(_ query: SongQuery) async throws(ImportFailure) -> [SearchCandidate]
    /// The chart or lyrics for one candidate, for the preview pane and then the review.
    func song(for candidate: SearchCandidate) async throws(ImportFailure) -> ImportedSong
}

/// A bundle of plugins that registers itself, e.g. `SeguePersonalModules`.
public protocol PluginModule {
    /// Registers this module's plugins.
    static func register(into registry: PluginRegistry)
}

/// The set of available plugins. Populated once at app launch via `registerAll(_:)`.
public final class PluginRegistry: Sendable {
    private struct Contents {
        var songImporters: [any SongImporter] = []
        var songSearchSources: [any SongSearchSource] = []
    }

    private let contents = Mutex(Contents())

    public init() {}

    /// Registers every module in `modules`. The app passes the personal module only in the
    /// Personal build (`#if SEGUE_PERSONAL`); the App Store build passes none.
    public func registerAll(_ modules: [any PluginModule.Type]) {
        for module in modules {
            module.register(into: self)
        }
    }

    public func register(_ importer: any SongImporter) {
        contents.withLock { $0.songImporters.append(importer) }
    }

    public func register(_ source: any SongSearchSource) {
        contents.withLock { $0.songSearchSources.append(source) }
    }

    public var songImporters: [any SongImporter] {
        contents.withLock { $0.songImporters }
    }

    /// In the fixed group order (R182), whatever order they registered in.
    public var songSearchSources: [any SongSearchSource] {
        contents.withLock { $0.songSearchSources }
            .enumerated()
            .sorted { lhs, rhs in
                (lhs.element.group.rawValue, lhs.offset) < (rhs.element.group.rawValue, rhs.offset)
            }
            .map(\.element)
    }
}
