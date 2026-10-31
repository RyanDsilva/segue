// P8-7a core (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 6.2, R167 Q3).
// "Looks like a key change to A": a section whose chords fit another key clearly better than
// the key in effect. Deterministic; never applied without a click (the chip is P8-7b's UI).

import Editing
import MusicTheory

/// A section whose chords look like they are in another key.
public struct KeyChangeSuggestion: Sendable, Hashable {
    /// The written render section.
    public var section: Int
    /// The written key the chords fit (the shape key under a capo, as `{key}` is).
    public var key: SongKey
    /// The key in effect there now.
    public var from: SongKey
    /// What "x" saves (`ChordTiming.dismissedKeys`).
    public var dismissal: KeyChangeDismissal
    /// Where "Insert {key: A}" writes its line: the section's header, else its first line.
    public var insertBefore: BlockPath?
}

public enum KeyChangeDetector {
    /// The suggested key must score this much higher than the key in effect (25%).
    public static let margin = 0.25
    /// Sections with fewer chord occurrences are not judged.
    public static let minimumChords = 4

    /// Suggestions over a song's written-order `timeline` (`order: nil`), its render
    /// `sections` and `units`, without the `dismissed` ones. A section is suggested key K'
    /// when it has at least four chords, K' is neither the key in effect nor its relative,
    /// the detection is clear and scores K' at least `margin` above the key in effect, the
    /// section before it is not already in K', no `{key}` is written at the section, and no
    /// dismissal matches.
    public static func suggestions(
        timeline: SongTimeline,
        sections: [RenderSection],
        units: [SongSectionUnit],
        dismissed: [KeyChangeDismissal],
    ) -> [KeyChangeSuggestion] {
        let written = writtenChords(timeline)
        let changed = Set(timeline.keys.changes.map(\.from.section))
        var result: [KeyChangeSuggestion] = []
        // The chords of the last section that had any.
        var previous: [ChartChord]?
        for index in sections.indices {
            guard let entry = written[index], !entry.chords.isEmpty else { continue }
            defer { previous = entry.chords }
            guard entry.chords.count >= minimumChords, let current = entry.key,
                  !changed.contains(index),
                  let detection = KeyDetector.detect(entry.chords), !detection.isAmbiguous
            else { continue }
            let suggested = detection.key
            guard !same(suggested, current), !same(suggested, current.relative),
                  let top = score(suggested, in: detection),
                  let now = score(current, in: detection),
                  top >= (1 + margin) * now
            else { continue }
            if let previous, let before = KeyDetector.detect(previous),
               same(before.key, suggested)
            {
                continue
            }
            guard let unit = units.first(where: { $0.index == index }) else { continue }
            let dismissal = KeyChangeDismissal(
                section: unit.anchor,
                fingerprint: unit.fingerprint,
                key: suggested,
            )
            guard !dismissed.contains(where: { matches($0, dismissal) }) else { continue }
            result.append(KeyChangeSuggestion(
                section: index,
                key: suggested,
                from: current,
                dismissal: dismissal,
                insertBefore: sections[index].path ?? SongTimeline.Builder.firstPath(
                    of: sections[index],
                ),
            ))
        }
        return result
    }

    /// Each written section's chords (its first play, `{chorus}` stubs left out) and the key in
    /// effect at its first chord.
    private static func writtenChords(_ timeline: SongTimeline)
        -> [Int: (chords: [ChartChord], key: SongKey?)]
    {
        var result: [Int: (chords: [ChartChord], key: SongKey?)] = [:]
        for chord in timeline.chords where !chord.isSilent {
            let pass = timeline.passes[chord.pass]
            guard pass.section == pass.content, pass.occurrence == 1,
                  case let .chord(chart) = ChordToken(parsing: chord.token)
            else { continue }
            result[pass.section, default: ([], chord.key)].chords.append(chart)
        }
        return result
    }

    private static func score(_ key: SongKey, in detection: KeyDetection) -> Double? {
        detection.ranking.first { same($0.key, key) }?.score
    }

    /// The same key by tonic pitch and mode (Ab and G# agree).
    private static func same(_ lhs: SongKey, _ rhs: SongKey) -> Bool {
        lhs.mode == rhs.mode && lhs.tonic.pitchClass == rhs.tonic.pitchClass
    }

    private static func matches(_ lhs: KeyChangeDismissal, _ rhs: KeyChangeDismissal) -> Bool {
        lhs.section.matches(rhs.section) && lhs.fingerprint == rhs.fingerprint
            && same(lhs.key, rhs.key)
    }
}
