// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.9). Sidecar-only writes for a
// song's walk-up feel and picks (and P8-6's play-along timing).

import Foundation
import Support

public extension LibraryStore {
    /// Writes `prefs` to the song's sidecar only: the `.cho` bytes, its mtime and the index
    /// projection are untouched; the sidecar is written at the current schema. A read-only
    /// song (a sidecar from a newer Segue) throws.
    func updateBassPrefs(id: SongID, _ prefs: BassPrefs) throws -> SongRecord {
        let library = try openLibrary()
        var existing = try editableSong(id, in: library)
        existing.record.sidecar = try sidecarToWrite(for: existing, files: library.files)
        let song = try library.files.writingBassPrefs(prefs, of: existing)
        self.library?.songs[id] = song
        return song.record
    }
}

extension SongFiles {
    /// `song` with `prefs` written to its sidecar only (the shape of `writingDisplayPrefs`).
    func writingBassPrefs(_ prefs: BassPrefs, of song: LoadedSong) throws -> LoadedSong {
        var song = song
        var sidecar = song.record.sidecar
        sidecar.bass = prefs
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
