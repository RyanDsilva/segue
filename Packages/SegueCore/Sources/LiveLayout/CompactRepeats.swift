// Owner: P9-1. The print-only Compact repeats option (spec 5.6, R158 Q9, R178): a Full pass
// that is identical, as laid out, to an earlier printed Full pass of the same part prints as
// one reference row. Never a guess: anything that differs keeps the pass written out.

import Editing

/// A pass printed as a reference row, and the pass it points at.
struct CompactReference: Hashable {
    /// The compacted pass's id (`MeasuredSection.id`).
    var pass: Int
    /// The written-out pass it repeats.
    var target: Int
    /// "Chorus 2 of 3: as Chorus 1", completed with " above" or " on page N".
    var prefix: String
}

enum CompactRepeats {
    /// The sections with every exact repeat replaced by a reference row, and the references.
    /// A pass compacts only when it and an earlier written-out pass are both Full, play the
    /// same part, carry the same items after `BassLine.annotate` (so a walk-up into what
    /// follows, a fill on one pass only or a changed chord keeps it written out), carry no
    /// cues, and the pass is numbered ("2 of 3").
    static func apply(
        _ sections: [MeasuredSection],
        measurer: Measurer,
    ) -> (sections: [MeasuredSection], references: [CompactReference]) {
        var result = sections
        var references: [CompactReference] = []
        var written: [MeasuredSection] = []
        for index in sections.indices {
            let section = sections[index]
            guard section.mode == .full, section.cues.isEmpty,
                  let number = section.passName.number,
                  let target = written.first(where: { Self.identical($0, section) }),
                  let targetNumber = target.passName.number
            else {
                written.append(section)
                continue
            }
            let title = section.passName.title
            let total = section.passName.total
            let prefix = "\(title) \(number) of \(total): as \(title) \(targetNumber)"
            let row = MeasuredItem.moreLines(measurer.paragraph(
                prefix + Self.above,
                role: .moreLines,
            ))
            result[index].items = [row]
            references.append(CompactReference(
                pass: section.id,
                target: target.id,
                prefix: prefix,
            ))
        }
        return (result, references)
    }

    static let above = " above"

    /// The reference row's text when the pass it repeats starts on another page.
    static func onPage(_ prefix: String, page: Int) -> String {
        "\(prefix) on page \(page)"
    }

    private static func identical(_ earlier: MeasuredSection, _ later: MeasuredSection) -> Bool {
        earlier.mode == .full && earlier.cues.isEmpty && earlier.source == later.source
            && !earlier.renderItems.isEmpty && earlier.renderItems == later.renderItems
    }
}
