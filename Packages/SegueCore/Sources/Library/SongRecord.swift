import ChordPro
import Foundation
import Support

/// Stable identity of a song: a ULID stored in its sidecar, unchanged by renames.
public struct SongID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let ulid: ULID

    public init(_ ulid: ULID) {
        self.ulid = ulid
    }

    public var description: String {
        ulid.description
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.ulid < rhs.ulid
    }

    public init(from decoder: any Decoder) throws {
        ulid = try ULID(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try ulid.encode(to: encoder)
    }
}

/// Why a song (or setlist) is open read-only. Implementers may add cases.
public enum ReadOnlyReason: Sendable, Equatable, Hashable {
    /// The file's `schemaVersion` is newer than this app supports ("created by a newer
    /// Segue - update to edit"). Still performable and searchable; never rewritten.
    case newerSchema(found: Int, supported: Int)
    /// The sidecar exists but could not be decoded. The song text stays usable; the sidecar
    /// is left untouched so no data is lost.
    case unreadableSidecar(message: String)
    /// The `.cho` file is not valid UTF-8. It is shown decoded as `encoding` (a best guess)
    /// and never rewritten, so saving can't silently change bytes the guess got wrong.
    case notUTF8(encoding: String)
}

/// Which bytes on disk a `SongRecord` was loaded from (or written as). An edit saved
/// against a revision is refused with `LibraryError.conflict` when the `.cho` on disk no
/// longer matches it, so an external edit made while the editor was open is never
/// silently overwritten.
public struct SongRevision: Sendable, Hashable {
    /// SHA-256 (hex) of the `.cho` bytes.
    public var contentHash: String
    /// SHA-256 (hex) of the sidecar bytes; nil when the sidecar was not on disk.
    public var sidecarHash: String?

    public init(contentHash: String, sidecarHash: String?) {
        self.contentHash = contentHash
        self.sidecarHash = sidecarHash
    }
}

/// A song as the library knows it: canonical text, parsed AST and its sidecar.
public struct SongRecord: Sendable, Equatable, Identifiable {
    public var id: SongID
    /// Path of the `.cho` file relative to the library root (e.g. `songs/wonderwall.cho`).
    public var relativePath: String
    /// The `.cho` file contents, exactly as on disk.
    public var source: String
    /// `source` parsed.
    public var document: SongDocument
    /// Parser diagnostics for `source`.
    public var diagnostics: [Diagnostic]
    /// App-only metadata.
    public var sidecar: Sidecar
    /// Non-nil when edits are blocked.
    public var readOnly: ReadOnlyReason?
    /// The on-disk bytes this record reflects; pass it back to `updateSong` when saving.
    public var revision: SongRevision
    /// True when the ID is not stored in a sidecar (the sidecar is unreadable without an
    /// `id`, or could not be created) and was derived from the file path instead. Stable
    /// across launches while the file keeps its name, but lost if the file is renamed, so
    /// setlist references to it are fragile.
    public var hasDerivedID: Bool

    public init(
        id: SongID,
        relativePath: String,
        source: String,
        document: SongDocument,
        diagnostics: [Diagnostic],
        sidecar: Sidecar,
        readOnly: ReadOnlyReason? = nil,
        revision: SongRevision = SongRevision(contentHash: "", sidecarHash: nil),
        hasDerivedID: Bool = false,
    ) {
        self.id = id
        self.relativePath = relativePath
        self.source = source
        self.document = document
        self.diagnostics = diagnostics
        self.sidecar = sidecar
        self.readOnly = readOnly
        self.revision = revision
        self.hasDerivedID = hasDerivedID
    }

    /// Whether edits are blocked.
    public var isReadOnly: Bool {
        readOnly != nil
    }
}
