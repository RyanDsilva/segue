// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 9.3). Which play of
// its section each annotated section is (a fill's "Shows on" counts them), and the section
// energy walk-ups and fills lean on. Pure.

import Editing

/// Per annotated section: the written content it plays (a `{chorus}` stub plays its chorus),
/// which play of that content it is, and each content's number of plays (P8-2's
/// "Chorus 2/3").
struct SectionPlays {
    var content: [Int] = []
    var occurrence: [Int] = []
    var total: [Int: Int] = [:]

    init(sections: [RenderSection], origins: [Int]) {
        for index in sections.indices {
            let origin = origins.indices.contains(index) ? origins[index] : index
            var played = origin
            if sections[index].isRepeat, sections[index].items.isEmpty,
               let target = SongSections.repeatTarget(of: index, in: sections)
            {
                played = origins.indices.contains(target) ? origins[target] : target
            }
            total[played, default: 0] += 1
            content.append(played)
            occurrence.append(total[played] ?? 1)
        }
    }
}

public extension BassLine {
    /// A section raises the energy (chorus, bridge, pre-chorus: true), settles it (verse,
    /// outro: false), else nil: what walk-ups and fills into it lean on.
    static func sectionEnergy(_ section: RenderSection) -> Bool? {
        let label = (SectionNotes.label(of: section) ?? "").lowercased()
        switch section.kind {
        case .bridge, .chorus: return true
        case .verse: return false
        default:
            if label.hasPrefix("pre-chorus") || label.hasPrefix("chorus") {
                return true
            }
            if label.hasPrefix("outro") {
                return false
            }
            return nil
        }
    }
}
