// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.6). How a walk-up reads to
// VoiceOver: "walk up A, B into C". Pure.

import MusicTheory

public extension BassLine {
    /// "walk up A, B into C"; a chromatic note adds "outside the key".
    static func spoken(
        _ candidate: WalkUpCandidate,
        names: [String],
        into: String,
    ) -> String {
        let verb = switch candidate.direction {
        case .up: "walk up"
        case .down: "walk down"
        case .neither: "walk"
        }
        let notes = zip(names, candidate.chromatic).map { name, chromatic in
            spokenNote(name) + (chromatic ? " outside the key" : "")
        }
        return "\(verb) \(notes.joined(separator: ", ")) into \(spokenNote(into))"
    }

    /// "C sharp", "B flat".
    static func spokenNote(_ name: String) -> String {
        guard name.count > 1 else { return name }
        let letter = String(name.prefix(1))
        return switch name.dropFirst() {
        case "#": letter + " sharp"
        case "b": letter + " flat"
        default: name
        }
    }
}
