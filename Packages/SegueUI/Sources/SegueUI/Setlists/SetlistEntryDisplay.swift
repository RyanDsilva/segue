import Editing
import Foundation
import Library
import Setlists

/// What a setlist row shows for its song with the slot's overrides applied: the key the
/// chords are displayed in and the capo to play with (the live view renders the same).
struct SetlistEntryDisplay: Equatable {
    var key: String?
    var capo: Int?
    var length: SongLength?

    init(entry: SetlistEntry, record: SongRecord?) {
        guard let record else {
            key = nil
            capo = nil
            length = nil
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
        length = SetlistTiming.directiveLength(of: record)
    }

    /// "Capo 2", or "-" when there is none.
    var capoText: String {
        capo.map { "Capo \($0)" } ?? "-"
    }
}

extension SetlistTiming {
    /// Timings for `setlist` with lengths from the songs' `{duration}` directives (learned
    /// lengths arrive in phase 3).
    init(setlist: Setlist, songs: (SongID) -> SongRecord?) {
        var lengths: [SongID: SongLength] = [:]
        for entry in setlist.entries where lengths[entry.songId] == nil {
            if let record = songs(entry.songId), let length = Self.directiveLength(of: record) {
                lengths[entry.songId] = length
            }
        }
        self.init(entries: setlist.entries, lengths: lengths, target: setlist.targetDuration)
    }
}
