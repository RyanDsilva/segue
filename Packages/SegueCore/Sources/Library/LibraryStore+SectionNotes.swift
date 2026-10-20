// Owner: P3-13. The one write behind a section note edit: the `.cho` and the sidecar cues
// together, so "Show on stage only" moves a note between them in one step.

import Foundation

public extension LibraryStore {
    /// Writes song `id`'s section notes: `source` (nil = the `.cho` is unchanged) and the
    /// sidecar `cues`, together. A new source is checked against `revision` (default: the
    /// revision this store last loaded) like `updateSong`: if the `.cho` on disk changed,
    /// nothing is written and `LibraryError.conflict` is thrown. Other sidecar fields edited
    /// on disk are kept. Throws `LibraryError.readOnly` for read-only songs.
    @discardableResult
    func updateSectionNotes(
        id: SongID,
        source: String?,
        cues: [SongCue],
        basedOn revision: SongRevision? = nil,
    ) throws -> SongRecord {
        let library = try openLibrary()
        let existing = try editableSong(id, in: library)
        var sidecar = try sidecarToWrite(for: existing, files: library.files)
        sidecar.cues = cues
        guard let source else {
            let song = try library.files.writingSidecar(sidecar, of: existing)
            self.library?.songs[id] = song
            return song.record
        }
        let expected = revision ?? existing.record.revision
        guard let onDisk = try library.files.currentSource(slug: existing.slug) else {
            throw LibraryError.conflict(id, .deleted)
        }
        guard SongFiles.hash(onDisk) == expected.contentHash else {
            throw LibraryError.conflict(id, .sourceChanged)
        }
        return try write(source: source, sidecar: sidecar, over: existing, in: library)
    }
}
