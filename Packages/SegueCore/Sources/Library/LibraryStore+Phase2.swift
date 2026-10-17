// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A.
//
// Library metadata edits (tags, proficiency, notes, cues), per-song live memory, single-song
// reload for the show snapshot rule, and the play-history projection behind "last played" /
// "times played". The bodies are unit A's work; they may move into `LibraryStore.swift` (and
// relax `private` helpers there) as needed, keeping these signatures.

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
    /// untouched) and reindexes it so tag search sees the change. Tags are trimmed, blank
    /// ones dropped and case-insensitive duplicates removed (first spelling wins). Throws
    /// `LibraryError.readOnly` for read-only songs.
    func updateMetadata(id: SongID, _ metadata: SongMetadata) throws -> SongRecord {
        fatalError("unimplemented: unit A (LibraryStore.updateMetadata)")
    }

    /// Replaces the song's live-mode memory (zoom, columns, scroll speed, collapse, auto
    /// start) in its sidecar only, like `updateDisplayPrefs`. Throws `LibraryError.readOnly`
    /// for read-only songs (the live view then keeps the change in memory only).
    func updateLivePrefs(id: SongID, _ prefs: LivePrefs) throws -> SongRecord {
        fatalError("unimplemented: unit A (LibraryStore.updateLivePrefs)")
    }

    /// Every tag in the library with its song count, most used first, then alphabetical.
    func allTags() throws -> [TagCount] {
        fatalError("unimplemented: unit A (LibraryStore.allTags)")
    }

    /// Re-reads song `id` from disk now (only that song's `.cho` and sidecar; the index row
    /// is updated if it changed) and returns it; nil when its file is gone. The show engine
    /// calls this when an item becomes current, so an external edit applies on the next
    /// advance and never mid-song.
    func reloadSong(id: SongID) throws -> SongRecord? {
        fatalError("unimplemented: unit A (LibraryStore.reloadSong)")
    }

    /// Replaces the plays projected for one show (called when a show ends, is auto-closed or
    /// its gig log entry is deleted with `plays: []`).
    func replacePlays(forShow showID: ULID, with plays: [PlayRecord]) throws {
        fatalError("unimplemented: unit A (LibraryStore.replacePlays)")
    }

    /// Replaces the whole play projection (on `ShowStore.load`). The store keeps this set in
    /// memory and re-applies it after `rebuildIndex()`, so the projection survives a rebuild.
    func replaceAllPlays(_ plays: [PlayRecord]) throws {
        fatalError("unimplemented: unit A (LibraryStore.replaceAllPlays)")
    }

    /// Play stats for every song that has been played at least once.
    func playStats() throws -> [SongID: PlayStats] {
        fatalError("unimplemented: unit A (LibraryStore.playStats)")
    }
}
