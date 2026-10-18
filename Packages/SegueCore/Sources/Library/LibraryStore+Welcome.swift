// WS2b 4.2: generic seeding from a schema-1 manifest folder (the Welcome library, WS5's
// screenshot-only songs) and lookup of the songs a seed's tag marks.

import Foundation
import Support

public extension LibraryStore {
    /// Adds the songs of the seed folder at `folder` (`manifest.json` plus its `.cho` files)
    /// to the open library, in manifest order, and returns each with its record.
    ///
    /// Idempotent: a song that already carries the manifest's `tag`, has the same title and
    /// byte-identical source is reused, not created again. Otherwise the song is created
    /// with the manifest's tags, proficiency, notes, cues and live columns in one write of
    /// its `.cho` and sidecar. Songs already in the library are never touched. The demo
    /// setlist is not created here (`Setlists` sits above `Library`); the caller does that
    /// from `SeedManifest.setlist` with the returned IDs.
    ///
    /// Throws `SeedError`. Songs written before a failure stay; a retry reuses them.
    func seedSongs(fromManifestFolder folder: URL) throws -> [SeededSong] {
        let library = try openLibrary()
        let fileSystem = library.files.fileSystem
        let manifest = try SeedManifest.load(fromFolder: folder, fileSystem: fileSystem)
        var seeded: [SeededSong] = []
        for entry in manifest.songs {
            let data: Data
            do {
                data = try fileSystem.readData(at: folder.appending(path: entry.file))
            } catch {
                throw SeedError.missingFile(entry.file)
            }
            guard let source = String(data: data, encoding: .utf8) else {
                throw SeedError.unreadableSong(entry.file)
            }
            if let existing = try seededMatch(for: data, tag: manifest.tag) {
                seeded.append(SeededSong(file: entry.file, record: existing, created: false))
                continue
            }
            let record: SongRecord
            do {
                record = try createSong(source: source) { sidecar in
                    sidecar.tags = SongMetadata.normalizedTags(entry.tags)
                    sidecar.proficiency = entry.proficiency
                    let blankNotes = entry.notes?.allSatisfy(\.isWhitespace) ?? true
                    sidecar.notes = blankNotes ? nil : entry.notes
                    sidecar.cues = entry.cues
                    if let columns = entry.live?.columns {
                        sidecar.live.columns = columns
                    }
                }
            } catch {
                throw SeedError.writeFailed(file: entry.file, reason: SongFiles.describe(error))
            }
            seeded.append(SeededSong(file: entry.file, record: record, created: true))
        }
        return seeded
    }

    /// Every song carrying `tag` (case-insensitive), sorted like `allSongs()`.
    func songs(taggedWith tag: String) throws -> [SongRecord] {
        let key = SongMetadata.tagKey(tag)
        return try allSongs().filter { song in
            song.sidecar.tags.contains { SongMetadata.tagKey($0) == key }
        }
    }

    /// The songs carrying the manifest's tag at `folder`, split into the unmodified seed
    /// originals and the rest ("Remove Welcome Songs" trashes the first and lists the second).
    func seedInventory(fromManifestFolder folder: URL) throws -> SeedInventory {
        let library = try openLibrary()
        let fileSystem = library.files.fileSystem
        let manifest = try SeedManifest.load(fromFolder: folder, fileSystem: fileSystem)
        var originals: Set<String> = []
        for entry in manifest.songs {
            if let data = try? fileSystem.readData(at: folder.appending(path: entry.file)) {
                originals.insert(SongFiles.hash(data))
            }
        }
        var inventory = SeedInventory(unmodified: [], edited: [])
        for song in try songs(taggedWith: manifest.tag) {
            if originals.contains(song.revision.contentHash) {
                inventory.unmodified.append(song)
            } else {
                inventory.edited.append(song)
            }
        }
        return inventory
    }
}

extension LibraryStore {
    /// A song carrying `tag` whose `.cho` bytes are exactly `data` (so also the same title).
    private func seededMatch(for data: Data, tag: String) throws -> SongRecord? {
        let hash = SongFiles.hash(data)
        return try songs(taggedWith: tag).first { $0.revision.contentHash == hash }
    }
}
