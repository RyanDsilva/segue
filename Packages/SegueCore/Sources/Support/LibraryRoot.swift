import Foundation

/// The library folder and the fixed layout beneath it:
///
/// ```
/// <root>/
///   songs/<slug>.cho
///   songs/<slug>.segue.json
///   setlists/<slug>.setlist.json
///   .segue/index.sqlite
/// ```
///
/// A plain value: security-scoped bookmark access is handled by the caller (Library/App)
/// before a `LibraryRoot` is handed to the stores. Tests point it at a temp directory.
public struct LibraryRoot: Sendable, Hashable {
    /// The library folder chosen by the user (or a temp directory in tests).
    public let url: URL

    public init(url: URL) {
        self.url = url.standardizedFileURL
    }

    /// `<root>/songs`: `.cho` files and their `.segue.json` sidecars.
    public var songsDirectory: URL {
        url.appending(path: "songs", directoryHint: .isDirectory)
    }

    /// `<root>/setlists`: `.setlist.json` files.
    public var setlistsDirectory: URL {
        url.appending(path: "setlists", directoryHint: .isDirectory)
    }

    /// `<root>/.segue`: app-private, rebuildable state.
    public var appDirectory: URL {
        url.appending(path: ".segue", directoryHint: .isDirectory)
    }

    /// `<root>/.segue/index.sqlite`: the rebuildable GRDB index. Safe to delete.
    public var indexDatabase: URL {
        appDirectory.appending(path: "index.sqlite", directoryHint: .notDirectory)
    }

    /// Path extension of canonical song files.
    public static let songExtension = "cho"
    /// Filename suffix of song sidecars (`<slug>.segue.json`).
    public static let sidecarSuffix = ".segue.json"
    /// Filename suffix of setlist files (`<slug>.setlist.json`).
    public static let setlistSuffix = ".setlist.json"
}
