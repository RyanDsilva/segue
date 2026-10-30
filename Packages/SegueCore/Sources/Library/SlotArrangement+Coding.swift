// Owner: P8-2. The schema-5 -> 6 arrangement migration (R149) and the anchor keys passes
// and known parts share.

import Foundation

public extension SlotArrangement {
    /// Rewrites a schema-5 arrangement object (`steps` with `plays`) into passes, in place:
    /// `plays` 0 (or below) is one Skip pass, `plays` n is `min(n, 9)` Full passes, no
    /// `plays` is one Full pass; `knownParts` lists the steps' distinct anchors with their
    /// `fp` (v5 listed every part, R123). The one function both the setlist (5 -> 6) and the
    /// show record (3 -> 4) migrations use, so they cannot drift.
    static func migrateV5(_ json: inout [String: Any]) {
        guard let steps = json["steps"] as? [Any] else { return }
        let anchorKeys = Set(AnchorCodingKeys.anchorKeys.map(\.stringValue))
        var passes: [Any] = []
        var known: [[String: Any]] = []
        for raw in steps {
            guard var step = raw as? [String: Any] else { continue }
            let plays = (step.removeValue(forKey: "plays") as? NSNumber)?.intValue ?? 1
            step.removeValue(forKey: "mode")
            let anchor = step.filter { anchorKeys.contains($0.key) }
            if !known.contains(where: { part in
                NSDictionary(dictionary: part.filter { anchorKeys.contains($0.key) })
                    .isEqual(to: anchor)
            }) {
                var part = anchor
                part["fp"] = step["fp"]
                known.append(part)
            }
            if plays <= 0 {
                var skipped = step
                skipped["mode"] = PassMode.skip.rawValue
                passes.append(skipped)
            } else {
                passes += Array(repeating: step as Any, count: min(plays, 9))
            }
        }
        json.removeValue(forKey: "steps")
        json["passes"] = passes
        json["knownParts"] = known
    }

    /// `migrateV5` on the `arrangement` of each object in `json[key]` (setlist entries, show
    /// items, a show's planned entries).
    static func migrateV5(arrangementsIn json: inout [String: Any], key: String) {
        guard let list = json[key] as? [Any] else { return }
        json[key] = list.map { raw -> Any in
            guard var object = raw as? [String: Any],
                  var arrangement = object["arrangement"] as? [String: Any]
            else { return raw }
            migrateV5(&arrangement)
            object["arrangement"] = arrangement
            return object
        }
    }
}

// MARK: - Anchor coding

/// The keys a pass and a known part share.
enum AnchorCodingKeys: String, CodingKey {
    case section
    case occurrence
    case loose
    case after
    case afterOccurrence
    case fingerprint = "fp"
    case mode

    /// The keys that name the part (not its fingerprint or mode).
    static let anchorKeys: [Self] = [.section, .occurrence, .loose, .after, .afterOccurrence]
}

extension SectionAnchor {
    static func decode(from container: KeyedDecodingContainer<AnchorCodingKeys>) throws -> Self {
        if let block = try container.decodeIfPresent(Int.self, forKey: .loose) {
            let after = try container.decodeIfPresent(String.self, forKey: .after).map { label in
                try SectionRef(
                    label: label,
                    occurrence: container.decodeIfPresent(Int.self, forKey: .afterOccurrence) ?? 1,
                )
            }
            return .loose(after: after, block: max(block, 1))
        }
        return try .section(SectionRef(
            label: container.decode(String.self, forKey: .section),
            occurrence: container.decodeIfPresent(Int.self, forKey: .occurrence) ?? 1,
        ))
    }

    func encode(to container: inout KeyedEncodingContainer<AnchorCodingKeys>) throws {
        switch self {
        case let .section(ref):
            try container.encode(ref.label, forKey: .section)
            try container.encode(ref.occurrence, forKey: .occurrence)
        case let .loose(after, block):
            try container.encode(block, forKey: .loose)
            if let after {
                try container.encode(after.label, forKey: .after)
                try container.encode(after.occurrence, forKey: .afterOccurrence)
            }
        }
    }

    /// The saved name: "Chorus", "Chorus 3rd" for a later occurrence, "Lead-in",
    /// "After Verse 2".
    public var summaryName: String {
        switch self {
        case let .section(ref):
            ref.occurrence > 1 ? "\(ref.label) \(SongSections.ordinal(ref.occurrence))" : ref.label
        case let .loose(after, _):
            after.map { "After \($0.label)" } ?? "Lead-in"
        }
    }
}
