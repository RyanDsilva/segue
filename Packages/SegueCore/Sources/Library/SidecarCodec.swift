import CryptoKit
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
            // v3 -> v4: each cue gains a stable `id` (and, when placed on one occurrence, an
            // optional `fp`). The IDs are derived on decode (`PartialSidecar.repairCueIDs`), the
            // same path that repairs a hand-edited v4 file, so nothing changes here.
            3: { _ in },
            // v4 -> v5: `bass` is new (P8-4b); an absent one decodes as empty.
            4: { _ in },
            // v5 -> v6: `parts` is new (P8-7c); an absent one decodes as empty.
            5: { _ in },
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
                var partial = try? SegueJSON.decode(PartialSidecar.self, from: data)
                partial?.repairCueIDs()
                return .newer(partial?.complete(schemaVersion: found), found: found)
            }
        } catch {
            return .unreadable(message: describe(error), salvagedID: salvageID(from: data))
        }
    }

    /// `json` decoded field by field at the current version; nil without a usable `id`.
    private static func lenient(_ json: Data, fallbackDate: Date) throws -> Sidecar? {
        var object = try SegueJSON.decode(PartialSidecar.self, from: json)
        object.repairCueIDs()
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
/// field (from a newer schema) does not hide the others. Keys the sidecar does not model,
/// values it cannot read (an enum case from a newer Segue) and unreadable cues or parts are
/// kept in `unknown` and written back on save (docs/architecture/data-compatibility.md).
struct PartialSidecar: Decodable {
    var id: SongID?
    var tags: [String]?
    var proficiency: Proficiency?
    var notes: String?
    var cues: [SongCue]?
    var displayPrefs: DisplayPrefs?
    var live: LivePrefs?
    var bass: BassPrefs?
    var parts: [Part]?
    var createdAt: Date?
    var updatedAt: Date?
    var unknown: UnknownFields

    init(from decoder: any Decoder) throws {
        var object = try LenientObject<Sidecar.CodingKeys>(decoder)
        id = object.value(.id)
        tags = object.value(.tags)
        proficiency = object.value(.proficiency)
        notes = object.value(.notes)
        cues = object.elements(.cues)
        displayPrefs = object.value(.displayPrefs)
        live = object.value(.live)
        bass = object.value(.bass)
        parts = object.elements(.parts)
        createdAt = object.value(.createdAt)
        updatedAt = object.value(.updatedAt)
        unknown = object.unknown
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
            bass: bass ?? BassPrefs(),
            parts: parts ?? [],
            createdAt: created,
            updatedAt: updatedAt ?? created,
            unknown: unknown,
        )
    }

    /// Gives every cue a usable, unique `id` (schema 4, P3-17): a cue without one (a v3 file
    /// being migrated, or a hand-edited file) and every later duplicate of an `id` get a
    /// derived ID. Derived IDs are deterministic, so re-reading a file before it is saved,
    /// or another device migrating the same file, yields the same IDs: the timestamp is the
    /// file's `createdAt` (else the Unix epoch), the randomness the first 80 bits of a
    /// SHA-256 over the song ID, the cue's index and its content.
    mutating func repairCueIDs() {
        guard let id, var cues else { return }
        var seen: Set<CueID> = []
        for index in cues.indices {
            let cue = cues[index]
            if cue.id == .unassigned || seen.contains(cue.id) {
                cues[index].id = Self.derivedCueID(song: id, index: index, cue: cue, at: createdAt)
            }
            seen.insert(cues[index].id)
        }
        self.cues = cues
    }

    static func derivedCueID(song: SongID, index: Int, cue: SongCue, at created: Date?) -> CueID {
        let occurrence = cue.occurrence.map(String.init) ?? "*"
        let key = "segue.cue-id:\(song)|\(index)|\(cue.section)|\(occurrence)|\(cue.text)"
        let digest = SHA256.hash(data: Data(key.utf8))
        return CueID(ULID(
            timestamp: created ?? Date(timeIntervalSince1970: 0),
            randomness: Array(digest.prefix(10)),
        ))
    }
}
