import ChordPro
import CryptoKit
import Foundation
import Support

/// Modification time and size of a file: the cheap check that lets a scan skip reading,
/// hashing and parsing a file that did not change since it was last loaded.
struct FileStamp: Sendable, Equatable {
    /// Modification time, seconds since 1970.
    var mtime: Double
    var size: Int

    init(_ attributes: FileAttributes) {
        mtime = attributes.modificationDate.timeIntervalSince1970
        size = attributes.size
    }

    private init(mtime: Double, size: Int) {
        self.mtime = mtime
        self.size = size
    }

    /// Matches no file on disk: a `previous` song carrying it is always read again (and
    /// still reused when its bytes hash the same).
    static let unknown = Self(mtime: -1, size: -1)
}

/// A song as loaded from disk, plus what change detection needs.
struct LoadedSong: Sendable, Equatable {
    var record: SongRecord
    /// `<slug>` of `songs/<slug>.cho`.
    var slug: String
    /// The `.cho` as stat'ed just before it was read.
    var choStamp: FileStamp
    /// The `.cho` creation date, if the volume records it (picks the original among
    /// duplicated IDs).
    var choCreated: Date?
    /// The sidecar as stat'ed just before it was read; nil when it is not on disk (or was
    /// rewritten without a fresh stat, which makes the next scan read it once more).
    var sidecarStamp: FileStamp?
    /// Raw sidecar bytes as last read or written (nil if never on disk). Assigning new bytes
    /// (after writing them) updates `record.revision` and clears `sidecarStamp`.
    var sidecarData: Data? {
        didSet {
            record.revision.sidecarHash = sidecarData.map(SongFiles.hash)
            sidecarStamp = nil
        }
    }

    /// Why the sidecar blocks edits (newer schema, unreadable), if it does.
    var sidecarReadOnly: ReadOnlyReason?
    /// Why the `.cho` text blocks edits (not UTF-8), if it does.
    var textReadOnly: ReadOnlyReason?

    init(
        record: SongRecord,
        slug: String,
        choStamp: FileStamp,
        choCreated: Date?,
        sidecarStamp: FileStamp?,
        sidecarData: Data?,
        sidecarReadOnly: ReadOnlyReason?,
        textReadOnly: ReadOnlyReason?,
    ) {
        self.record = record
        self.slug = slug
        self.choStamp = choStamp
        self.choCreated = choCreated
        self.sidecarStamp = sidecarStamp
        self.sidecarData = sidecarData
        self.sidecarReadOnly = sidecarReadOnly
        self.textReadOnly = textReadOnly
        self.record.readOnly = sidecarReadOnly ?? textReadOnly
    }

    /// SHA-256 (hex) of the `.cho` bytes.
    var contentHash: String {
        record.revision.contentHash
    }

    /// `.cho` modification time, seconds since 1970.
    var mtime: Double {
        choStamp.mtime
    }

    /// Sidecar may be (re)written: false for newer-schema and unreadable sidecars. A
    /// non-UTF-8 `.cho` does not block its sidecar.
    var sidecarWritable: Bool {
        sidecarReadOnly == nil
    }

    /// The index projection of this song. Uses only `metadata`, `plainLyrics` and the
    /// sidecar tags.
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
            tags: indexedTags,
        )
    }

    /// The sidecar tags as the index stores them (normalized, one per line); cheap, so a
    /// scan can compare it with the index row without building the whole projection.
    var indexedTags: String {
        SongMetadata.normalizedTags(record.sidecar.tags).joined(separator: "\n")
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

    static func sidecarRelativePath(slug: String) -> String {
        "songs/\(slug)\(LibraryRoot.sidecarSuffix)"
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

    // MARK: Writing

    /// Writes `source` to `songs/<slug>.cho` and `sidecar` next to it (the `.cho` first, so
    /// an interrupted write leaves at worst an orphan `.cho`, which gets a sidecar on index).
    func write(source: String, sidecar: Sidecar, slug: String) throws -> LoadedSong {
        let data = Data(source.utf8)
        let sidecarData = try SidecarCodec.encode(sidecar)
        try fileSystem.writeAtomically(data, to: choURL(slug: slug))
        try fileSystem.writeAtomically(sidecarData, to: sidecarURL(slug: slug))
        let choAttributes = try fileSystem.attributes(at: choURL(slug: slug))
        let sidecarAttributes = try fileSystem.attributes(at: sidecarURL(slug: slug))
        let (document, diagnostics) = ChordProParser.parse(source)
        return LoadedSong(
            record: SongRecord(
                id: sidecar.id,
                relativePath: Self.relativePath(slug: slug),
                source: source,
                document: document,
                diagnostics: diagnostics,
                sidecar: sidecar,
                revision: SongRevision(
                    contentHash: Self.hash(data),
                    sidecarHash: Self.hash(sidecarData),
                ),
            ),
            slug: slug,
            choStamp: FileStamp(choAttributes),
            choCreated: choAttributes.creationDate,
            sidecarStamp: FileStamp(sidecarAttributes),
            sidecarData: sidecarData,
            sidecarReadOnly: nil,
            textReadOnly: nil,
        )
    }

    /// Gives `song` a fresh ID (and creation date: it is a new song now) and rewrites its
    /// sidecar. Used when two sidecars carry the same ID (e.g. a Finder-duplicated song).
    /// A read-only sidecar can't take a new ID, so it gets one derived from its path, which
    /// at least stays the same across launches.
    func reassignID(_ song: LoadedSong) throws -> LoadedSong {
        var song = song
        guard song.sidecarWritable else {
            song.record.id = Self.derivedID(slug: song.slug)
            song.record.sidecar.id = song.record.id
            song.record.hasDerivedID = true
            return song
        }
        let id = SongID(ids.next())
        let now = SegueJSON.stamp(clock.now())
        var sidecar = song.record.sidecar
        sidecar.id = id
        sidecar.schemaVersion = Sidecar.currentSchemaVersion
        sidecar.createdAt = now
        sidecar.updatedAt = now
        let data = try SidecarCodec.encode(sidecar)
        let url = sidecarURL(slug: song.slug)
        try fileSystem.writeAtomically(data, to: url)
        song.sidecarData = data
        song.sidecarStamp = try FileStamp(fileSystem.attributes(at: url))
        song.record.sidecar = sidecar
        song.record.id = id
        song.record.hasDerivedID = false
        return song
    }

    // MARK: Conflict checks

    /// The `.cho` bytes on disk now, or nil when the file is gone.
    func currentSource(slug: String) throws -> Data? {
        let url = choURL(slug: slug)
        guard fileSystem.fileExists(at: url) else { return nil }
        return try fileSystem.readData(at: url)
    }

    /// The sidecar bytes on disk now, or nil when the file is gone.
    func currentSidecar(slug: String) throws -> Data? {
        let url = sidecarURL(slug: slug)
        guard fileSystem.fileExists(at: url) else { return nil }
        return try fileSystem.readData(at: url)
    }

    // MARK: Decoding

    /// A decoded sidecar: its metadata, why it blocks edits (if it does), and whether its ID
    /// had to be derived because none could be recovered.
    struct DecodedSidecar {
        var sidecar: Sidecar
        var readOnly: ReadOnlyReason?
        var derivedID: Bool
    }

    func decodeSidecar(_ data: Data, slug: String, previous: LoadedSong?) -> DecodedSidecar {
        let now = SegueJSON.stamp(clock.now())
        // An ID this session already knew for the file beats a derived one: setlists that
        // reference it keep resolving until the next launch.
        let knownID = previous.flatMap { $0.record.hasDerivedID ? nil : $0.record.id }
        let fallbackID = knownID ?? Self.derivedID(slug: slug)
        switch SidecarCodec.decode(data, fallbackDate: now) {
        case let .editable(sidecar, _):
            return DecodedSidecar(sidecar: sidecar, readOnly: nil, derivedID: false)
        case let .newer(sidecar, found):
            let fallback = Sidecar(
                schemaVersion: found,
                id: fallbackID,
                createdAt: now,
                updatedAt: now,
            )
            return DecodedSidecar(
                sidecar: sidecar ?? fallback,
                readOnly: .newerSchema(found: found, supported: Sidecar.currentSchemaVersion),
                derivedID: sidecar == nil && knownID == nil,
            )
        case let .unreadable(message, salvagedID):
            // Placeholder metadata in memory only; the file on disk stays untouched.
            return DecodedSidecar(
                sidecar: Sidecar(id: salvagedID ?? fallbackID, createdAt: now, updatedAt: now),
                readOnly: .unreadableSidecar(message: message),
                derivedID: salvagedID == nil && knownID == nil,
            )
        }
    }

    /// Decodes `.cho` bytes. Anything but UTF-8 is shown with a best-guess encoding and
    /// flagged read-only, so a save never rewrites bytes the guess may have got wrong.
    static func decodeText(_ data: Data) -> (String, ReadOnlyReason?) {
        if let text = String(bytes: data, encoding: .utf8) {
            return (text, nil)
        }
        let hasUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        if hasUTF16BOM, let text = String(bytes: data, encoding: .utf16) {
            return (text, .notUTF8(encoding: "UTF-16"))
        }
        if let text = String(bytes: data, encoding: .windowsCP1252) {
            return (text, .notUTF8(encoding: "Windows Latin 1"))
        }
        // ISO Latin 1 maps every byte to a character, so this never fails.
        let text = String(bytes: data, encoding: .isoLatin1) ?? ""
        return (text, .notUTF8(encoding: "ISO Latin 1"))
    }

    /// A stable ID for a song whose sidecar holds no recoverable ID: the SHA-256 of its path,
    /// with a zero timestamp so derived IDs are recognisable. Unchanged across launches while
    /// the file keeps its name.
    static func derivedID(slug: String) -> SongID {
        let digest = SHA256.hash(data: Data("segue.derived-id:\(relativePath(slug: slug))".utf8))
        return SongID(ULID(milliseconds: 0, randomness: Array(digest.prefix(10))))
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func describe(_ error: any Error) -> String {
        (error as NSError).localizedDescription
    }
}
