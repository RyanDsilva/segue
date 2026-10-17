import Foundation
import GRDB
import Support

/// The `plays` table: songs played in finished shows, projected from `shows/*.show.json`
/// (the files stay canonical). Rows are not tied to `songs`, so a song that is removed and
/// comes back keeps its history. Times are stored as `Date.timeIntervalSinceReferenceDate`,
/// which round-trips a `Date` exactly.
extension SongIndex {
    /// Replaces the plays of `showID` with `plays` in one transaction.
    func replacePlays(forShow showID: ULID, with plays: [PlayRecord]) throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM plays WHERE show_id = ?",
                arguments: [showID.description],
            )
            try Self.insert(plays, in: db)
        }
    }

    /// Replaces every play with `plays` in one transaction.
    func replaceAllPlays(_ plays: [PlayRecord]) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM plays")
            try Self.insert(plays, in: db)
        }
    }

    /// Times played and the latest start, per song ID string.
    func playStats() throws -> [String: PlayStats] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT song_id, COUNT(*) AS times, MAX(started_at) AS last
                FROM plays GROUP BY song_id
                """,
            )
            var result: [String: PlayStats] = [:]
            for row in rows {
                let last: Double = row["last"]
                result[row["song_id"]] = PlayStats(
                    timesPlayed: row["times"],
                    lastPlayed: Date(timeIntervalSinceReferenceDate: last),
                )
            }
            return result
        }
    }

    private static func insert(_ plays: [PlayRecord], in db: Database) throws {
        let statement = try db.makeStatement(sql: """
        INSERT INTO plays (show_id, song_id, started_at, ended_at, from_request)
        VALUES (?, ?, ?, ?, ?)
        """)
        for play in plays {
            try statement.execute(arguments: [
                play.showId.description,
                play.songId.description,
                play.startedAt.timeIntervalSinceReferenceDate,
                play.endedAt.timeIntervalSinceReferenceDate,
                play.fromRequest,
            ])
        }
    }
}
