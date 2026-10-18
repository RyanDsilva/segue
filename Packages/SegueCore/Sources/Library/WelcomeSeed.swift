import Foundation
import Support

/// A seed manifest (`manifest.json`, schema 1): songs to add to a library with their
/// metadata, plus an optional demo setlist. The Welcome library (WS2b 4.2) is one such
/// folder; WS5's screenshot-only songs are another. The seeder is generic over both.
///
/// ```json
/// { "schema": 1, "tag": "Welcome",
///   "songs": [ { "file": "a.cho", "tags": ["Welcome"], "proficiency": "pro",
///                "notes": "...",
///                "cues": [ { "section": "Chorus", "occurrence": 3, "text": "..." } ],
///                "live": { "columns": 2 } } ],
///   "setlist": { "name": "Welcome Set", "targetDuration": 1200,
///                "entries": [ { "song": "a.cho", "overrides": { "transpose": -2 },
///                               "note": "..." } ] } }
/// ```
///
/// `tag` is the seed's identity: a song that carries it, has the same title and has
/// byte-identical source is the seeded song (idempotency, "Remove Welcome Songs").
/// Unknown keys are ignored; a schema major other than 1 is rejected.
public struct SeedManifest: Sendable, Equatable, Decodable {
    /// The manifest file name inside a seed folder.
    public static let fileName = "manifest.json"
    /// The only schema major this build reads.
    public static let supportedSchema = 1

    public var schema: Int
    public var tag: String
    public var songs: [Song]
    public var setlist: SetlistPlan?

    public struct Song: Sendable, Equatable, Decodable {
        /// File name of the `.cho` inside the seed folder.
        public var file: String
        public var tags: [String]
        public var proficiency: Proficiency?
        public var notes: String?
        public var cues: [SongCue]
        /// Live-mode memory to pin (only `columns` today); nil leaves the defaults.
        public var live: Live?

        private enum CodingKeys: String, CodingKey {
            case file
            case tags
            case proficiency
            case notes
            case cues
            case live
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decode(String.self, forKey: .file)
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            proficiency = try container.decodeIfPresent(Proficiency.self, forKey: .proficiency)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            cues = try container.decodeIfPresent([SongCue].self, forKey: .cues) ?? []
            live = try container.decodeIfPresent(Live.self, forKey: .live)
        }
    }

    public struct Live: Sendable, Equatable, Decodable {
        public var columns: Int?
    }

    /// The demo setlist. Overrides are plain values here because `Setlists` depends on
    /// `Library`, not the other way round; the app maps them onto `SetlistOverrides`.
    public struct SetlistPlan: Sendable, Equatable, Decodable {
        public var name: String
        /// Planned length in seconds.
        public var targetDuration: TimeInterval?
        public var entries: [Entry]
    }

    public struct Entry: Sendable, Equatable, Decodable {
        /// The manifest song's `file`.
        public var song: String
        public var overrides: Overrides?
        public var note: String?
    }

    public struct Overrides: Sendable, Equatable, Decodable {
        public var transpose: Int?
        public var capo: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case tag
        case songs
        case setlist
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        guard schema == Self.supportedSchema else {
            throw SeedError.unsupportedSchema(schema)
        }
        tag = try container.decode(String.self, forKey: .tag)
        songs = try container.decode([Song].self, forKey: .songs)
        setlist = try container.decodeIfPresent(SetlistPlan.self, forKey: .setlist)
    }

    /// Reads and validates `<folder>/manifest.json`: a known schema, a non-blank tag, unique
    /// song files that exist in the folder, and setlist entries that name manifest songs.
    public static func load(fromFolder folder: URL, fileSystem: any FileSystem) throws -> Self {
        let data: Data
        do {
            data = try fileSystem.readData(at: folder.appending(path: fileName))
        } catch {
            throw SeedError.manifestUnreadable(SongFiles.describe(error))
        }
        let manifest: Self
        do {
            manifest = try JSONDecoder().decode(Self.self, from: data)
        } catch let error as SeedError {
            throw error
        } catch {
            throw SeedError.manifestUnreadable(String(describing: error))
        }
        guard !manifest.tag.allSatisfy(\.isWhitespace) else {
            throw SeedError.manifestUnreadable("The manifest has no tag.")
        }
        var files: Set<String> = []
        for song in manifest.songs {
            guard files.insert(song.file).inserted else {
                throw SeedError.manifestUnreadable("\(song.file) is listed twice.")
            }
            guard fileSystem.fileExists(at: folder.appending(path: song.file)) else {
                throw SeedError.missingFile(song.file)
            }
        }
        for entry in manifest.setlist?.entries ?? [] where !files.contains(entry.song) {
            throw SeedError.unknownSetlistSong(entry.song)
        }
        return manifest
    }
}

/// Why a seed could not be read or written. Songs written before a failure stay (they carry
/// the seed's tag), and a retry is idempotent.
public enum SeedError: Error, Equatable {
    /// `manifest.json` is missing, not valid JSON or not a valid manifest.
    case manifestUnreadable(String)
    /// The manifest's schema major is not one this build reads.
    case unsupportedSchema(Int)
    /// A manifest song file is not in the seed folder.
    case missingFile(String)
    /// A setlist entry names a file that is not one of the manifest's songs.
    case unknownSetlistSong(String)
    /// A song file in the seed folder is not UTF-8 text.
    case unreadableSong(String)
    /// Writing a song into the library failed (read-only folder, disk full).
    case writeFailed(file: String, reason: String)
}

/// One manifest song as it stands in the library after a seed.
public struct SeededSong: Sendable, Equatable {
    /// The manifest's `file` (setlist entries refer to songs by it).
    public var file: String
    public var record: SongRecord
    /// True when this seed created it; false when an earlier seed's song was reused.
    public var created: Bool

    public init(file: String, record: SongRecord, created: Bool) {
        self.file = file
        self.record = record
        self.created = created
    }
}

/// The songs carrying a seed's tag, split by whether they still match a seed original.
public struct SeedInventory: Sendable, Equatable {
    /// Same title and byte-identical source as a manifest song.
    public var unmodified: [SongRecord]
    /// Carry the tag but were edited (or are not from the manifest at all).
    public var edited: [SongRecord]

    public init(unmodified: [SongRecord], edited: [SongRecord]) {
        self.unmodified = unmodified
        self.edited = edited
    }
}
