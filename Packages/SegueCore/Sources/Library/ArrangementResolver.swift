// Owner: P3-16, P8-2. Checking a slot's arrangement against the song as it is now (R122,
// R123, R149), and the passes an arranged slot shows, for live layout.

import ChordPro
import Editing
import Foundation

// MARK: - Resolution

/// One shown pass: a part of the song and how it is shown.
public struct PlayedPass: Sendable, Hashable {
    /// The part: index into the song's `RenderModel.sections`.
    public var index: Int
    /// Never `.skip`.
    public var mode: PassMode
    /// Index into `SlotArrangement.passes`; nil for the full song.
    public var position: Int?

    public init(index: Int, mode: PassMode = .full, position: Int? = nil) {
        self.index = index
        self.mode = mode
        self.position = position
    }
}

/// An arrangement checked against the song as it is now.
public enum ArrangementResolution: Sendable, Equatable {
    /// Every pass still names a part of the song: the shown passes, in order, plus the parts
    /// the arrangement neither plays nor knew (added to the song since; not played, not out
    /// of date).
    case applied(order: [PlayedPass], newSections: [SongSectionUnit])
    /// Some pass no longer names a part (its label or occurrence is gone, or the content
    /// fingerprint changed), or the arrangement breaks an invariant (`problems`): the stage
    /// shows the full song (R122).
    case outOfDate(missing: [ArrangementPass])

    public var isOutOfDate: Bool {
        if case .outOfDate = self {
            return true
        }
        return false
    }
}

public enum ArrangementResolver {
    /// Checks `arrangement` against the song's parts (`SongSections.units`). Skip passes are
    /// resolved (an unresolvable one still makes the arrangement out of date) but left out
    /// of `order`.
    public static func resolve(
        _ arrangement: SlotArrangement,
        units: [SongSectionUnit],
    ) -> ArrangementResolution {
        var order: [PlayedPass] = []
        var missing: [ArrangementPass] = []
        var listed = Set<Int>()
        for (position, pass) in arrangement.passes.enumerated() {
            guard let unit = unit(for: pass, in: units) else {
                missing.append(pass)
                continue
            }
            listed.insert(unit.index)
            if pass.isShown {
                order.append(PlayedPass(index: unit.index, mode: pass.mode, position: position))
            }
        }
        guard missing.isEmpty, !order.isEmpty, arrangement.problems.isEmpty else {
            return .outOfDate(missing: missing)
        }
        let known = arrangement.effectiveKnownParts
        let new = units.filter { unit in
            !listed.contains(unit.index) && !known.contains { $0.anchor.matches(unit.anchor) }
        }
        return .applied(order: order, newSections: new)
    }

    /// The song's part a pass names, when its anchor and fingerprint still match.
    public static func unit(
        for pass: ArrangementPass,
        in units: [SongSectionUnit],
    ) -> SongSectionUnit? {
        guard let unit = units.first(where: { $0.anchor.matches(pass.anchor) }) else {
            return nil
        }
        // A pass saved before R146 carries the comment-including fingerprint.
        if let fingerprint = pass.fingerprint, fingerprint != unit.fingerprint,
           fingerprint != unit.legacyFingerprint
        {
            return nil
        }
        return unit
    }

    /// The song as written: every part once, Full, in song order.
    public static func fullSong(_ units: [SongSectionUnit]) -> [PlayedPass] {
        units.map { PlayedPass(index: $0.index) }
    }
}

// MARK: - Arranged sections (live layout)

/// One shown pass as the stage lays it out.
public struct ArrangedSection: Sendable, Equatable {
    /// The section to lay out: a `{chorus}` repeat is written out with its chorus's lines
    /// (so skipping the written chorus never leaves a dangling "Repeat chorus"); a repeat
    /// with no chorus to write out holds one "Repeat chorus" comment. `id` is the shown
    /// pass's index (unique even when a part plays twice).
    public var section: RenderSection
    /// The part: index into the song's `RenderModel.sections`.
    public var source: Int
    /// Never `.skip`.
    public var mode: PassMode
    /// The first shown pass of this part (cues show here only).
    public var isFirstShown: Bool
    /// Index into `SlotArrangement.passes`; nil for the full song.
    public var position: Int?
}

public enum ArrangedSections {
    /// The shown passes in played order (Skip passes, if any, are left out).
    public static func build(
        _ sections: [RenderSection],
        order: [PlayedPass],
    ) -> [ArrangedSection] {
        var result: [ArrangedSection] = []
        var shown = Set<Int>()
        for pass in order where sections.indices.contains(pass.index) && pass.mode != .skip {
            var section = sections[pass.index]
            if section.isRepeat {
                if let target = SongSections.repeatTarget(of: pass.index, in: sections) {
                    section.items = sections[target].items
                } else {
                    section.items = [.comment(
                        text: repeatText(section),
                        style: .plain,
                        path: repeatPath(pass.index, in: sections),
                    )]
                }
                section.isRepeat = false
                section.kind = section.kind ?? .chorus
            }
            section.id = result.count
            result.append(ArrangedSection(
                section: section,
                source: pass.index,
                mode: pass.mode,
                isFirstShown: shown.insert(pass.index).inserted,
                position: pass.position,
            ))
        }
        return result
    }

    /// "Repeat chorus", or "Repeat <label>" for a differently named repeat.
    public static func repeatText(_ section: RenderSection) -> String {
        let label = SectionNotes.label(of: section) ?? "Chorus"
        if label.caseInsensitiveCompare("Chorus") == .orderedSame {
            return "Repeat chorus"
        }
        return "Repeat \(label)"
    }

    /// A `{chorus}` section carries no path of its own: its row borrows the closest earlier
    /// section's header (the row's source is informational only).
    private static func repeatPath(_ index: Int, in sections: [RenderSection]) -> BlockPath {
        sections[..<index].reversed().lazy.compactMap(\.path).first ?? BlockPath(block: 0)
    }
}
