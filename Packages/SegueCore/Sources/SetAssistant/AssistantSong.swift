import Diagrams
import Editing
import Foundation
import Library
import MusicTheory

/// What the assistant needs of one song, read once from its record (key detection is the
/// only costly part, so a library's songs are prepared once per build, not per signal).
public struct AssistantSong: Sendable, Hashable, Identifiable {
    public var id: SongID
    public var title: String
    /// Folded tags (`SetRequest.fold`).
    public var tags: Set<String>
    public var proficiency: Proficiency?
    /// The written key (`{key}`, else detected), if any.
    public var key: SongKey?
    public var capo: Int
    public var tuning: [Int]
    public var tempo: Double?
    /// `{duration}` in seconds; nil = unknown (R91).
    public var length: TimeInterval?
    public var lastPlayed: Date?
    /// The artists' matching forms (`SongFilter.artistForms`), for artist chips.
    public var artistForms: Set<String>
    /// The Movie / Album, `RomanNormalizer.normalize`d, for album chips; nil when none.
    public var albumForm: String?

    public init(
        id: SongID,
        title: String,
        tags: [String] = [],
        proficiency: Proficiency? = nil,
        key: SongKey? = nil,
        capo: Int = 0,
        tuning: [Int] = Tuning.standard.strings,
        tempo: Double? = nil,
        length: TimeInterval? = nil,
        lastPlayed: Date? = nil,
        artists: [String] = [],
        album: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.tags = Set(tags.map(SetRequest.fold))
        self.proficiency = proficiency
        self.key = key
        self.capo = capo
        self.tuning = tuning
        self.tempo = tempo
        self.length = length.flatMap { $0 > 0 ? $0 : nil }
        self.lastPlayed = lastPlayed
        artistForms = SongFilter.artistForms(artists)
        albumForm = album.map(RomanNormalizer.normalize).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Reads `record` (with its play stats, if it was ever played).
    public init(record: SongRecord, stats: PlayStats? = nil) {
        let metadata = record.document.metadata
        self.init(
            id: record.id,
            title: metadata.title ?? record.relativePath,
            tags: record.sidecar.tags,
            proficiency: record.sidecar.proficiency,
            key: KeyContext(document: record.document).writtenKey,
            capo: max(metadata.capo ?? 0, 0),
            tuning: record.sidecar.displayPrefs.tuning.strings,
            tempo: metadata.tempo,
            length: metadata.duration,
            lastPlayed: stats?.lastPlayed,
            artists: metadata.artists,
            album: metadata.album,
        )
    }

    public func hasTag(_ tag: String) -> Bool {
        tags.contains(SetRequest.fold(tag))
    }
}

/// The library as the builder sees it: songs, the setlist's changeover and the smart
/// filters a request may name (each resolved to the songs it matches).
public struct AssistantLibrary: Sendable {
    public var songs: [AssistantSong]
    /// Song IDs per smart filter (`SmartFilter.songs(in:playStats:)`, evaluated by the caller
    /// against the real index).
    public var smartFilterMatches: [SmartFilterID: Set<SongID>]
    /// When "recently" is measured from.
    public var now: Date

    public init(
        songs: [AssistantSong],
        smartFilterMatches: [SmartFilterID: Set<SongID>] = [:],
        now: Date,
    ) {
        self.songs = songs
        self.smartFilterMatches = smartFilterMatches
        self.now = now
    }

    /// Prepares `records` with their play stats, and resolves `filters` against them.
    public init(
        records: [SongRecord],
        playStats: [SongID: PlayStats],
        filters: [SmartFilter] = [],
        now: Date,
    ) {
        songs = records.map { AssistantSong(record: $0, stats: playStats[$0.id]) }
        smartFilterMatches = Dictionary(uniqueKeysWithValues: filters.map { filter in
            (filter.id, Set(filter.songs(in: records, playStats: playStats).map(\.id)))
        })
        self.now = now
    }
}
