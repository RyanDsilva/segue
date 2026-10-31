import Foundation

/// The library folder and the fixed layout beneath it:
///
/// ```
/// <root>/
///   songs/<slug>.cho
///   songs/<slug>.segue.json
///   setlists/<slug>.setlist.json
///   shows/<ulid>.show.json            (phase 2: shows and the gig log)
///   timings/<ulid>.rehearsal.json     (phase 2: rehearse-setlist timings)
///   filters/<slug>.filter.json        (phase 3: saved smart filters)
///   .segue/index.sqlite
///   .segue/library.lock
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

    /// `<root>/shows`: `.show.json` files, one per show (a finished show is a gig log entry).
    public var showsDirectory: URL {
        url.appending(path: "shows", directoryHint: .isDirectory)
    }

    /// `<root>/timings`: song timings from rehearse-setlist runs (`.rehearsal.json`).
    public var timingsDirectory: URL {
        url.appending(path: "timings", directoryHint: .isDirectory)
    }

    /// `<root>/filters`: saved smart filters (`.filter.json`), phase 3 (R72).
    public var filtersDirectory: URL {
        url.appending(path: "filters", directoryHint: .isDirectory)
    }

    /// `<root>/.segue`: app-private, rebuildable state.
    public var appDirectory: URL {
        url.appending(path: ".segue", directoryHint: .isDirectory)
    }

    /// `<root>/.segue/library.lock`: held with `flock` by the copy of Segue that has the
    /// library open (`LibraryLock`), so two copies never open the same library at once.
    public var lockURL: URL {
        appDirectory.appending(path: "library.lock", directoryHint: .notDirectory)
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
    /// Filename suffix of show files (`<ulid>.show.json`).
    public static let showSuffix = ".show.json"
    /// Filename suffix of rehearsal timing files (`<ulid>.rehearsal.json`).
    public static let rehearsalSuffix = ".rehearsal.json"
    /// Filename suffix of smart filter files (`<slug>.filter.json`).
    public static let filterSuffix = ".filter.json"
}
