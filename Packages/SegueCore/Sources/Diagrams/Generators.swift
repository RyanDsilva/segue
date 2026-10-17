// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.
// The curated table lives in CuratedShapes.swift, piano voicing in PianoVoicingGenerator.swift.

import MusicTheory

/// Algorithmic guitar fingerings for any tuning (phase 1 spec, "Tunings and custom shapes").
///
/// For each 4-fret window up the neck, every string may be muted, open (when its open note
/// is a chord tone) or fretted on a chord tone inside the window. A fingering qualifies when
/// its lowest sounding note is `tones.lowest`, it contains every essential pitch class, it
/// sounds at least three strings with at most one muted string between sounding ones, and
/// `GuitarFingering.assign` can finger it (four fingers, barre allowed). Qualifying
/// fingerings are ranked by `PlayabilityScore`.
public enum GuitarShapeGenerator {
    /// Fingers per hand position: frets `start ... start + windowWidth - 1`.
    public static let windowWidth = 4
    /// The highest window start searched (shapes reach fret `maxWindowStart + 3`).
    public static let maxWindowStart = 12

    /// Ranked playable shapes for `tones` in `tuning`, best first, at most `limit`.
    /// Every result has `tones.lowest` as its lowest sounding note and contains every
    /// essential pitch class. Empty only when no fingering exists within a 4-fret span.
    public static func shapes(for tones: ChordTones, tuning: Tuning, limit: Int = 5)
        -> [GuitarShape]
    {
        guard limit > 0 else { return [] }
        return rankedCandidates(for: tones, tuning: tuning)
            .prefix(limit)
            .map { GuitarShape(absoluteFrets: $0.frets, fingers: $0.fingering.fingers) }
    }

    /// Every qualifying fingering with its score, best first (ties broken by frets so the
    /// order is deterministic).
    static func rankedCandidates(for tones: ChordTones, tuning: Tuning) -> [Candidate] {
        guard !tuning.strings.isEmpty else { return [] }
        let search = Search(tones: tones, tuning: tuning)
        var seen = Set<[Int?]>()
        var candidates: [Candidate] = []
        for start in 1 ... maxWindowStart {
            search.enumerate(window: start ..< start + windowWidth) { frets, shape in
                guard seen.insert(frets).inserted,
                      let fingering = GuitarFingering.assign(absoluteFrets: frets)
                else { return }
                let score = PlayabilityScore(
                    frets: frets,
                    fingering: fingering,
                    missingTones: shape.missingTones,
                    trebleMutes: shape.trebleMutes,
                    innerMutes: shape.innerMutes,
                ).value
                candidates.append(Candidate(frets: frets, fingering: fingering, score: score))
            }
        }
        return candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            return lhs.frets.lexicographicallyPrecedes(rhs.frets) { ($0 ?? -1) < ($1 ?? -1) }
        }
    }

    /// One qualifying fingering.
    struct Candidate {
        var frets: [Int?]
        var fingering: GuitarFingering.Assignment
        var score: Double
    }

    /// Facts about a fingering the search already knows when it reports one.
    private struct Facts {
        var missingTones: Int
        var trebleMutes: Int
        var innerMutes: Int
    }

    /// Depth-first search over strings for one chord in one tuning, pruning as soon as a
    /// partial fingering cannot qualify (too many inner mutes, too few strings left for the
    /// missing essential tones).
    private struct Search {
        let tuning: Tuning
        let lowest: PitchClass
        let chordMask: Int
        let essentialMask: Int
        let minimumSounding: Int

        init(tones: ChordTones, tuning: Tuning) {
            self.tuning = tuning
            lowest = tones.lowest
            chordMask = Self.mask(tones.pitchClasses)
            essentialMask = Self.mask(tones.essentialPitchClasses + [tones.lowest])
            minimumSounding = min(3, tuning.strings.count)
        }

        static func mask(_ classes: [PitchClass]) -> Int {
            classes.reduce(0) { $0 | 1 << $1.rawValue }
        }

        func bit(_ midi: Int) -> Int {
            1 << PitchClass(midi: midi).rawValue
        }

        /// Partial-fingering state, lowest string first.
        private struct State {
            var covered = 0
            var lowestPitch = Int.max
            var sounding = 0
            /// Muted strings since the last sounding one (after the first sounding one).
            var pendingMutes = 0
            var innerMutes = 0
        }

        /// Calls `body` with every qualifying (pre-fingering) combination for one window.
        func enumerate(window: Range<Int>, _ body: ([Int?], Facts) -> Void) {
            let options: [[Int?]] = tuning.strings.map { open in
                var choices: [Int?] = [nil]
                if chordMask & bit(open) != 0 {
                    choices.append(0)
                }
                choices += window.filter { chordMask & bit(open + $0) != 0 }.map(\.self)
                return choices
            }
            let count = options.count
            var frets = [Int?](repeating: nil, count: count)
            func visit(_ string: Int, _ state: State) {
                let missing = (essentialMask & ~state.covered).nonzeroBitCount
                guard missing <= count - string else { return }
                if string == count {
                    guard state.sounding >= minimumSounding,
                          PitchClass(midi: state.lowestPitch) == lowest
                    else { return }
                    body(frets, Facts(
                        missingTones: (chordMask & ~state.covered).nonzeroBitCount,
                        trebleMutes: state.pendingMutes,
                        innerMutes: state.innerMutes,
                    ))
                    return
                }
                for choice in options[string] {
                    var next = state
                    if let fret = choice {
                        let pitch = tuning.strings[string] + fret
                        next.covered |= bit(pitch)
                        next.lowestPitch = min(next.lowestPitch, pitch)
                        next.sounding += 1
                        next.innerMutes += next.pendingMutes
                        next.pendingMutes = 0
                        guard next.innerMutes <= 1 else { continue }
                    } else if state.sounding > 0 {
                        next.pendingMutes += 1
                    }
                    frets[string] = choice
                    visit(string + 1, next)
                }
                frets[string] = nil
            }
            visit(0, State())
        }
    }
}

/// How hard a fingering is to play (lower is easier): fingers and barres cost, wide spans
/// and high positions cost, open and sounding strings help, muted strings above or inside
/// the chord and missing optional tones cost.
struct PlayabilityScore {
    let frets: [Int?]
    let fingering: GuitarFingering.Assignment
    /// Non-essential chord tones (typically the 5th) the fingering leaves out.
    let missingTones: Int
    let trebleMutes: Int
    let innerMutes: Int

    var value: Double {
        let fretted = frets.compactMap(\.self).filter { $0 > 0 }
        let span = (fretted.max() ?? 0) - (fretted.min() ?? 0)
        let position = fretted.min() ?? 0
        let open = frets.count { $0 == 0 }
        let sounding = frets.count { $0 != nil }
        var cost = Double(fingering.fingerCount)
        cost += fingering.barre == nil ? 0 : 1
        cost += 0.7 * Double(span)
        cost += 0.4 * Double(position)
        cost -= 0.3 * Double(open)
        cost -= 0.8 * Double(sounding)
        cost += 0.6 * Double(trebleMutes)
        cost += 2.5 * Double(innerMutes)
        cost += 1.0 * Double(missingTones)
        return cost
    }
}

/// Hand-checked open and barre shapes, authored by us (no licence question).
public enum CuratedShapes {
    /// The curated shape for a chord, or `nil`. Only standard tuning has curated shapes.
    /// Chords match by root, lowest note and pitch-class set, so spelling and extension
    /// numbering (`add9` vs `add2`) do not matter.
    public static func shape(for tones: ChordTones, tuning: Tuning) -> GuitarShape? {
        guard tuning.strings == Tuning.standard.strings else { return nil }
        return index[Key(tones)]
    }

    /// A curated chord and its shape.
    public struct Entry: Sendable, Hashable {
        /// Readable name, for tests and diagnostics (`"D/F#"`).
        public var name: String
        public var tones: ChordTones
        public var shape: GuitarShape
    }

    /// Every curated shape, in table order.
    public static let all: [Entry] = CuratedTable.rows.map { row in
        Entry(name: row.name, tones: row.tones, shape: row.shape)
    }

    private struct Key: Hashable {
        let root: PitchClass
        let lowest: PitchClass
        let classes: [PitchClass]

        init(_ tones: ChordTones) {
            root = tones.root
            lowest = tones.lowest
            classes = tones.pitchClasses
        }
    }

    private static let index: [Key: GuitarShape] = Dictionary(
        all.map { (Key($0.tones), $0.shape) },
        uniquingKeysWith: { first, _ in first },
    )
}
