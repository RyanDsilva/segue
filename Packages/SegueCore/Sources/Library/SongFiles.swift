import ChordPro
import CryptoKit
import Foundation
import Support

/// A song as loaded from disk, plus what change detection needs.
struct LoadedSong: Sendable, Equatable {
    var record: SongRecord
    /// `<slug>` of `songs/<slug>.cho`.
    var slug: String
    /// SHA-256 (hex) of the `.cho` bytes.
    var contentHash: String
    /// `.cho` modification time, seconds since 1970.
    var mtime: Double
    /// Raw sidecar bytes as last read or written (nil if never on disk).
    var sidecarData: Data?
    /// Sidecar may be (re)written: false for newer-schema and unreadable sidecars.
    var sidecarWritable: Bool {
        record.readOnly == nil
    }

    /// The index projection of this song. Uses only `metadata` and `plainLyrics`.
    var indexed: IndexedSong {
        let metadata = record.document.metadata
        let lyrics = record.document.plainLyrics
        let firstLine = lyrics.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return IndexedSong(
            id: record.id.description,
            path: record.relativePath,
            title: metadata.title ?? "",
            artist: metadata.artists.joined(separator: ", "),
            key: metadata.key,
            tempo: metadata.tempo,
            mtime: mtime,
            contentHash: contentHash,
            firstLine: firstLine,
            lyrics: lyrics,
        )
    }

    /// Sort key for `allSongs()`: title, else file slug.
    var sortTitle: String {
        record.document.metadata.title ?? slug
    }
}

/// File-level operations on `songs/`: reading a `.cho` with its sidecar, creating missing
/// sidecars and writing songs. All IO goes through the injected `FileSystem`.
struct SongFiles: Sendable {
    let root: LibraryRoot
    let fileSystem: any FileSystem
    let clock: any Clock
    let ids: any IDGenerator

    func choURL(slug: String) -> URL {
        root.songsDirectory.appending(path: slug + "." + LibraryRoot.songExtension)
    }

    func sidecarURL(slug: String) -> URL {
        root.songsDirectory.appending(path: slug + LibraryRoot.sidecarSuffix)
    }

    static func relativePath(slug: String) -> String {
        "songs/\(slug).\(LibraryRoot.songExtension)"
    }

    /// Every `songs/*.cho`, sorted by path.
    func songSlugs() throws -> [String] {
        let suffix = "." + LibraryRoot.songExtension
        return try fileSystem.contentsOfDirectory(at: root.songsDirectory)
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(suffix) && $0.count > suffix.count }
            .map { String($0.dropLast(suffix.count)) }
    }

    /// Whether `slug` is free for a new song (neither the `.cho` nor the sidecar exists).
    func isTaken(slug: String) -> Bool {
        fileSystem.fileExists(at: choURL(slug: slug))
            || fileSystem.fileExists(at: sidecarURL(slug: slug))
    }

    /// Loads `songs/<slug>.cho` and its sidecar. Reuses `previous` (same path) for whatever
    /// did not change. An orphan `.cho` gets a new sidecar written next to it.
    func load(slug: String, previous: LoadedSong?) throws -> LoadedSong {
        let data = try fileSystem.readData(at: choURL(slug: slug))
        let attributes = try fileSystem.attributes(at: choURL(slug: slug))
        let hash = Self.hash(data)

        let sidecarURL = sidecarURL(slug: slug)
        let sidecarData: Data
        let sidecar: Sidecar
        let readOnly: ReadOnlyReason?
        if fileSystem.fileExists(at: sidecarURL) {
            sidecarData = try fileSystem.readData(at: sidecarURL)
            if let previous, previous.sidecarData == sidecarData {
                (sidecar, readOnly) = (previous.record.sidecar, previous.record.readOnly)
            } else {
                (sidecar, readOnly) = decodeSidecar(sidecarData, previousID: previous?.record.id)
            }
        } else {
            let now = SegueJSON.stamp(clock.now())
            sidecar = Sidecar(id: SongID(ids.next()), createdAt: now, updatedAt: now)
            readOnly = nil
            sidecarData = try SidecarCodec.encode(sidecar)
            try fileSystem.writeAtomically(sidecarData, to: sidecarURL)
        }

        let source: String
        let document: SongDocument
        let diagnostics: [Diagnostic]
        if let previous, previous.contentHash == hash {
            (source, document, diagnostics) = (
                previous.record.source, previous.record.document, previous.record.diagnostics,
            )
        } else {
            source = String(decoding: data, as: UTF8.self)
            (document, diagnostics) = ChordProParser.parse(source)
        }

        return LoadedSong(
            record: SongRecord(
                id: sidecar.id,
                relativePath: Self.relativePath(slug: slug),
                source: source,
                document: document,
                diagnostics: diagnostics,
                sidecar: sidecar,
                readOnly: readOnly,
            ),
            slug: slug,
            contentHash: hash,
            mtime: attributes.modificationDate.timeIntervalSince1970,
            sidecarData: sidecarData,
        )
    }

    /// Writes `source` to `songs/<slug>.cho` and `sidecar` next to it (the `.cho` first, so
    /// an interrupted write leaves at worst an orphan `.cho`, which gets a sidecar on index).
    func write(source: String, sidecar: Sidecar, slug: String) throws -> LoadedSong {
        let data = Data(source.utf8)
        let sidecarData = try SidecarCodec.encode(sidecar)
        try fileSystem.writeAtomically(data, to: choURL(slug: slug))
        try fileSystem.writeAtomically(sidecarData, to: sidecarURL(slug: slug))
        let attributes = try fileSystem.attributes(at: choURL(slug: slug))
        let (document, diagnostics) = ChordProParser.parse(source)
        return LoadedSong(
            record: SongRecord(
                id: sidecar.id,
                relativePath: Self.relativePath(slug: slug),
                source: source,
                document: document,
                diagnostics: diagnostics,
                sidecar: sidecar,
            ),
            slug: slug,
            contentHash: Self.hash(data),
            mtime: attributes.modificationDate.timeIntervalSince1970,
            sidecarData: sidecarData,
        )
    }

    /// Gives `song` a fresh ID: rewrites its sidecar if writable, otherwise only in memory.
    /// Used when two sidecars carry the same ID (e.g. a Finder-duplicated song).
    func reassignID(_ song: LoadedSong) throws -> LoadedSong {
        var song = song
        let id = SongID(ids.next())
        song.record.id = id
        song.record.sidecar.id = id
        if song.sidecarWritable {
            song.record.sidecar.schemaVersion = Sidecar.currentSchemaVersion
            song.record.sidecar.updatedAt = SegueJSON.stamp(clock.now())
            let data = try SidecarCodec.encode(song.record.sidecar)
            try fileSystem.writeAtomically(data, to: sidecarURL(slug: song.slug))
            song.sidecarData = data
        }
        return song
    }

    private func decodeSidecar(
        _ data: Data,
        previousID: SongID?,
    ) -> (Sidecar, ReadOnlyReason?) {
        let now = SegueJSON.stamp(clock.now())
        switch SidecarCodec.decode(data, fallbackDate: now) {
        case let .editable(sidecar, _):
            return (sidecar, nil)
        case let .newer(sidecar, found):
            let reason = ReadOnlyReason.newerSchema(
                found: found,
                supported: Sidecar.currentSchemaVersion,
            )
            let fallback = Sidecar(
                schemaVersion: found,
                id: previousID ?? SongID(ids.next()),
                createdAt: now,
                updatedAt: now,
            )
            return (sidecar ?? fallback, reason)
        case let .unreadable(message, salvagedID):
            // Placeholder metadata in memory only; the file on disk stays untouched.
            let placeholder = Sidecar(
                id: salvagedID ?? previousID ?? SongID(ids.next()),
                createdAt: now,
                updatedAt: now,
            )
            return (placeholder, .unreadableSidecar(message: message))
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
