import Foundation
import GRDB
import Support

/// One song as the indexer projects it into SQLite.
struct IndexedSong: Sendable, Equatable {
    var id: String
    var path: String
    var title: String
    var artist: String
    var key: String?
    var tempo: Double?
    var mtime: Double
    var contentHash: String
    var firstLine: String
    var lyrics: String
    /// The song's tags (normalized, see `SongMetadata.normalizedTags`), one per line.
    var tags: String
    /// "Movie / Album": the first `{album}`, "" when none (P8-8 section 4.3).
    var album: String = ""
}

/// What the indexer needs to decide whether a file changed.
struct IndexRow: Sendable, Equatable {
    var id: String
    var path: String
    var mtime: Double
    var contentHash: String
    /// As `IndexedSong.tags`: sidecar tag edits change the row too.
    var tags: String
}

/// Index writes collected during one scan, applied in one transaction.
struct IndexChanges: Sendable {
    var upserts: [IndexedSong] = []
    /// New mtimes for unchanged files, keyed by song ID.
    var touches: [String: Double] = [:]
    var deletes: [String] = []

    var isEmpty: Bool {
        upserts.isEmpty && touches.isEmpty && deletes.isEmpty
    }
}

/// Normalized title and first line of one song, for the edit-distance fallback.
struct FuzzyCandidate: Sendable {
    var id: String
    var words: [String]
}

/// The rebuildable search index at `.segue/index.sqlite` (GRDB `DatabasePool`, WAL).
///
/// A projection of the files on disk: no data migrations. When `version` changes (schema or
/// `RomanNormalizer` rules), or the file cannot be opened, the database is deleted and
/// re-created empty; the caller then re-indexes from files. Only `LibraryStore` writes here.
struct SongIndex: Sendable {
    /// Bump on any change to the tables below.
    ///
    /// History: 1 = phase 0 (songs + FTS); 2 = phase 2 (tags in `songs` and FTS, the
    /// `plays` projection); 3 = the loose (vowel quality) FTS columns; 4 = the album
    /// (Movie / Album) columns, P8-8.
    static let schemaVersion = 4

    /// Stored in `PRAGMA user_version`; covers both schema and normalization rules.
    static var version: Int {
        schemaVersion * 1000 + RomanNormalizer.version
    }

    /// FTS5 columns, in table order (`song_id` is unindexed).
    private static let originalColumns = "{title artist lyrics tags album}"
    private static let normalizedColumns =
        "{norm_title norm_artist norm_lyrics norm_tags norm_album}"
    private static let looseColumns =
        "{loose_title loose_artist loose_lyrics loose_tags loose_album}"
    /// bm25 weights per FTS column: song_id, title, artist, lyrics, tags, album, then norm_*
    /// and loose_* in the same order.
    private static let rankExpression =
        "bm25(songs_fts, 0, 10, 5, 1, 5, 5, 10, 5, 1, 5, 5, 10, 5, 1, 5, 5)"

    let pool: DatabasePool

    /// Opens the index at `url`, re-creating it empty when missing, stale or unreadable.
    static func open(at url: URL, fileSystem: any FileSystem) throws -> Self {
        do {
            if let index = try openExisting(at: url, fileSystem: fileSystem) {
                return index
            }
        } catch {
            // Corrupt or unreadable: it is only a projection, so start over.
        }
        try deleteFiles(at: url, fileSystem: fileSystem)
        return try create(at: url)
    }

    /// Deletes the database and its WAL/SHM side files.
    static func deleteFiles(at url: URL, fileSystem: any FileSystem) throws {
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path(percentEncoded: false) + suffix)
            if fileSystem.fileExists(at: file) {
                try fileSystem.removeItem(at: file)
            }
        }
    }

    /// Opens an existing database if its version matches; nil if missing or stale.
    private static func openExisting(
        at url: URL,
        fileSystem: any FileSystem,
    ) throws -> Self? {
        guard fileSystem.fileExists(at: url) else { return nil }
        let pool = try DatabasePool(path: url.path(percentEncoded: false))
        let found = try pool.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
        guard found == version else {
            try pool.close()
            return nil
        }
        return Self(pool: pool)
    }

    private static func create(at url: URL) throws -> Self {
        let pool = try DatabasePool(path: url.path(percentEncoded: false))
        try pool.write { db in
            try db.execute(sql: """
            CREATE TABLE songs (
                id TEXT PRIMARY KEY NOT NULL,
                path TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                key TEXT,
                tempo REAL,
                mtime REAL NOT NULL,
                content_hash TEXT NOT NULL,
                first_line TEXT NOT NULL,
                tags TEXT NOT NULL,
                norm_title TEXT NOT NULL,
                norm_artist TEXT NOT NULL,
                norm_first_line TEXT NOT NULL
            );
            CREATE VIRTUAL TABLE songs_fts USING fts5(
                song_id UNINDEXED,
                title, artist, lyrics, tags, album,
                norm_title, norm_artist, norm_lyrics, norm_tags, norm_album,
                loose_title, loose_artist, loose_lyrics, loose_tags, loose_album,
                tokenize = 'unicode61 remove_diacritics 2'
            );
            CREATE TABLE plays (
                show_id TEXT NOT NULL,
                song_id TEXT NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                from_request INTEGER NOT NULL
            );
            CREATE INDEX plays_by_show ON plays (show_id);
            CREATE INDEX plays_by_song ON plays (song_id, started_at);
            PRAGMA user_version = \(version);
            """)
        }
        return Self(pool: pool)
    }

    /// Closes the pool (before deleting the files).
    func close() throws {
        try pool.close()
    }

    /// Change-detection rows, keyed by song ID.
    func rows() throws -> [String: IndexRow] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, path, mtime, content_hash, tags FROM songs",
            )
            var result: [String: IndexRow] = [:]
            for row in rows {
                let indexRow = IndexRow(
                    id: row["id"],
                    path: row["path"],
                    mtime: row["mtime"],
                    contentHash: row["content_hash"],
                    tags: row["tags"],
                )
                result[indexRow.id] = indexRow
            }
            return result
        }
    }

    /// Inserts or replaces `song` (any row holding the same ID or path is replaced).
    func upsert(_ song: IndexedSong) throws {
        try apply(IndexChanges(upserts: [song]))
    }

    /// Applies every change of one scan in a single write transaction (one commit, one
    /// fsync), deletions first so a re-pathed song never collides with its stale row.
    func apply(_ changes: IndexChanges) throws {
        guard !changes.isEmpty else { return }
        try pool.write { db in
            for id in changes.deletes {
                try Self.delete(id: id, in: db)
            }
            for song in changes.upserts {
                try Self.upsert(song, in: db)
            }
            for (id, mtime) in changes.touches {
                try db.execute(
                    sql: "UPDATE songs SET mtime = ? WHERE id = ?",
                    arguments: [mtime, id],
                )
            }
        }
    }

    private static func upsert(_ song: IndexedSong, in db: Database) throws {
        let stale = try String.fetchAll(
            db,
            sql: "SELECT id FROM songs WHERE id = ? OR path = ?",
            arguments: [song.id, song.path],
        )
        for id in stale {
            try delete(id: id, in: db)
        }
        try db.execute(
            sql: """
            INSERT INTO songs (id, path, title, artist, key, tempo, mtime, content_hash,
                               first_line, tags, norm_title, norm_artist, norm_first_line)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                song.id, song.path, song.title, song.artist, song.key, song.tempo,
                song.mtime, song.contentHash, song.firstLine, song.tags,
                RomanNormalizer.normalize(song.title),
                RomanNormalizer.normalize(song.artist),
                RomanNormalizer.normalize(song.firstLine),
            ],
        )
        try db.execute(
            sql: """
            INSERT INTO songs_fts (song_id, title, artist, lyrics, tags, album,
                                   norm_title, norm_artist, norm_lyrics, norm_tags, norm_album,
                                   loose_title, loose_artist, loose_lyrics, loose_tags,
                                   loose_album)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                song.id, song.title, song.artist, song.lyrics, song.tags, song.album,
                RomanNormalizer.normalize(song.title),
                RomanNormalizer.normalize(song.artist),
                RomanNormalizer.normalize(song.lyrics),
                RomanNormalizer.normalize(song.tags),
                RomanNormalizer.normalize(song.album),
                RomanNormalizer.loose(song.title),
                RomanNormalizer.loose(song.artist),
                RomanNormalizer.loose(song.lyrics),
                RomanNormalizer.loose(song.tags),
                RomanNormalizer.loose(song.album),
            ],
        )
    }

    private static func delete(id: String, in db: Database) throws {
        try db.execute(sql: "DELETE FROM songs_fts WHERE song_id = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM songs WHERE id = ?", arguments: [id])
    }

    /// Song IDs where every token prefix-matches one of the original columns, best first.
    func matchOriginals(tokens: [String]) throws -> [String] {
        try match(columns: Self.originalColumns, terms: tokens.map { ($0, true) })
    }

    /// Song IDs where every (already normalized) token matches a normalized column as a whole
    /// word, best first. Only the last token may match as a prefix (as-you-type), and only
    /// when it is at least `minimumPrefixLength` long: short normalized prefixes are too
    /// loose (English "the" -> "te" would match Hindi "tera").
    func matchNormalized(tokens: [String]) throws -> [String] {
        let terms = tokens.enumerated().map { offset, token in
            (token, offset == tokens.count - 1 && token.count >= Self.minimumPrefixLength)
        }
        return try match(columns: Self.normalizedColumns, terms: terms)
    }

    /// As `matchNormalized(tokens:)`, over the loose columns (`RomanNormalizer.loose`): the
    /// tokens are already in the loose form.
    func matchLoose(tokens: [String]) throws -> [String] {
        let terms = tokens.enumerated().map { offset, token in
            (token, offset == tokens.count - 1 && token.count >= Self.minimumPrefixLength)
        }
        return try match(columns: Self.looseColumns, terms: terms)
    }

    /// Shortest normalized last token that still matches as a prefix.
    static let minimumPrefixLength = 4

    /// Normalized title + first-line words of every song, for the edit-distance fallback.
    func fuzzyCandidates() throws -> [FuzzyCandidate] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, norm_title, norm_first_line FROM songs
                ORDER BY title COLLATE NOCASE, id
                """,
            )
            return rows.map { row in
                let title: String = row["norm_title"]
                let firstLine: String = row["norm_first_line"]
                let words = (title + " " + firstLine).split(separator: " ").map(String.init)
                return FuzzyCandidate(id: row["id"], words: words)
            }
        }
    }

    private func match(columns: String, terms: [(token: String, prefix: Bool)]) throws -> [String] {
        guard !terms.isEmpty else { return [] }
        // Tokens are letters/digits only (RomanNormalizer.words), so quoting is safe.
        let query = terms
            .map { "\"\($0.token)\"" + ($0.prefix ? "*" : "") }
            .joined(separator: " AND ")
        let expression = "\(columns) : (\(query))"
        return try pool.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT f.song_id FROM (
                    SELECT song_id, \(Self.rankExpression) AS score
                    FROM songs_fts WHERE songs_fts MATCH ?
                ) AS f
                JOIN songs AS s ON s.id = f.song_id
                ORDER BY f.score, s.title COLLATE NOCASE, s.id
                """,
                arguments: [expression],
            )
        }
    }
}
