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
    /// The song's time in seconds (`SlotTimes`, P8-8 section 5.4); nil = unknown.
    public var time: TimeInterval?
    /// Why `time` is unknown (nil when known).
    public var unknownTime: UnknownTime?
    /// `time` rests on default chord lengths.
    public var timeEstimated: Bool
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
        time: SlotTime = .unknown(.noTempo),
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
        self.time = time.seconds.flatMap { $0 > 0 ? $0 : nil }
        unknownTime = self.time == nil ? (time.unknown ?? .noChords) : nil
        timeEstimated = time.isEstimated
        self.lastPlayed = lastPlayed
        artistForms = SongFilter.artistForms(artists)
        albumForm = album.map(RomanNormalizer.normalize).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Reads `record` (with its play stats, if it was ever played). Its time is filled by
    /// the builder for the songs a request admits (`SetBuilder.withSlotTimes`).
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
            lastPlayed: stats?.lastPlayed,
            artists: metadata.artists,
            album: metadata.album,
        )
    }

    /// This song with `time` in place of its own.
    public func timed(_ time: SlotTime) -> Self {
        var song = self
        song.time = time.seconds.flatMap { $0 > 0 ? $0 : nil }
        song.unknownTime = song.time == nil ? (time.unknown ?? .noChords) : nil
        song.timeEstimated = time.isEstimated
        return song
    }

    /// The time as `SetlistTiming` reads it.
    public var slotTime: SlotTime {
        if let time {
            return .known(seconds: time, bars: 0, tempo: tempo ?? 0, estimated: timeEstimated)
        }
        return .unknown(unknownTime ?? .noTempo)
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
    /// The records behind `songs` (empty for a library built from songs alone, whose songs
    /// keep the times they were given).
    public var records: [SongID: SongRecord]
    /// A song's or an arranged slot's time (`SlotTimes.slot`); the builder calls it only for
    /// the songs a request admits and the slots it keeps.
    public var times: @Sendable (SongRecord, SlotArrangement?) -> SlotTime

    public init(
        songs: [AssistantSong],
        smartFilterMatches: [SmartFilterID: Set<SongID>] = [:],
        now: Date,
    ) {
        self.songs = songs
        self.smartFilterMatches = smartFilterMatches
        self.now = now
        records = [:]
        times = SlotTimes.slot
    }

    /// Prepares `records` with their play stats, and resolves `filters` against them.
    public init(
        records: [SongRecord],
        playStats: [SongID: PlayStats],
        filters: [SmartFilter] = [],
        now: Date,
        times: @escaping @Sendable (SongRecord, SlotArrangement?) -> SlotTime = SlotTimes.slot,
    ) {
        songs = records.map { AssistantSong(record: $0, stats: playStats[$0.id]) }
        self.records = Dictionary(records.map { ($0.id, $0) }) { first, _ in first }
        self.times = times
        smartFilterMatches = Dictionary(uniqueKeysWithValues: filters.map { filter in
            (filter.id, Set(filter.songs(in: records, playStats: playStats).map(\.id)))
        })
        self.now = now
    }
}
