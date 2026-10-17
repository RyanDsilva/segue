// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A.
//
// Library metadata edits (tags, proficiency, notes, cues), per-song live memory, single-song
// reload for the show snapshot rule, and the play-history projection behind "last played" /
// "times played".

import Foundation
import Support

/// The user-editable metadata of a song's sidecar (library inspector, builder).
public struct SongMetadata: Sendable, Equatable {
    public var tags: [String]
    public var proficiency: Proficiency?
    public var notes: String?
    public var cues: [SongCue]

    public init(
        tags: [String] = [],
        proficiency: Proficiency? = nil,
        notes: String? = nil,
        cues: [SongCue] = [],
    ) {
        self.tags = tags
        self.proficiency = proficiency
        self.notes = notes
        self.cues = cues
    }

    /// The metadata currently in `sidecar`.
    public init(_ sidecar: Sidecar) {
        self.init(
            tags: sidecar.tags,
            proficiency: sidecar.proficiency,
            notes: sidecar.notes,
            cues: sidecar.cues,
        )
    }

    /// `tags` as they are saved and indexed: whitespace runs collapsed to one space and
    /// trimmed, blank ones dropped, and case-insensitive duplicates removed (the first
    /// spelling wins). Order is kept.
    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for tag in tags {
            let cleaned = tag.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !cleaned.isEmpty, seen.insert(tagKey(cleaned)).inserted {
                result.append(cleaned)
            }
        }
        return result
    }

    /// The case-insensitive identity of a tag ("Upbeat" and "upbeat" are one tag).
    public static func tagKey(_ tag: String) -> String {
        tag.lowercased()
    }
}

/// A tag and how many songs carry it (tag chips, filter menus). `tag` keeps the spelling
/// used most often; matching is case-insensitive.
public struct TagCount: Sendable, Hashable {
    public var tag: String
    public var count: Int

    public init(tag: String, count: Int) {
        self.tag = tag
        self.count = count
    }
}

/// One song played in a finished show, as the index projects it.
public struct PlayRecord: Sendable, Hashable {
    public var songId: SongID
    /// The show's ULID (`ShowID.ulid`; Library does not depend on Shows).
    public var showId: ULID
    public var startedAt: Date
    public var endedAt: Date
    public var fromRequest: Bool

    public init(songId: SongID, showId: ULID, startedAt: Date, endedAt: Date, fromRequest: Bool) {
        self.songId = songId
        self.showId = showId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.fromRequest = fromRequest
    }
}

/// "Last played" and "times played" for one song (library list, builder, search results).
public struct PlayStats: Sendable, Hashable {
    public var timesPlayed: Int
    public var lastPlayed: Date?

    public init(timesPlayed: Int = 0, lastPlayed: Date? = nil) {
        self.timesPlayed = timesPlayed
        self.lastPlayed = lastPlayed
    }
}

public extension LibraryStore {
    /// Replaces the song's tags, proficiency, notes and cues in its sidecar (the `.cho` is
    /// untouched) and reindexes it so tag search sees the change. Tags are normalized with
    /// `SongMetadata.normalizedTags`; notes that are only whitespace are saved as none.
    /// Metadata edited on disk since the song was loaded is replaced, other sidecar fields
    /// on disk are kept. Throws `LibraryError.readOnly` for read-only songs.
    @discardableResult
    func updateMetadata(id: SongID, _ metadata: SongMetadata) throws -> SongRecord {
        let library = try openLibrary()
        let existing = try editableSong(id, in: library)
        var sidecar = try sidecarToWrite(for: existing, files: library.files)
        sidecar.tags = SongMetadata.normalizedTags(metadata.tags)
        sidecar.proficiency = metadata.proficiency
        let blankNotes = metadata.notes?.allSatisfy(\.isWhitespace) ?? true
        sidecar.notes = blankNotes ? nil : metadata.notes
        sidecar.cues = metadata.cues
        let song = try library.files.writingSidecar(sidecar, of: existing)
        try library.index.upsert(song.indexed)
        self.library?.songs[id] = song
        return song.record
    }

    /// Replaces the song's live-mode memory (zoom, columns, scroll speed, collapse, auto
    /// start) in its sidecar only, like `updateDisplayPrefs`. Throws `LibraryError.readOnly`
    /// for read-only songs (the live view then keeps the change in memory only).
    @discardableResult
    func updateLivePrefs(id: SongID, _ prefs: LivePrefs) throws -> SongRecord {
        let library = try openLibrary()
        let existing = try editableSong(id, in: library)
        var sidecar = try sidecarToWrite(for: existing, files: library.files)
        sidecar.live = prefs
        let song = try library.files.writingSidecar(sidecar, of: existing)
        self.library?.songs[id] = song
        return song.record
    }

    /// Every tag in the library with its song count, most used first, then alphabetical
    /// (case-insensitive). A tag's spelling is the one most songs use (ties: the first in
    /// code-point order).
    func allTags() throws -> [TagCount] {
        var spellings: [String: [String: Int]] = [:]
        for song in try openLibrary().songs.values {
            for tag in SongMetadata.normalizedTags(song.record.sidecar.tags) {
                spellings[SongMetadata.tagKey(tag), default: [:]][tag, default: 0] += 1
            }
        }
        return spellings.values
            .compactMap { variants -> TagCount? in
                let spelling = variants.min { lhs, rhs in
                    lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
                }
                return spelling.map { TagCount(tag: $0.key, count: variants.values.reduce(0, +)) }
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return switch lhs.tag.caseInsensitiveCompare(rhs.tag) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: lhs.tag < rhs.tag
                }
            }
    }

    /// Re-reads song `id` from disk now (only that song's `.cho` and sidecar; the index row
    /// is updated if it changed) and returns it; nil when its file is gone. The show engine
    /// calls this when an item becomes current, so an external edit applies on the next
    /// advance and never mid-song.
    ///
    /// When the file is gone, or now holds another song, the library is rescanned
    /// (`refresh()`), so a song renamed on disk is still found. A file that exists but
    /// can't be read keeps the last loaded version.
    func reloadSong(id: SongID) throws -> SongRecord? {
        let library = try openLibrary()
        guard let existing = library.songs[id],
              library.files.fileSystem.fileExists(at: library.files.choURL(slug: existing.slug))
        else {
            try refresh()
            return self.library?.songs[id]?.record
        }
        // Read both files again whatever their stamps say; unchanged bytes are reused.
        var stale = existing
        stale.choStamp = .unknown
        stale.sidecarStamp = nil
        let path = existing.record.relativePath
        var song: LoadedSong
        switch library.files.scan([existing.slug], previous: [path: stale]).first {
        case let .loaded(loaded):
            song = loaded
        case let .orphan(orphan):
            let (adopted, problem) = library.files.adoptOrphan(orphan, previous: existing)
            song = adopted
            if let problem {
                let issue = LibraryLoadIssue(
                    relativePath: SongFiles.sidecarRelativePath(slug: orphan.slug),
                    message: problem,
                )
                if !loadIssues.contains(issue) {
                    loadIssues.append(issue)
                    loadIssues.sort { $0.relativePath < $1.relativePath }
                }
            }
        case .failed, nil:
            return existing.record
        }
        guard song.record.id == id else {
            try refresh()
            return self.library?.songs[id]?.record
        }
        song.choCreated = song.choCreated ?? existing.choCreated
        var changes = IndexChanges()
        if song.record.relativePath != existing.record.relativePath
            || song.contentHash != existing.contentHash
            || song.indexedTags != existing.indexedTags
        {
            changes.upserts = [song.indexed]
        } else if song.mtime != existing.mtime {
            changes.touches[id.description] = song.mtime
        }
        try library.index.apply(changes)
        self.library?.songs[id] = song
        return song.record
    }

    /// Replaces the plays projected for one show (called when a show ends, is auto-closed or
    /// its gig log entry is deleted with `plays: []`). Every record is stored under
    /// `showID`, whatever its own `showId` says.
    func replacePlays(forShow showID: ULID, with plays: [PlayRecord]) throws {
        let rows = plays.map { play in
            var play = play
            play.showId = showID
            return play
        }
        try openLibrary().index.replacePlays(forShow: showID, with: rows)
        self.plays[showID] = rows.isEmpty ? nil : rows
    }

    /// Replaces the whole play projection (on `ShowStore.load`). The store keeps this set in
    /// memory and re-applies it after `rebuildIndex()`, so the projection survives a rebuild.
    func replaceAllPlays(_ plays: [PlayRecord]) throws {
        try openLibrary().index.replaceAllPlays(plays)
        self.plays = Dictionary(grouping: plays, by: \.showId)
    }

    /// Play stats for every song that has been played at least once ("last played" is the
    /// latest start).
    func playStats() throws -> [SongID: PlayStats] {
        var result: [SongID: PlayStats] = [:]
        for (id, stats) in try openLibrary().index.playStats() {
            if let ulid = ULID(string: id) {
                result[SongID(ulid)] = stats
            }
        }
        return result
    }
}

extension LibraryStore {
    /// Writes the in-memory play projection into the index (after it was re-created). A
    /// no-op while nothing was handed in, so a fresh launch never wipes the persisted plays
    /// before `ShowStore.load` replaces them.
    func reapplyPlays() throws {
        guard let library, !plays.isEmpty else { return }
        let all = plays.sorted { $0.key < $1.key }.flatMap(\.value)
        try library.index.replaceAllPlays(all)
    }
}

extension SongFiles {
    /// `song` with `sidecar` written (only the sidecar: the `.cho` bytes, its mtime and the
    /// index are untouched), at the current schema version with a new `updatedAt`. Callers
    /// check that the song is editable and build `sidecar` on `sidecarToWrite`.
    func writingSidecar(_ sidecar: Sidecar, of song: LoadedSong) throws -> LoadedSong {
        var song = song
        var sidecar = sidecar
        sidecar.schemaVersion = Sidecar.currentSchemaVersion
        sidecar.updatedAt = SegueJSON.stamp(clock.now())
        let data = try SidecarCodec.encode(sidecar)
        let url = sidecarURL(slug: song.slug)
        try fileSystem.writeAtomically(data, to: url)
        song.record.sidecar = sidecar
        song.sidecarData = data // also updates `record.revision.sidecarHash`
        song.sidecarStamp = try FileStamp(fileSystem.attributes(at: url))
        return song
    }
}
