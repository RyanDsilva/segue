// Owner: P3-16. Checking a slot's arrangement against the song as it is now (R122, R123),
// and the sections an arranged slot plays, for live layout.

import Editing
import Foundation

// MARK: - Resolution

/// One played row: a section of the song and how many times in a row.
public struct PlayedSection: Sendable, Hashable {
    /// Index into the song's `RenderModel.sections`.
    public var index: Int
    public var plays: Int

    public init(index: Int, plays: Int) {
        self.index = index
        self.plays = plays
    }
}

/// An arrangement checked against the song as it is now.
public enum ArrangementResolution: Sendable, Equatable {
    /// Every row still names a part of the song: the parts to play, in order, plus the parts
    /// the arrangement does not list (added to the song since; not played, not out of date).
    case applied(order: [PlayedSection], newSections: [SongSectionUnit])
    /// Some row no longer names a part (its label or occurrence is gone, or the content
    /// fingerprint changed): the stage shows the full song (R122).
    case outOfDate(missing: [ArrangementStep])

    public var isOutOfDate: Bool {
        if case .outOfDate = self {
            return true
        }
        return false
    }
}

public enum ArrangementResolver {
    /// Checks `arrangement` against the song's parts (`SongSections.units`).
    public static func resolve(
        _ arrangement: SlotArrangement,
        units: [SongSectionUnit],
    ) -> ArrangementResolution {
        var order: [PlayedSection] = []
        var missing: [ArrangementStep] = []
        var listed = Set<Int>()
        for step in arrangement.steps {
            guard let unit = unit(for: step, in: units) else {
                missing.append(step)
                continue
            }
            listed.insert(unit.index)
            if !step.isSkipped {
                order.append(PlayedSection(
                    index: unit.index,
                    plays: min(step.plays, SlotArrangement.maxPlays),
                ))
            }
        }
        guard missing.isEmpty, !order.isEmpty else {
            return .outOfDate(missing: missing)
        }
        return .applied(order: order, newSections: units.filter { !listed.contains($0.index) })
    }

    /// The song's part a row names, when its anchor and fingerprint still match.
    public static func unit(
        for step: ArrangementStep,
        in units: [SongSectionUnit],
    ) -> SongSectionUnit? {
        guard let unit = units.first(where: { $0.anchor.matches(step.anchor) }) else {
            return nil
        }
        if let fingerprint = step.fingerprint, fingerprint != unit.fingerprint {
            return nil
        }
        return unit
    }
}

// MARK: - Arranged sections (live layout)

/// One section as an arranged slot plays it.
public struct ArrangedSection: Sendable, Equatable {
    /// The section to lay out: a `{chorus}` repeat is written out with its chorus's lines (so
    /// skipping the written chorus never leaves a dangling "Repeat chorus"); `id` is the
    /// position in the arranged list (unique even when a section plays twice).
    public var section: RenderSection
    /// Index into the song's `RenderModel.sections`.
    public var source: Int
    /// The first time this source section is played (cues show here only).
    public var isFirstPlay: Bool
}

public enum ArrangedSections {
    /// The sections in played order, each played section repeated `plays` times.
    public static func build(
        _ sections: [RenderSection],
        order: [PlayedSection],
    ) -> [ArrangedSection] {
        var result: [ArrangedSection] = []
        var played = Set<Int>()
        for step in order where sections.indices.contains(step.index) {
            var section = sections[step.index]
            if section.isRepeat, let target = SongSections.repeatTarget(
                of: step.index,
                in: sections,
            ) {
                section.items = sections[target].items
                section.isRepeat = false
                section.kind = section.kind ?? .chorus
            }
            for _ in 0 ..< max(step.plays, 1) {
                var copy = section
                copy.id = result.count
                result.append(ArrangedSection(
                    section: copy,
                    source: step.index,
                    isFirstPlay: played.insert(step.index).inserted,
                ))
            }
        }
        return result
    }
}
