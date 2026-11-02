// Owner: unit C (phase 1). Sidecar-only writes for the per-song view toggles.

import Foundation
import Support

extension SongFiles {
    /// `song` with `prefs` written to its sidecar only: the `.cho` bytes, its mtime and the
    /// index projection are untouched. The sidecar is written at the current schema version
    /// with a new `updatedAt`. Callers check that the song is editable and pass the sidecar
    /// to build on (merged with any change made on disk) in `song.record.sidecar`.
    func writingDisplayPrefs(_ prefs: DisplayPrefs, of song: LoadedSong) throws -> LoadedSong {
        var song = song
        var sidecar = song.record.sidecar
        sidecar.displayPrefs = prefs
        // The editor knows only the modelled keys: keep the ones it does not.
        sidecar.displayPrefs.unknown = song.record.sidecar.displayPrefs.unknown
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
