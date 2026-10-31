import Foundation
import Library
import Playback

/// The chord-length lane's P8-7b edits (P8-7 section 8): sub-beat lengths (a snapped drag or
/// "2.5" typed), pushes, the edge style per source, the key, time and tempo markers, and a
/// shift-click span. Every write is one correction in the sidecar (one undo step in the
/// editor), recorded as `playAlongTiming` like any other.
extension PlayAlong {
    // MARK: Lengths

    /// The chord's length in ticks on the bar grid: what a correction stores, before a push
    /// moves its onset (a pushed chord sounds longer, and the one before it shorter).
    func gridTicks(of index: Int) -> Int {
        let chords = timeline.timeline.chords
        guard chords.indices.contains(index) else { return 0 }
        var ticks = chords[index].length - (chords[index].push?.ticks ?? 0)
        if chords.indices.contains(index + 1), let push = chords[index + 1].push {
            ticks += push.ticks
        }
        return ticks
    }

    /// Chord `index` lasts `ticks` (a sixteenth ... 32 pulses), keeping any push it had.
    func setLength(_ index: Int, ticks: Int) {
        guard let chord = chord(index) else { return }
        let most = SongTimeline.maximumPulses * chord.meter.ticksPerPulse
        let ticks = min(max(ticks, SongTimeline.minimumLength), most)
        writeCorrection(index, name: "Change Chord Length") { existing, anchor in
            ChordBeatsOverride(
                anchor: anchor,
                ticks: ticks,
                meter: chord.meter,
                push: existing?.push,
            )
        }
    }

    /// The Beats field: "3", "2.5", "2½" or "2 1/2" pulses. False (nothing written) when the
    /// text is not a length.
    @discardableResult
    func setLength(_ index: Int, text: String) -> Bool {
        guard let chord = chord(index),
              let ticks = BeatsText.ticks(text, ticksPerPulse: chord.meter.ticksPerPulse)
        else { return false }
        setLength(index, ticks: ticks)
        return true
    }

    // MARK: Push

    /// The push the chord's correction carries (shown even where the timeline ignores it, on
    /// the range's first chord).
    func push(of index: Int) -> Push? {
        correction(of: index)?.push
    }

    /// `<` and Timing > Push: none, an eighth early, a sixteenth early, none.
    func cyclePush(_ index: Int) {
        let next: Push? = switch push(of: index) {
        case nil: .eighth
        case .eighth: .sixteenth
        case .sixteenth: nil
        }
        setPush(index, next)
    }

    /// Chord `index` starts `push` early (nil: on the beat). A chord without a correction
    /// gets one holding its current length.
    func setPush(_ index: Int, _ push: Push?) {
        guard let chord = chord(index), push != self.push(of: index) else { return }
        let ticks = gridTicks(of: index)
        writeCorrection(
            index,
            name: push == nil ? "Remove Push" : "Push Chord",
        ) { existing, anchor in
            var override = existing
                ?? ChordBeatsOverride(anchor: anchor, ticks: ticks, meter: chord.meter)
            override.push = push
            return override
        }
    }

    /// Replaces chord `index`'s correction (nil without one) with `make(existing, anchor)`.
    /// One write; nothing when it would not change.
    private func writeCorrection(
        _ index: Int,
        name: String,
        _ make: (ChordBeatsOverride?, ChordAnchor) -> ChordBeatsOverride,
    ) {
        guard canEditTiming, let source, let chord = chord(index), !chord.isSilent,
              let anchor = ChordAnchors.anchor(
                  at: chord.position,
                  units: source.units,
                  sections: source.sections,
              )
        else { return }
        let existing = correction(of: index)
        let override = make(existing, anchor)
        guard override != existing else { return }
        save(name) { timing in
            timing.chords.removeAll { $0 == existing }
            timing.chords.append(override)
        }
    }

    // MARK: Span

    /// The chords a shift-click in the lane spans (P8-7 section 8, for the fill editor),
    /// either direction; nil without one.
    var span: ClosedRange<Int>? {
        guard let selected, let spanEnd, spanEnd != selected else { return nil }
        return min(selected, spanEnd) ... max(selected, spanEnd)
    }

    /// A click on a block selects it; shift-click extends the span from the selection.
    func select(_ index: Int, extending: Bool) {
        guard timeline.timeline.chords.indices.contains(index) else { return }
        if extending, selected != nil {
            spanEnd = index
        } else {
            selected = index
            spanEnd = nil
        }
    }

    // MARK: Markers

    /// Where the key, meter or tempo changes inside the range (none at its start).
    var laneMarkers: [LaneMarker] {
        LaneMarker.markers(timeline.timeline, semitones: source?.transform.semitones ?? 0)
    }
}

/// How a dragged right edge snaps: beats, eighths with ⌥, sixteenths with ⌥⇧.
enum LaneSnap: Equatable {
    case beat
    case eighth
    case sixteenth

    init(option: Bool, shift: Bool) {
        self = option ? (shift ? .sixteenth : .eighth) : .beat
    }

    func step(ticksPerPulse: Int) -> Int {
        switch self {
        case .beat: ticksPerPulse
        case .eighth: Ticks.eighth
        case .sixteenth: Ticks.sixteenth
        }
    }

    /// `ticks` rounded to the nearest step, at least one step and at most 32 pulses.
    func snap(_ ticks: Int, ticksPerPulse: Int) -> Int {
        let step = step(ticksPerPulse: ticksPerPulse)
        let steps = (Double(ticks) / Double(step)).rounded()
        let most = SongTimeline.maximumPulses * ticksPerPulse
        return min(max(Int(steps), 1) * step, most)
    }
}

/// The lane's typed lengths: "3", "2.5", "2,5", "2½", "½", "2 1/2" or "3/2" pulses.
enum BeatsText {
    /// The length in ticks for a pulse of `ticksPerPulse`; nil when it is not a length
    /// above zero.
    static func ticks(_ text: String, ticksPerPulse: Int) -> Int? {
        guard let pulses = pulses(text), pulses > 0 else { return nil }
        let ticks = Int((pulses * Double(ticksPerPulse)).rounded())
        return ticks > 0 ? ticks : nil
    }

    static func pulses(_ text: String) -> Double? {
        let fractions: [Character: Double] = [
            "½": 0.5,
            "¼": 0.25,
            "¾": 0.75,
            "⅓": 1 / 3,
            "⅔": 2 / 3,
        ]
        var text = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(
            of: ",",
            with: ".",
        )
        var extra = 0.0
        if let last = text.last, let value = fractions[last] {
            extra = value
            text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                return extra
            }
        }
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count == 2, extra == 0, let whole = Double(parts[0]),
           let part = fraction(parts[1])
        {
            return whole + part
        }
        guard parts.count == 1 else { return nil }
        if extra == 0, let value = fraction(parts[0]) {
            return value
        }
        guard let value = Double(parts[0]), value.isFinite else { return nil }
        return value + extra
    }

    /// "3", "2½", "¼", "1¾", else "2.33".
    static func format(_ pulses: Double) -> String {
        let whole = pulses.rounded(.down)
        let part = pulses - whole
        let glyphs: [(Double, String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾")]
        if abs(part) < 0.001 {
            return "\(Int(whole))"
        }
        if let glyph = glyphs.first(where: { abs($0.0 - part) < 0.001 })?.1 {
            return whole == 0 ? glyph : "\(Int(whole))\(glyph)"
        }
        return String(format: "%.2f", pulses)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    /// "an eighth" / "a sixteenth".
    static func spoken(_ push: Push) -> String {
        switch push {
        case .eighth: "an eighth"
        case .sixteenth: "a sixteenth"
        }
    }

    /// "1/8" / "1/16".
    static func short(_ push: Push) -> String {
        switch push {
        case .eighth: "1/8"
        case .sixteenth: "1/16"
        }
    }

    /// "1/2" as 0.5.
    private static func fraction(_ text: Substring) -> Double? {
        let sides = text.split(separator: "/")
        guard sides.count == 2, let top = Double(sides[0]), let bottom = Double(sides[1]),
              bottom > 0
        else { return nil }
        return top / bottom
    }
}

/// A block's edge, by where its length came from (P8-7 section 8).
enum LaneEdge: Equatable {
    /// Solid: the chart's marks or a grid.
    case chart
    /// Dashed: the song's rule (estimated).
    case estimated
    /// Solid with a dot: your correction.
    case corrected
    /// Solid with a dot and a tick: tapped.
    case tapped

    init(_ source: TimingSource) {
        self = switch source {
        case .chart, .grid: .chart
        case .rule: .estimated
        case .user: .corrected
        case .tap: .tapped
        }
    }
}

/// "Key: A", "3/4" or "♩ 120" above the block where the key, meter or tempo changes.
struct LaneMarker: Hashable {
    /// The chord (an index into the range's chords).
    var index: Int
    var text: String
    var spoken: String

    /// Every change after the range's first chord; keys as the chart shows them
    /// (`semitones` from written).
    static func markers(_ timeline: SongTimeline, semitones: Int) -> [Self] {
        var result: [Self] = []
        let chords = timeline.chords
        for index in chords.indices.dropFirst() {
            let chord = chords[index]
            let before = chords[index - 1]
            var parts: [(text: String, spoken: String)] = []
            if chord.key != before.key, let key = chord.key?.transposed(by: semitones) {
                parts.append(("Key: \(key.name)", "key change to \(key.name)"))
            }
            if chord.meter != before.meter {
                parts.append(("\(chord.meter)", "time change to \(chord.meter)"))
            }
            if chord.tempo != before.tempo, let tempo = chord.tempo {
                let bpm = tempo.rounded() == tempo ? "\(Int(tempo))" : String(format: "%.1f", tempo)
                parts.append(("\u{2669} \(bpm)", "tempo change to \(bpm)"))
            }
            guard !parts.isEmpty else { continue }
            result.append(Self(
                index: index,
                text: parts.map(\.text).joined(separator: "  "),
                spoken: parts.map(\.spoken).joined(separator: ", "),
            ))
        }
        return result
    }
}
