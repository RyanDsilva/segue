import Foundation
import Support

/// Reads and writes `Sidecar` files with schema versioning:
///
/// - current version: decoded as is;
/// - older (incl. pre-versioned files without `schemaVersion`, i.e. version 0): migrated
///   forward in memory, written back at the current version on the next save;
/// - newer: decoded leniently and opened read-only, never rewritten;
/// - undecodable: reported, never rewritten.
enum SidecarCodec {
    /// Forward migrations, `steps[n]` takes version `n` to `n + 1`.
    static let migrator = SchemaMigrator(
        currentVersion: Sidecar.currentSchemaVersion,
        steps: [
            // v0: pre-versioned sidecar; any field but `id` may be missing.
            0: { object in
                object["tags"] = object["tags"] ?? [String]()
                object["displayPrefs"] = object["displayPrefs"] ?? [String: Any]()
                if object["createdAt"] == nil {
                    object["createdAt"] = object["updatedAt"]
                }
                if object["updatedAt"] == nil {
                    object["updatedAt"] = object["createdAt"]
                }
            },
            // v1 -> v2: `displayPrefs` gains the phase 1 view toggles. A v1 object is kept
            // (fields it already has survive; missing ones take their defaults when
            // decoded leniently); anything that is not an object is replaced by defaults.
            1: { object in
                if !(object["displayPrefs"] is [String: Any]) {
                    object["displayPrefs"] = [String: Any]()
                }
            },
            // v2 -> v3: `cues` and `live` are new; both decode leniently with defaults.
            2: { object in
                object["cues"] = object["cues"] ?? [Any]()
                if !(object["live"] is [String: Any]) {
                    object["live"] = [String: Any]()
                }
            },
        ],
    )

    enum Decoded: Equatable {
        /// Usable and editable. `migratedFrom` is set when the file is at an older version.
        case editable(Sidecar, migratedFrom: Int?)
        /// Written by a newer Segue: best-effort fields, read-only.
        case newer(Sidecar?, found: Int)
        /// Not decodable. `salvagedID` is the `id` field if it could still be read.
        case unreadable(message: String, salvagedID: SongID?)
    }

    static func decode(_ data: Data, fallbackDate: Date) -> Decoded {
        let outcome: SchemaMigrator.Outcome
        do {
            outcome = try migrator.migrate(data)
        } catch {
            return .unreadable(message: describe(error), salvagedID: salvageID(from: data))
        }
        do {
            switch outcome {
            case let .current(json):
                // Every field but `id` is optional and decoded on its own: a current-version
                // file missing `displayPrefs`, `live` or another optional field (hand-edited,
                // or written by a tool) still opens editable with that field's default.
                guard let sidecar = try lenient(json, fallbackDate: fallbackDate) else {
                    return .unreadable(message: "missing id", salvagedID: nil)
                }
                return .editable(sidecar, migratedFrom: nil)
            case let .migrated(json, version):
                guard let sidecar = try lenient(json, fallbackDate: fallbackDate) else {
                    return .unreadable(message: "missing id", salvagedID: nil)
                }
                return .editable(sidecar, migratedFrom: version)
            case let .newer(found):
                let partial = try? SegueJSON.decode(PartialSidecar.self, from: data)
                return .newer(partial?.complete(schemaVersion: found), found: found)
            }
        } catch {
            return .unreadable(message: describe(error), salvagedID: salvageID(from: data))
        }
    }

    /// `json` decoded field by field at the current version; nil without a usable `id`.
    private static func lenient(_ json: Data, fallbackDate: Date) throws -> Sidecar? {
        var object = try SegueJSON.decode(PartialSidecar.self, from: json)
        object.createdAt = object.createdAt ?? fallbackDate
        object.updatedAt = object.updatedAt ?? object.createdAt
        return object.complete(schemaVersion: Sidecar.currentSchemaVersion)
    }

    static func encode(_ sidecar: Sidecar) throws -> Data {
        try SegueJSON.encode(sidecar)
    }

    /// The `id` field of a sidecar that otherwise fails to decode, if it is a valid ULID, so
    /// setlists keep resolving the song. Falls back to a textual scan when the JSON itself is
    /// malformed (e.g. a truncated file).
    private static func salvageID(from data: Data) -> SongID? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return (object["id"] as? String).flatMap(ULID.init(string:)).map(SongID.init)
        }
        guard let text = String(bytes: data, encoding: .utf8),
              let match = text.firstMatch(of: /"id"\s*:\s*"([0-9A-Za-z]{26})"/)
        else {
            return nil
        }
        return ULID(string: String(match.output.1)).map(SongID.init)
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case let error as SchemaMigrationError:
            error.description
        case let DecodingError.dataCorrupted(context),
             let DecodingError.keyNotFound(_, context),
             let DecodingError.typeMismatch(_, context),
             let DecodingError.valueNotFound(_, context):
            context.codingPath.isEmpty
                ? context.debugDescription
                : "\(context.codingPath.map(\.stringValue).joined(separator: ".")): "
                + context.debugDescription
        default:
            "invalid JSON"
        }
    }
}

/// Every sidecar field optional, each decoded independently so one bad or unknown-shaped
/// field (from a newer schema) does not hide the others.
private struct PartialSidecar: Decodable {
    var id: SongID?
    var tags: [String]?
    var proficiency: Proficiency?
    var notes: String?
    var cues: [SongCue]?
    var displayPrefs: DisplayPrefs?
    var live: LivePrefs?
    var createdAt: Date?
    var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case tags
        case proficiency
        case notes
        case cues
        case displayPrefs
        case live
        case createdAt
        case updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(SongID.self, forKey: .id)
        tags = try? container.decodeIfPresent([String].self, forKey: .tags)
        proficiency = try? container.decodeIfPresent(Proficiency.self, forKey: .proficiency)
        notes = try? container.decodeIfPresent(String.self, forKey: .notes)
        cues = Self.lenientCues(container)
        displayPrefs = try? container.decodeIfPresent(DisplayPrefs.self, forKey: .displayPrefs)
        live = try? container.decodeIfPresent(LivePrefs.self, forKey: .live)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func complete(schemaVersion: Int) -> Sidecar? {
        guard let id else { return nil }
        let created = createdAt ?? updatedAt ?? .distantPast
        return Sidecar(
            schemaVersion: schemaVersion,
            id: id,
            tags: tags ?? [],
            proficiency: proficiency,
            notes: notes,
            cues: cues ?? [],
            displayPrefs: displayPrefs ?? DisplayPrefs(),
            live: live ?? LivePrefs(),
            createdAt: created,
            updatedAt: updatedAt ?? created,
        )
    }

    /// Cues one by one, so one malformed cue does not hide the others.
    private static func lenientCues(_ container: KeyedDecodingContainer<CodingKeys>) -> [SongCue]? {
        struct Lenient: Decodable {
            var cue: SongCue?

            init(from decoder: any Decoder) throws {
                cue = try? SongCue(from: decoder)
            }
        }
        return (try? container.decodeIfPresent([Lenient].self, forKey: .cues))?
            .compactMap(\.cue)
    }
}
