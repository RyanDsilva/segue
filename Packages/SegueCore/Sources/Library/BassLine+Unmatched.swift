// P8-4b (docs/phases/8-workstreams/P8-4-bass.md sections 8.9, 8.11). Saved walk-ups that no
// longer match the song, for the Walk-ups list's footer: which, and how to describe them.

import ChordPro
import Editing
import MusicTheory

public extension BassLine {
    /// The saved picks of `prefs` that no longer resolve against the song (kept in the
    /// sidecar, never applied, listed with Remove).
    static func unmatched(
        _ model: RenderModel,
        document: SongDocument,
        prefs: BassPrefs,
    ) -> [WalkUpPick] {
        guard !prefs.walkUps.isEmpty else { return [] }
        return ChordAnchors.resolve(
            prefs.walkUps,
            units: SongSections.units(of: document),
            sections: model.sections,
        ).unmatched
    }
}

public extension WalkUpPick {
    /// The section the pick was saved in: "Verse 1", "Chorus (2nd)", "After Verse 2",
    /// "Lead-in".
    var sectionName: String {
        func name(_ ref: SectionRef) -> String {
            ref.occurrence > 1 ? "\(ref.label) (\(Self.ordinal(ref.occurrence)))" : ref.label
        }
        switch anchor.section {
        case let .section(ref):
            return name(ref)
        case let .loose(after?, _):
            return "After \(name(after))"
        case .loose(nil, _):
            return "Lead-in"
        }
    }

    /// "Verse 1: G \u{2192} C, A B" as saved: the written basses and the picked notes in
    /// `key` (the song's written key), "Nothing" for a hold.
    func savedSummary(key: SongKey?) -> String {
        "\(sectionName): \(anchor.from) \u{2192} \(to), " + savedNotes(key: key)
    }

    /// The picked notes rebuilt at written pitch ("A B"), "Nothing" for a hold.
    func savedNotes(key: SongKey?) -> String {
        guard kind != .hold, !offsets.isEmpty,
              let from = ChordSymbol(parsing: anchor.from),
              let target = ChordSymbol(parsing: to),
              let candidate = WalkUp.candidate(
                  kind: kind,
                  offsets: offsets,
                  from: from.root.pitchClass,
                  to: target.root.pitchClass,
                  context: .legacy(key: key, from: from, to: target),
              )
        else { return "Nothing" }
        return candidate.notes.map(\.chartName).joined(separator: " ")
    }

    private static func ordinal(_ number: Int) -> String {
        let suffix = switch number % 100 {
        case 11, 12, 13: "th"
        default: switch number % 10 {
            case 1: "st"
            case 2: "nd"
            case 3: "rd"
            default: "th"
            }
        }
        return "\(number)\(suffix)"
    }
}
