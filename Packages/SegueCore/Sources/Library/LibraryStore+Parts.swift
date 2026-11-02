// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 9.5). Sidecar-only
// writes for a song's parts (bass fills).

import Foundation
import Support

public extension LibraryStore {
    /// Writes `parts` to the song's sidecar only: the `.cho` bytes, its mtime and the index
    /// projection are untouched; the sidecar is written at the current schema. A read-only
    /// song (a sidecar from a newer Segue) throws.
    func updateParts(id: SongID, _ parts: [Part]) throws -> SongRecord {
        let library = try openLibrary()
        var existing = try editableSong(id, in: library)
        existing.record.sidecar = try sidecarToWrite(for: existing, files: library.files)
        let song = try library.files.writingParts(parts, of: existing)
        self.library?.songs[id] = song
        return song.record
    }
}

extension SongFiles {
    /// `song` with `parts` written to its sidecar only (the shape of `writingBassPrefs`).
    func writingParts(_ parts: [Part], of song: LoadedSong) throws -> LoadedSong {
        var song = song
        var sidecar = song.record.sidecar
        sidecar.parts = parts
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
