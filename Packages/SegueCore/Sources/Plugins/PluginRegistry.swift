import Synchronization

// Plugin seam for restricted, personal-build-only modules (phase 5). Core defines the
// protocols; `SeguePersonalModules` implements them. Core never knows that package exists.
// The capability protocols are intentionally empty beyond identity in phase 0; phase 5
// adds their real requirements.

/// Common identity of every plugin.
public protocol Plugin: Sendable {
    /// Stable reverse-DNS identifier, e.g. `dev.ryandsilva.segue.lrclib`.
    var id: String { get }
    /// Name shown in the UI.
    var displayName: String { get }
}

/// Turns external input (URL, file, page) into a song. Phase 5.
public protocol SongImporter: Plugin {}

/// Analyzes audio (transcription, key/BPM, sections, chords). Phase 5.
public protocol AudioAnalyzer: Plugin {}

/// Looks up lyrics from an external source (e.g. LRCLIB). Phase 5.
public protocol LyricsSource: Plugin {}

/// A bundle of plugins that registers itself, e.g. `SeguePersonalModules`.
public protocol PluginModule {
    /// Registers this module's plugins.
    static func register(into registry: PluginRegistry)
}

/// The set of available plugins. Populated once at app launch via `registerAll(_:)`.
public final class PluginRegistry: Sendable {
    private struct Contents {
        var songImporters: [any SongImporter] = []
        var audioAnalyzers: [any AudioAnalyzer] = []
        var lyricsSources: [any LyricsSource] = []
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

    public func register(_ analyzer: any AudioAnalyzer) {
        contents.withLock { $0.audioAnalyzers.append(analyzer) }
    }

    public func register(_ source: any LyricsSource) {
        contents.withLock { $0.lyricsSources.append(source) }
    }

    public var songImporters: [any SongImporter] {
        contents.withLock { $0.songImporters }
    }

    public var audioAnalyzers: [any AudioAnalyzer] {
        contents.withLock { $0.audioAnalyzers }
    }

    public var lyricsSources: [any LyricsSource] {
        contents.withLock { $0.lyricsSources }
    }
}
