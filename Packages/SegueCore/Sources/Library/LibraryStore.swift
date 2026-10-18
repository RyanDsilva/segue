import ChordPro
import Foundation
import Support

/// Errors surfaced by `LibraryStore`. Implementers may add cases.
public enum LibraryError: Error, Equatable {
    /// An operation ran before `open(root:)` succeeded.
    case notOpen
    /// No song with this ID is in the library.
    case songNotFound(SongID)
    /// The song is read-only and cannot be edited.
    case readOnly(SongID, ReadOnlyReason)
    /// The song's files changed on disk since the revision the edit was based on; nothing
    /// was written. The caller decides: reload, overwrite (`overwriteSong`) or save a copy.
    case conflict(SongID, SongConflict)
}

/// How a song's files changed under an edit (see `LibraryError.conflict`).
public enum SongConflict: Sendable, Equatable {
    /// The `.cho` was edited outside Segue.
    case sourceChanged
    /// The `.cho` was deleted (or renamed) outside Segue.
    case deleted
    /// The sidecar changed into something that can't be merged (unreadable, newer schema
    /// or another song's ID).
    case metadataChanged
}

/// A file under `songs/` that could not be loaded (or given a sidecar). Reported, never
/// deleted; the rest of the library still opens.
public struct LibraryLoadIssue: Sendable, Equatable {
    /// Path relative to the library root.
    public var relativePath: String
    public var message: String

    public init(relativePath: String, message: String) {
        self.relativePath = relativePath
        self.message = message
    }
}

/// Outcome of a `refresh()` scan, for UI feedback and tests.
public struct RefreshSummary: Sendable, Equatable {
    public var added: Int
    public var updated: Int
    public var removed: Int

    public init(added: Int = 0, updated: Int = 0, removed: Int = 0) {
        self.added = added
        self.updated = updated
        self.removed = removed
    }
}

/// The song library: `.cho` files + sidecars on disk (canonical) and a rebuildable GRDB
/// index at `.segue/index.sqlite` (a projection; only this store writes to it).
///
/// All IO goes through the injected `FileSystem`; timestamps and IDs come from the injected
/// `Clock` and `IDGenerator`, so integration tests are reproducible.
/// Implementers may add methods (e.g. delete) as later phases need them.
public actor LibraryStore {
    private let fileSystem: any FileSystem
    private let clock: any Clock
    private let ids: any IDGenerator

    struct OpenLibrary {
        var files: SongFiles
        var index: SongIndex
        var songs: [SongID: LoadedSong]
    }

    /// Internal (not private) for the phase 2 extensions in `LibraryStore+Phase2.swift`.
    var library: OpenLibrary?

    /// The play projection as last handed in (`replacePlays` / `replaceAllPlays`), keyed by
    /// show. Re-applied whenever the index is re-created (`rebuildIndex()`, or `open` of the
    /// same root after a version bump), so "last played" survives a rebuild.
    var plays: [ULID: [PlayRecord]] = [:]

    /// Files the last scan could not load, by path. Shown in the UI; never fatal.
    public internal(set) var loadIssues: [LibraryLoadIssue] = []

    public init(fileSystem: any FileSystem, clock: any Clock, ids: any IDGenerator) {
        self.fileSystem = fileSystem
        self.clock = clock
        self.ids = ids
    }

    /// The open library's root, or nil before `open(root:)`.
    public var root: LibraryRoot? {
        library?.files.root
    }

    /// Opens (creating if needed) the library at `root`: ensures the folder layout, opens or
    /// rebuilds the index, then scans files like `refresh()`. Orphan `.cho` files get a
    /// sidecar.
    public func open(root: LibraryRoot) throws {
        if let library {
            if library.files.root != root {
                plays = [:] // another library's history
            }
            try library.index.close()
            self.library = nil
        }
        loadIssues = []
        for directory in [root.songsDirectory, root.setlistsDirectory, root.appDirectory] {
            try fileSystem.createDirectory(at: directory)
        }
        let index = try SongIndex.open(at: root.indexDatabase, fileSystem: fileSystem)
        library = OpenLibrary(
            files: SongFiles(root: root, fileSystem: fileSystem, clock: clock, ids: ids),
            index: index,
            songs: [:],
        )
        try reapplyPlays()
        try refresh()
    }

    /// Creates a new song from ChordPro `source`: writes `songs/<slug>.cho` and its sidecar
    /// (slug from the title, de-duplicated with `-2`, `-3`, ...) and indexes it.
    public func createSong(source: String) throws -> SongRecord {
        try createSong(source: source) { _ in }
    }

    /// `createSong(source:)` with sidecar fields set before the first write, so the song's
    /// metadata lands in the same write as its files (the seeder relies on this: a seeded
    /// song never exists without its seed tag).
    func createSong(source: String, configure: (inout Sidecar) -> Void) throws -> SongRecord {
        let library = try openLibrary()
        let (document, _) = ChordProParser.parse(source)
        let usedSlugs = Set(library.songs.values.map(\.slug))
        let slug = Slug.unique(Slug.make(from: document.metadata.title ?? "")) { candidate in
            usedSlugs.contains(candidate) || library.files.isTaken(slug: candidate)
        }
        let now = SegueJSON.stamp(clock.now())
        var sidecar = Sidecar(id: SongID(ids.next()), createdAt: now, updatedAt: now)
        configure(&sidecar)
        let song = try library.files.write(source: source, sidecar: sidecar, slug: slug)
        try library.index.upsert(song.indexed)
        self.library?.songs[song.record.id] = song
        return song.record
    }

    /// Replaces the `.cho` contents of song `id` and reindexes it. The ID and file name stay
    /// stable; the sidecar is written back at the current schema version with a new
    /// `updatedAt`.
    ///
    /// The edit is checked against `revision` (default: the revision this store last
    /// loaded): if the `.cho` on disk no longer hashes to it, nothing is written and
    /// `LibraryError.conflict` is thrown. A sidecar changed on disk is merged (its metadata
    /// is kept) when it is still an editable sidecar of this song, else it is a conflict.
    /// Throws `LibraryError.readOnly` for read-only songs.
    public func updateSong(
        id: SongID,
        source: String,
        basedOn revision: SongRevision? = nil,
    ) throws -> SongRecord {
        let library = try openLibrary()
        let existing = try editableSong(id, in: library)
        let expected = revision ?? existing.record.revision
        guard let onDisk = try library.files.currentSource(slug: existing.slug) else {
            throw LibraryError.conflict(id, .deleted)
        }
        guard SongFiles.hash(onDisk) == expected.contentHash else {
            throw LibraryError.conflict(id, .sourceChanged)
        }
        let sidecar = try sidecarToWrite(for: existing, files: library.files)
        return try write(source: source, sidecar: sidecar, over: existing, in: library)
    }

    /// Writes `source` for song `id` whatever the `.cho` on disk now holds: the user chose
    /// "Overwrite" after a `.sourceChanged` conflict. Sidecar changes are still merged, or
    /// refused as `.metadataChanged`.
    public func overwriteSong(id: SongID, source: String) throws -> SongRecord {
        let library = try openLibrary()
        let existing = try editableSong(id, in: library)
        let sidecar = try sidecarToWrite(for: existing, files: library.files)
        return try write(source: source, sidecar: sidecar, over: existing, in: library)
    }

    /// Replaces the display preferences of song `id` in its sidecar (the `.cho` is not
    /// touched) and returns the updated record. Throws `LibraryError.readOnly` for
    /// read-only songs. Owner: unit C (phase 1).
    public func updateDisplayPrefs(id: SongID, _ prefs: DisplayPrefs) throws -> SongRecord {
        let library = try openLibrary()
        var existing = try editableSong(id, in: library)
        existing.record.sidecar = try sidecarToWrite(for: existing, files: library.files)
        let song = try library.files.writingDisplayPrefs(prefs, of: existing)
        self.library?.songs[id] = song
        return song.record
    }

    /// The song with `id`, or nil if absent.
    public func song(id: SongID) throws -> SongRecord? {
        try openLibrary().songs[id]?.record
    }

    /// Every song, sorted by title (case-insensitive; file slug when untitled), then ID.
    public func allSongs() throws -> [SongRecord] {
        try openLibrary().songs.values
            .sorted { lhs, rhs in
                switch lhs.sortTitle.caseInsensitiveCompare(rhs.sortTitle) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: lhs.record.id < rhs.record.id
                }
            }
            .map(\.record)
    }

    /// Full-text search over title, artist, lyrics and tags (FTS5), including romanized-Hindi
    /// spelling variants via the normalized index columns. Best matches first.
    ///
    /// Tiers, each appended without duplicates: (1) FTS on the original text, every query
    /// word as a prefix; (2) FTS on the `RomanNormalizer` forms, whole words except a last
    /// word of 4+ letters (prefix, for as-you-type); (3) the same over the loose forms
    /// (`RomanNormalizer.loose`: `dewana` = `deewana` = `diwana`), ranked after the exact
    /// spellings. Only when all three find nothing, (4) an edit-distance fallback (<= 1 per query
    /// word of 4+ letters) over normalized titles and
    /// first lines. Within a tier: bm25 (title > artist = tags > lyrics), then title, then ID.
    /// An empty query returns `allSongs()`.
    public func search(query: String) throws -> [SongRecord] {
        let library = try openLibrary()
        let words = RomanNormalizer.words(query)
        guard !words.isEmpty else { return try allSongs() }
        let normalized = words.map(RomanNormalizer.normalizeWord)

        var ordered: [String] = []
        var seen: Set<String> = []
        func append(_ matches: [String]) {
            for id in matches where seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        try append(library.index.matchOriginals(tokens: words))
        try append(library.index.matchNormalized(tokens: normalized))
        try append(library.index.matchLoose(tokens: normalized.map(RomanNormalizer.looseWord)))
        if ordered.isEmpty {
            try append(Self.fuzzyMatches(normalized, in: library.index.fuzzyCandidates()))
        }
        return ordered.compactMap { idString in
            ULID(string: idString).flatMap { library.songs[SongID($0)]?.record }
        }
    }

    /// Rescans the library folder: upserts changed files, deletes missing ones. Files whose
    /// modification time and size are unchanged are not read again; the index is updated in
    /// one transaction. A file that can't be read is reported in `loadIssues` (keeping what
    /// was loaded before, if anything) instead of failing the scan.
    @discardableResult
    public func refresh() throws -> RefreshSummary {
        let library = try openLibrary()
        let previousByPath = Dictionary(
            library.songs.values.map { ($0.record.relativePath, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var (scanned, issues) = try collectScan(of: library.files, previous: previousByPath)
        scanned = library.files.resolveDuplicateIDs(
            scanned,
            previousPaths: library.songs.mapValues(\.record.relativePath),
            issues: &issues,
        )

        let rows = try library.index.rows()
        var summary = RefreshSummary()
        var changes = IndexChanges()
        var songs: [SongID: LoadedSong] = [:]
        for song in scanned {
            songs[song.record.id] = song
            guard let row = rows[song.record.id.description] else {
                changes.upserts.append(song.indexed)
                summary.added += 1
                continue
            }
            if row.path != song.record.relativePath || row.contentHash != song.contentHash
                || row.tags != song.indexedTags
            {
                changes.upserts.append(song.indexed)
                summary.updated += 1
            } else if row.mtime != song.mtime {
                changes.touches[row.id] = song.mtime
            }
        }
        let live = Set(songs.keys.map(\.description))
        changes.deletes = rows.keys.filter { !live.contains($0) }.sorted()
        summary.removed = changes.deletes.count
        try library.index.apply(changes)
        self.library?.songs = songs
        loadIssues = issues.sorted { $0.relativePath < $1.relativePath }
        return summary
    }

    /// Deletes the index and re-creates it from the files on disk. If that fails, the
    /// existing index is reopened (or re-created) so the library stays usable, and the error
    /// is rethrown.
    public func rebuildIndex() throws {
        let library = try openLibrary()
        let url = library.files.root.indexDatabase
        try library.index.close()
        do {
            try SongIndex.deleteFiles(at: url, fileSystem: fileSystem)
            let index = try SongIndex.open(at: url, fileSystem: fileSystem)
            self.library = OpenLibrary(files: library.files, index: index, songs: [:])
        } catch {
            if let reopened = try? SongIndex.open(at: url, fileSystem: fileSystem) {
                self.library?.index = reopened
                // A partly deleted index reopens empty: fill it again from the files.
                try? reapplyPlays()
                _ = try? refresh()
            } else {
                // No usable index at all: fail closed (`notOpen`) rather than keep a closed
                // pool around.
                self.library = nil
            }
            throw error
        }
        try reapplyPlays()
        try refresh()
    }

    // MARK: - Private

    func openLibrary() throws -> OpenLibrary {
        guard let library else { throw LibraryError.notOpen }
        return library
    }

    /// Scans `songs/` and adopts orphans; unreadable files become issues (keeping what was
    /// loaded before for them, if anything).
    private func collectScan(
        of files: SongFiles,
        previous previousByPath: [String: LoadedSong],
    ) throws -> ([LoadedSong], [LibraryLoadIssue]) {
        var issues: [LibraryLoadIssue] = []
        var scanned: [LoadedSong] = []
        for result in try files.scan(files.songSlugs(), previous: previousByPath) {
            switch result {
            case let .loaded(song):
                scanned.append(song)
            case let .orphan(song):
                let previous = previousByPath[song.record.relativePath]
                let (adopted, problem) = files.adoptOrphan(song, previous: previous)
                scanned.append(adopted)
                if let problem {
                    issues.append(LibraryLoadIssue(
                        relativePath: SongFiles.sidecarRelativePath(slug: song.slug),
                        message: problem,
                    ))
                }
            case let .failed(slug, message):
                let path = SongFiles.relativePath(slug: slug)
                issues.append(LibraryLoadIssue(relativePath: path, message: message))
                if let previous = previousByPath[path] {
                    scanned.append(previous)
                }
            }
        }
        return (scanned, issues)
    }

    func editableSong(_ id: SongID, in library: OpenLibrary) throws -> LoadedSong {
        guard let existing = library.songs[id] else {
            throw LibraryError.songNotFound(id)
        }
        if let reason = existing.record.readOnly {
            throw LibraryError.readOnly(id, reason)
        }
        return existing
    }

    /// The sidecar to write with a new source: the one in memory while the file on disk is
    /// unchanged; the file's own when it changed but is still an editable sidecar of this
    /// song (so metadata edited elsewhere survives); ours again when it was deleted.
    func sidecarToWrite(for existing: LoadedSong, files: SongFiles) throws -> Sidecar {
        guard let data = try files.currentSidecar(slug: existing.slug),
              SongFiles.hash(data) != existing.record.revision.sidecarHash
        else {
            return existing.record.sidecar
        }
        let decoded = files.decodeSidecar(data, slug: existing.slug, previous: existing)
        guard decoded.readOnly == nil, decoded.sidecar.id == existing.record.id else {
            throw LibraryError.conflict(existing.record.id, .metadataChanged)
        }
        return decoded.sidecar
    }

    private func write(
        source: String,
        sidecar: Sidecar,
        over existing: LoadedSong,
        in library: OpenLibrary,
    ) throws -> SongRecord {
        var sidecar = sidecar
        sidecar.schemaVersion = Sidecar.currentSchemaVersion
        sidecar.updatedAt = SegueJSON.stamp(clock.now())
        let song = try library.files.write(source: source, sidecar: sidecar, slug: existing.slug)
        try library.index.upsert(song.indexed)
        self.library?.songs[song.record.id] = song
        return song.record
    }

    private static func fuzzyMatches(
        _ queryWords: [String],
        in candidates: [FuzzyCandidate],
    ) -> [String] {
        candidates.filter { candidate in
            queryWords.allSatisfy { queryWord in
                candidate.words.contains { word in
                    word.hasPrefix(queryWord)
                        || (queryWord.count >= 4
                            && RomanNormalizer.editDistance(queryWord, word, limit: 1) <= 1)
                }
            }
        }
        .map(\.id)
    }
}
