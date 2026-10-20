// Phase 3 (P3-6, R71): tag management across the library (rename, merge) and the starter
// tag suggestions. Tags stay free-form in the sidecar.

import Foundation
import Support

/// What one library-wide tag rewrite changed: each rewritten song's tags as they were
/// before, so the whole rewrite undoes as one action (`restoreTags`).
public struct TagRewrite: Sendable, Equatable {
    /// The tags each rewritten song had before, by song.
    public var previous: [SongID: [String]]
    /// Songs that carry a source tag but were left alone because they are read-only.
    public var skipped: [SongID]

    public init(previous: [SongID: [String]] = [:], skipped: [SongID] = []) {
        self.previous = previous
        self.skipped = skipped
    }

    /// How many songs were rewritten.
    public var count: Int {
        previous.count
    }
}

public extension LibraryStore {
    /// Renames tag `old` to `new` in every song's sidecar (case-insensitive match). When
    /// `new` is already a tag, this is a merge. See `mergeTags(_:into:)`.
    @discardableResult
    func renameTag(_ old: String, to new: String) throws -> TagRewrite {
        try mergeTags([old], into: new)
    }

    /// Replaces every tag of `sources` (case-insensitive) with `target` in every editable
    /// song that carries one, keeping the position of the first replaced tag and dropping
    /// duplicates (`SongMetadata.normalizedTags`). Only sidecars change (each written
    /// atomically) and the index follows in one transaction. If a write fails, the songs
    /// already rewritten are put back and the error is rethrown, so the library is never
    /// left half renamed. Read-only songs are left alone and listed in `skipped`. Returns the
    /// receipt that `restoreTags` undoes.
    @discardableResult
    func mergeTags(_ sources: [String], into target: String) throws -> TagRewrite {
        let cleanTarget = SongMetadata.normalizedTags([target]).first ?? ""
        let sourceKeys = Set(SongMetadata.normalizedTags(sources).map(SongMetadata.tagKey))
        guard !cleanTarget.isEmpty, !sourceKeys.isEmpty else { return TagRewrite() }
        let library = try openLibrary()
        var rewrite = TagRewrite()
        var plan: [SongID: [String]] = [:]
        for song in library.songs.values.sorted(by: { $0.record.id < $1.record.id }) {
            let tags = song.record.sidecar.tags
            guard tags.contains(where: { sourceKeys.contains(SongMetadata.tagKey($0)) }) else {
                continue
            }
            if song.record.isReadOnly {
                rewrite.skipped.append(song.record.id)
                continue
            }
            let replaced = tags
                .map { sourceKeys.contains(SongMetadata.tagKey($0)) ? cleanTarget : $0 }
            let normalized = SongMetadata.normalizedTags(replaced)
            if normalized != tags {
                plan[song.record.id] = normalized
            }
        }
        rewrite.previous = try writeTags(plan)
        return rewrite
    }

    /// Undoes a `renameTag` / `mergeTags`: puts each rewritten song's previous tags back
    /// (one action, rolled back as a whole on failure). Songs deleted since are skipped.
    /// Returns the receipt that redoes it.
    @discardableResult
    func restoreTags(_ rewrite: TagRewrite) throws -> TagRewrite {
        let library = try openLibrary()
        let plan = rewrite.previous.filter { library.songs[$0.key]?.record.isReadOnly == false }
        return try TagRewrite(previous: writeTags(plan), skipped: rewrite.skipped)
    }
}

extension LibraryStore {
    /// Writes `plan` (song -> new tags) and reindexes those songs in one transaction;
    /// returns each written song's tags from before. On a failed write, the songs already
    /// written get their old sidecars back before the error is rethrown.
    private func writeTags(_ plan: [SongID: [String]]) throws -> [SongID: [String]] {
        let library = try openLibrary()
        var written: [(before: LoadedSong, after: LoadedSong)] = []
        do {
            for id in plan.keys.sorted() {
                guard let tags = plan[id] else { continue }
                let existing = try editableSong(id, in: library)
                var sidecar = try sidecarToWrite(for: existing, files: library.files)
                sidecar.tags = tags
                let song = try library.files.writingSidecar(sidecar, of: existing)
                written.append((existing, song))
            }
            var changes = IndexChanges()
            changes.upserts = written.map(\.after.indexed)
            try library.index.apply(changes)
        } catch {
            for (before, after) in written.reversed() {
                _ = try? library.files.writingSidecar(before.record.sidecar, of: after)
            }
            throw error
        }
        var previous: [SongID: [String]] = [:]
        for (before, after) in written {
            self.library?.songs[after.record.id] = after
            previous[before.record.id] = before.record.sidecar.tags
        }
        return previous
    }
}

/// The starter tags offered while the library has no tags of its own (R71): a manual pick
/// only, nothing is ever applied for the user and no model guesses tags.
public enum StarterTags {
    /// In the order the tag field offers them.
    public static let all = ["upbeat", "ballad", "crowd pleaser", "singalong", "original", "cover"]

    /// The starter tags to offer, given every tag in the library and the seed tags that do
    /// not count as the user's own (the Welcome songs' tag): all six while the user has no
    /// tag of their own, none once they do.
    public static func suggestions(libraryTags: [String], seedTags: [String]) -> [String] {
        let seeds = Set(seedTags.map(SongMetadata.tagKey))
        let own = SongMetadata.normalizedTags(libraryTags)
            .contains { !seeds.contains(SongMetadata.tagKey($0)) }
        return own ? [] : all
    }
}
