import Editing
import Foundation
import Library
import Services
import Setlists

/// What a setlist row shows for its song with the slot's overrides applied: the key the
/// chords are displayed in and the capo to play with (the live view renders the same).
struct SetlistEntryDisplay: Equatable {
    var key: String?
    var capo: Int?

    init(entry: SetlistEntry, record: SongRecord?) {
        guard let record else {
            key = nil
            capo = nil
            return
        }
        let songCapo = record.document.metadata.capo
        let (options, capo) = entry.overrides.applied(
            to: record.sidecar.displayPrefs.displayOptions,
            songCapo: songCapo,
        )
        let transform = DisplayTransform(
            options: options,
            key: KeyContext(document: record.document),
            capo: capo,
        )
        key = transform.displayKey?.name
        self.capo = (capo ?? 0) > 0 ? capo : nil
    }

    /// "Capo 2", or nothing when there is none: "Capo" labels the column itself, and a bare
    /// "-" there read like a missing tempo.
    var capoText: String {
        capo.map { "Capo \($0)" } ?? ""
    }
}

extension SetlistTiming {
    /// Timings for `setlist` with each slot's time from the timeline (`SlotTimes.slot`,
    /// through the library's cache) and the setlist's changeover, else `defaultChangeover`
    /// (Settings > General, R86). A missing song is unknown.
    @MainActor
    init(setlist: Setlist, library: LibraryViewModel, defaultChangeover: Int) {
        var times: [SetlistItemID: SlotTime] = [:]
        var medleys: [SetlistItemID: MedleyTime] = [:]
        for entry in setlist.entries {
            if let song = entry.songId, let record = library.song(id: song) {
                times[entry.itemId] = library.times.slot(record, arrangement: entry.arrangement)
            }
            // A medley: each member's slot time through the same cache (P9-3 7).
            if let medley = entry.medley {
                medleys[entry.itemId] = MedleyTime(members: medley.members.map { member in
                    library.song(id: member.songId)
                        .map { library.times.slot($0, arrangement: member.arrangement) }
                        ?? .unknown(.missingSong)
                })
            }
        }
        self.init(
            entries: setlist.entries,
            times: times,
            medleyTimes: medleys,
            target: setlist.targetDuration,
            changeover: ChangeoverSetting.effective(
                for: setlist.changeoverSeconds,
                default: defaultChangeover,
            ),
        )
    }

    /// The same, uncached (tests and callers without a library view model).
    init(setlist: Setlist, songs: (SongID) -> SongRecord?, defaultChangeover: Int) {
        var times: [SetlistItemID: SlotTime] = [:]
        var medleys: [SetlistItemID: MedleyTime] = [:]
        for entry in setlist.entries {
            if let song = entry.songId, let record = songs(song) {
                times[entry.itemId] = SlotTimes.slot(record, arrangement: entry.arrangement)
            }
            if let medley = entry.medley {
                medleys[entry.itemId] = SlotTimes.medley(medley.members.map {
                    (songs($0.songId), $0.arrangement)
                })
            }
        }
        self.init(
            entries: setlist.entries,
            times: times,
            medleyTimes: medleys,
            target: setlist.targetDuration,
            changeover: ChangeoverSetting.effective(
                for: setlist.changeoverSeconds,
                default: defaultChangeover,
            ),
        )
    }
}

extension SetlistTiming {
    /// Row 30's closed-vocabulary summary of these timings (counts and buckets only).
    func summary(arranged: Int, tolerance: TimeInterval) -> SetlistTimedSummary {
        // Songs are slots and medley members (P9-3 7).
        let medleys = items.compactMap(\.medley)
        let songs = items.compactMap(\.slot) + medleys.flatMap { $0.members.compactMap(\.slot) }
        let known = items.compactMap(\.time).filter { $0.source != .intermission }
        let target: SetlistTimedTarget = if let target = self.target, target > 0 {
            abs(total - target) <= tolerance ? .within : total < target ? .under : .over
        } else {
            .noTarget
        }
        return SetlistTimedSummary(
            songs: SmallBucket(songs.count),
            noTempo: SmallBucket(songs.count { $0.unknown == .noTempo }),
            noChords: SmallBucket(songs.count { $0.unknown == .noChords }),
            arranged: SmallBucket(arranged),
            estimatedOnly: !known.isEmpty && known.allSatisfy(\.estimated),
            target: target,
            medleys: SmallBucket(medleys.count),
            medleyUnknown: medleys.contains { !$0.unknownMembers.isEmpty },
        )
    }
}
