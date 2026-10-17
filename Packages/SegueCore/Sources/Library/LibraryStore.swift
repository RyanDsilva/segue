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

    private struct OpenLibrary {
        var files: SongFiles
        var index: SongIndex
        var songs: [SongID: LoadedSong]
    }

    private var library: OpenLibrary?

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
            try library.index.close()
            self.library = nil
        }
        for directory in [root.songsDirectory, root.setlistsDirectory, root.appDirectory] {
            try fileSystem.createDirectory(at: directory)
        }
        let index = try SongIndex.open(at: root.indexDatabase, fileSystem: fileSystem)
        library = OpenLibrary(
            files: SongFiles(root: root, fileSystem: fileSystem, clock: clock, ids: ids),
            index: index,
            songs: [:],
        )
        try refresh()
    }

    /// Creates a new song from ChordPro `source`: writes `songs/<slug>.cho` and its sidecar
    /// (slug from the title, de-duplicated with `-2`, `-3`, ...) and indexes it.
    public func createSong(source: String) throws -> SongRecord {
        let library = try openLibrary()
        let (document, _) = ChordProParser.parse(source)
        let usedSlugs = Set(library.songs.values.map(\.slug))
        let slug = Slug.unique(Slug.make(from: document.metadata.title ?? "")) { candidate in
            usedSlugs.contains(candidate) || library.files.isTaken(slug: candidate)
        }
        let now = SegueJSON.stamp(clock.now())
        let sidecar = Sidecar(id: SongID(ids.next()), createdAt: now, updatedAt: now)
        let song = try library.files.write(source: source, sidecar: sidecar, slug: slug)
        try library.index.upsert(song.indexed)
        self.library?.songs[song.record.id] = song
        return song.record
    }

    /// Replaces the `.cho` contents of song `id` and reindexes it. Throws
    /// `LibraryError.readOnly` for read-only songs. The ID and file name stay stable.
    /// The sidecar is written back at the current schema version with a new `updatedAt`.
    public func updateSong(id: SongID, source: String) throws -> SongRecord {
        let library = try openLibrary()
        guard let existing = library.songs[id] else {
            throw LibraryError.songNotFound(id)
        }
        if let reason = existing.record.readOnly {
            throw LibraryError.readOnly(id, reason)
        }
        var sidecar = existing.record.sidecar
        sidecar.schemaVersion = Sidecar.currentSchemaVersion
        sidecar.updatedAt = SegueJSON.stamp(clock.now())
        let song = try library.files.write(source: source, sidecar: sidecar, slug: existing.slug)
        try library.index.upsert(song.indexed)
        self.library?.songs[id] = song
        return song.record
    }

    /// Replaces the display preferences of song `id` in its sidecar (the `.cho` is not
    /// touched) and returns the updated record. Throws `LibraryError.readOnly` for
    /// read-only songs. Owner: unit C (phase 1).
    public func updateDisplayPrefs(id: SongID, _ prefs: DisplayPrefs) throws -> SongRecord {
        fatalError("unimplemented: unit C")
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

    /// Full-text search over title, artist and lyrics (FTS5), including romanized-Hindi
    /// spelling variants via the normalized index columns. Best matches first.
    ///
    /// Tiers, each appended without duplicates: (1) FTS on the original text, every query
    /// word as a prefix; (2) FTS on the `RomanNormalizer` forms, whole words except a last
    /// word of 4+ letters (prefix, for as-you-type). Only when both find nothing, (3) an
    /// edit-distance fallback (<= 1 per query word of 4+ letters) over normalized titles and
    /// first lines. Within a tier: bm25 (title > artist > lyrics), then title, then ID.
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
        if ordered.isEmpty {
            try append(Self.fuzzyMatches(normalized, in: library.index.fuzzyCandidates()))
        }
        return ordered.compactMap { idString in
            ULID(string: idString).flatMap { library.songs[SongID($0)]?.record }
        }
    }

    /// Rescans the library folder: upserts changed files (mtime/hash), deletes missing ones.
    @discardableResult
    public func refresh() throws -> RefreshSummary {
        let library = try openLibrary()
        let previousByPath = Dictionary(
            library.songs.values.map { ($0.record.relativePath, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var scanned = try library.files.songSlugs().map { slug in
            try library.files.load(
                slug: slug,
                previous: previousByPath[SongFiles.relativePath(slug: slug)],
            )
        }
        scanned = try resolveDuplicateIDs(scanned, previous: library.songs, files: library.files)

        let rows = try library.index.rows()
        var summary = RefreshSummary()
        var songs: [SongID: LoadedSong] = [:]
        for song in scanned {
            songs[song.record.id] = song
            guard let row = rows[song.record.id.description] else {
                try library.index.upsert(song.indexed)
                summary.added += 1
                continue
            }
            if row.path != song.record.relativePath || row.contentHash != song.contentHash {
                try library.index.upsert(song.indexed)
                summary.updated += 1
            } else if row.mtime != song.mtime {
                try library.index.touch(id: row.id, mtime: song.mtime)
            }
        }
        let live = Set(songs.keys.map(\.description))
        let removed = rows.keys.filter { !live.contains($0) }
        try library.index.delete(ids: removed)
        summary.removed = removed.count
        self.library?.songs = songs
        return summary
    }

    /// Deletes the index and re-creates it from the files on disk.
    public func rebuildIndex() throws {
        let library = try openLibrary()
        try library.index.close()
        try SongIndex.deleteFiles(at: library.files.root.indexDatabase, fileSystem: fileSystem)
        let index = try SongIndex.open(at: library.files.root.indexDatabase, fileSystem: fileSystem)
        self.library = OpenLibrary(files: library.files, index: index, songs: [:])
        try refresh()
    }

    // MARK: - Private

    private func openLibrary() throws -> OpenLibrary {
        guard let library else { throw LibraryError.notOpen }
        return library
    }

    /// When several files carry the same ID (e.g. a Finder-duplicated song + sidecar), the
    /// file that already held the ID keeps it (else the first by path); the others get new
    /// IDs, persisted in their sidecar when it is writable.
    private func resolveDuplicateIDs(
        _ songs: [LoadedSong],
        previous: [SongID: LoadedSong],
        files: SongFiles,
    ) throws -> [LoadedSong] {
        let groups = Dictionary(grouping: songs.indices, by: { songs[$0].record.id })
        var result = songs
        // Sorted so new IDs are handed out in a deterministic order.
        for (id, indices) in groups.sorted(by: { $0.key < $1.key }) where indices.count > 1 {
            let previousPath = previous[id]?.record.relativePath
            let keeper = indices.first { songs[$0].record.relativePath == previousPath }
                ?? indices[0]
            for index in indices where index != keeper {
                result[index] = try files.reassignID(songs[index])
            }
        }
        return result
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
