import ChordPro
import Library
import MusicTheory

/// The set essentials (R80): key, tempo and length, what set timing and flow need. The
/// song card shows a dot on each missing one; library rows and the builder's library
/// column show one quiet dot for a song missing any (R110).
enum SetEssential: String, Sendable, Hashable, CaseIterable {
    case key
    case tempo
    case length

    /// The help tag on every essentials dot.
    static let help = "Set essential: used for set timing and flow"

    /// The essentials `metadata` lacks, in card order. A `{key}` that does not parse
    /// counts as missing.
    ///
    /// Shim: P3-6 owns the one definition of "missing essentials" (`SongEssentials` in
    /// SegueCore, next to `SongFilter`). Until it lands this mirrors that rule; then this
    /// delegates to it and the shim goes.
    static func missing(in metadata: Metadata) -> [Self] {
        allCases.filter { essential in
            switch essential {
            case .key: metadata.key.flatMap(SongKey.init(parsing:)) == nil
            case .tempo: metadata.tempo == nil
            case .length: metadata.duration == nil
            }
        }
    }

    /// "Missing key, tempo and length", for VoiceOver.
    static func spokenMissing(_ missing: [Self]) -> String {
        let names = missing.map(\.rawValue)
        let list = switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
        return list.isEmpty ? "" : "Missing \(list)"
    }
}

extension SongRecord {
    /// The set essentials this song lacks.
    var missingEssentials: [SetEssential] {
        SetEssential.missing(in: document.metadata)
    }
}
