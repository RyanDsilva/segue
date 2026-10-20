import Library

// The set essentials (R80) are defined once, in SegueCore (`SetEssential`, `SongEssentials`).
// This adds only their presentation: the song card shows a dot on each missing one; library
// rows and the builder's library column show one quiet dot for a song missing any (R110).

extension SetEssential {
    /// The help tag on every essentials dot.
    static let help = "Set essential: used for set timing and flow"

    /// "Missing key, length and tempo", for VoiceOver.
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
        SongEssentials.missing(in: document)
    }
}
