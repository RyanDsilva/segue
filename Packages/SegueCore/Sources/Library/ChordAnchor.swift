// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.11). Resolving a saved chord
// anchor (a walk-up pick, P8-6's timing override) against the song as it is now. Pure.

import Editing
import MusicTheory

/// Saved picks resolved against a song: which apply at which departing chord, and which no
/// longer match (kept in the sidecar, listed in the Walk-ups list, never applied).
public struct ResolvedPicks: Sendable, Hashable {
    /// By departing chord, at most one per target bass.
    public var applied: [ChordPosition: [WalkUpPick]]
    public var unmatched: [WalkUpPick]

    public init(applied: [ChordPosition: [WalkUpPick]] = [:], unmatched: [WalkUpPick] = []) {
        self.applied = applied
        self.unmatched = unmatched
    }

    public static let empty = Self()

    /// The pick for the change from `position` into a chord whose written bass is `toBass`.
    public func pick(from position: ChordPosition, toBass: PitchClass) -> WalkUpPick? {
        applied[position]?.first { $0.to.bassPitch == toBass }
    }
}

public enum ChordAnchors {
    /// Picks resolved against `sections` (a song's render sections in written order) and
    /// its `units` (`SongSections.units(of: document)`, default options).
    public static func resolve(
        _ picks: [WalkUpPick],
        units: [SongSectionUnit],
        sections: [RenderSection],
    ) -> ResolvedPicks {
        let song = WrittenChords(sections)
        var result = ResolvedPicks()
        for pick in picks {
            if let position = song.resolve(pick.anchor, to: pick.to, units: units) {
                result.applied[position, default: []].append(pick)
            } else {
                result.unmatched.append(pick)
            }
        }
        return result
    }

    /// Timing overrides resolved the same way (no target): beats by chord, and the
    /// overrides that no longer match.
    public static func resolve(
        _ overrides: [ChordBeatsOverride],
        units: [SongSectionUnit],
        sections: [RenderSection],
    ) -> (beats: [ChordPosition: Int], unmatched: [ChordBeatsOverride]) {
        let song = WrittenChords(sections)
        var beats: [ChordPosition: Int] = [:]
        var unmatched: [ChordBeatsOverride] = []
        for override in overrides {
            if let position = song.resolve(override.anchor, to: nil, units: units) {
                beats[position] = override.beats
            } else {
                unmatched.append(override)
            }
        }
        return (beats, unmatched)
    }

    /// The anchor that saves the chord at `position`: its section's anchor and fingerprint,
    /// its ordinal and its written bass. nil when there is no such chord.
    public static func anchor(
        at position: ChordPosition,
        units: [SongSectionUnit],
        sections: [RenderSection],
    ) -> ChordAnchor? {
        let song = WrittenChords(sections)
        guard let unit = units.first(where: { $0.index == position.section }),
              let chord = song.chords[position.section]?[safe: position.chord]
        else { return nil }
        return ChordAnchor(
            section: unit.anchor,
            fingerprint: unit.fingerprint,
            chord: position.chord,
            from: chord.text,
        )
    }

    /// The written bass of a chord token ("B" for G/B), nil for `N.C.` and unknown chords.
    public static func writtenBass(_ original: String) -> (text: String, pitch: PitchClass)? {
        guard let symbol = ChordToken(parsing: original).chord?.symbol else { return nil }
        let note = symbol.bass ?? symbol.root
        return (note.chartName, note.pitchClass)
    }
}

/// The `.chord`-kind chords of a song's sections with their written basses.
private struct WrittenChords {
    struct Chord {
        var text: String
        var pitch: PitchClass
    }

    let sections: [RenderSection]
    /// By section index, in order.
    let chords: [Int: [Chord]]

    init(_ sections: [RenderSection]) {
        self.sections = sections
        var chords: [Int: [Chord]] = [:]
        for (index, section) in sections.enumerated() {
            for item in section.items {
                guard case let .lyrics(line) = item else { continue }
                for chord in line.chords where chord.kind == .chord {
                    if let bass = ChordAnchors.writtenBass(chord.original) {
                        chords[index, default: []].append(Chord(text: bass.text, pitch: bass.pitch))
                    }
                }
            }
        }
        self.chords = chords
    }

    func resolve(_ anchor: ChordAnchor, to: String?, units: [SongSectionUnit]) -> ChordPosition? {
        guard let section = section(of: anchor, units: units),
              let from = anchor.from.bassPitch
        else { return nil }
        let list = chords[section] ?? []
        if let chord = list[safe: anchor.chord], chord.pitch == from,
           to.map({ targetMatches(section: section, chord: anchor.chord, to: $0) }) ?? true
        {
            return ChordPosition(section: section, chord: anchor.chord)
        }
        // Re-anchor within the section: exactly one chord with this bass (and this target).
        let matches = list.indices.filter { ordinal in
            list[ordinal].pitch == from
                && (to.map { targetMatches(section: section, chord: ordinal, to: $0) } ?? true)
        }
        guard matches.count == 1 else { return nil }
        return ChordPosition(section: section, chord: matches[0])
    }

    /// The section the anchor names: the unit with its anchor and fingerprint, else the one
    /// unit with the same label (for loose lines, the same `after` label) and fingerprint.
    private func section(of anchor: ChordAnchor, units: [SongSectionUnit]) -> Int? {
        let fingerprint = anchor.fingerprint
        func hasPrint(_ unit: SongSectionUnit) -> Bool {
            unit.fingerprint == fingerprint || unit.legacyFingerprint == fingerprint
        }
        if let unit = units.first(where: { $0.anchor.matches(anchor.section) }), hasPrint(unit) {
            return unit.index
        }
        let label = Self.labelKey(anchor.section)
        let candidates = units.filter { Self.labelKey($0.anchor) == label && hasPrint($0) }
        return candidates.count == 1 ? candidates[0].index : nil
    }

    private static func labelKey(_ anchor: SectionAnchor) -> String? {
        switch anchor {
        case let .section(ref): "s:" + SectionNotes.key(ref.label)
        case let .loose(after, _): "l:" + (after.map { SectionNotes.key($0.label) } ?? "")
        }
    }

    /// Whether the chord after (`section`, `chord`) in written order has the bass `to`.
    private func targetMatches(section: Int, chord: Int, to: String) -> Bool {
        guard let wanted = to.bassPitch else { return false }
        return next(section: section, chord: chord)?.pitch == wanted
    }

    /// The next `.chord` in written order; a `{chorus}` repeat leads to its chorus's first.
    private func next(section: Int, chord: Int) -> Chord? {
        if let following = chords[section]?[safe: chord + 1] {
            return following
        }
        for index in sections.indices where index > section {
            let target = sections[index].isRepeat && sections[index].items.isEmpty
                ? SongSections.repeatTarget(of: index, in: sections) ?? index
                : index
            if let first = chords[target]?.first {
                return first
            }
        }
        return nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
