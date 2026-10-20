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

    /// "Capo 2", or nothing when there is none: "Capo" labels the column itself, and a bare
    /// "-" there read like a missing tempo.
    var capoText: String {
        capo.map { "Capo \($0)" } ?? ""
    }
}

extension SetlistTiming {
    /// Timings for `setlist` with lengths from the songs' `{duration}` directives and the
    /// setlist's changeover, else `defaultChangeover` (Settings > General, R86).
    init(setlist: Setlist, songs: (SongID) -> SongRecord?, defaultChangeover: Int) {
        var lengths: [SongID: SongLength] = [:]
        for song in setlist.entries.compactMap(\.songId) where lengths[song] == nil {
            if let record = songs(song), let length = Self.directiveLength(of: record) {
                lengths[song] = length
            }
        }
        self.init(
            entries: setlist.entries,
            lengths: lengths,
            target: setlist.targetDuration,
            changeover: ChangeoverSetting.effective(
                for: setlist.changeoverSeconds,
                default: defaultChangeover,
            ),
        )
    }
}
