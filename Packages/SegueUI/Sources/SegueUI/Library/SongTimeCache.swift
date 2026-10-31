import Library

/// Memoised slot times (P8-8 section 5.9): one `SlotTime` per song and arrangement, kept
/// until the song's source or chord timing changes. The set builder, composer and no-time
/// list read through it, so a render model and timeline are built once per song version.
@MainActor
final class SongTimeCache {
    private struct Version: Equatable {
        var source: String
        var timing: ChordTiming
    }

    private struct Entry {
        var version: Version
        var song: SlotTime?
        var slots: [SlotArrangement: SlotTime] = [:]
    }

    private var entries: [SongID: Entry] = [:]

    /// The whole song in written order.
    func song(_ record: SongRecord) -> SlotTime {
        var entry = current(record)
        if let time = entry.song {
            return time
        }
        let time = SlotTimes.song(record)
        entry.song = time
        entries[record.id] = entry
        return time
    }

    /// A setlist slot (`SlotTimes.slot`).
    func slot(_ record: SongRecord, arrangement: SlotArrangement?) -> SlotTime {
        guard let arrangement else { return song(record) }
        var entry = current(record)
        if let time = entry.slots[arrangement] {
            return time
        }
        let time = SlotTimes.slot(record, arrangement: arrangement)
        entry.slots[arrangement] = time
        entries[record.id] = entry
        return time
    }

    /// The entry for `record`'s current version (a stale one is dropped).
    private func current(_ record: SongRecord) -> Entry {
        let version = Version(source: record.source, timing: record.sidecar.bass.timing)
        if let entry = entries[record.id], entry.version == version {
            return entry
        }
        return Entry(version: version)
    }
}
