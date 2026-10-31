// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 12.1, R166, R168 Q6,
// Q11). Selecting a run of chords for a bass fill: a plain click on a chord unit anchors the
// span (it still plays the chord), a shift-click extends it silently, in written order and
// either direction (the later chord is the landing). Shared by the preview, the visual
// canvas, the chord-length lane and VoiceOver's "Start fill here" / "End fill here".

import Editing
import Library
import Observation

/// A chord unit of a rendered chart: its line and its lyric offset there.
struct ChordUnitKey: Hashable {
    var line: BlockPath
    var offset: Int
}

@MainActor
@Observable
final class ChordSpanSelection {
    /// The chord a plain click (or play) set, an index into `timeline.chords`; invisible
    /// until a shift-click extends it.
    private(set) var anchor: Int?
    /// The other end, set by a shift-click.
    private(set) var end: Int?
    /// The song in written order (`{chorus}` stubs written out).
    private(set) var timeline: SongTimeline = .empty
    /// The song's saved fills resolved now (an exact span reads "Edit Bass Fill...").
    private(set) var parts: ResolvedParts = .empty
    /// Each chord unit of the rendered chart, to its index in `timeline.chords`.
    private var units: [ChordUnitKey: Int] = [:]
    /// What the chart's chords are, so an edit (not a timing change) clears the span.
    @ObservationIgnored private var shape: [String] = []

    /// The selected chords (start ... landing), once two ends are set.
    var span: ClosedRange<Int>? {
        guard let anchor, let end, anchor != end else { return nil }
        return min(anchor, end) ... max(anchor, end)
    }

    /// Why the span cannot take a fill (section 10), nil when it can.
    var problem: FillSpanProblem? {
        span.flatMap { FillSpan.problem(timeline: timeline, chords: $0) }
    }

    /// The saved fill whose span is exactly this one.
    var existing: AppliedPart? {
        guard let span else { return nil }
        let positions = timeline.chords[span].map(\.position)
        return parts.applied.first { $0.positions == positions }
    }

    /// "Edit Bass Fill..." on an exact saved span, else "Create Bass Fill...".
    var actionTitle: String {
        existing == nil ? "Create Bass Fill\u{2026}" : "Edit Bass Fill\u{2026}"
    }

    // MARK: Song

    /// The chart as rendered now. An edit that changes the chords clears the span; a timing
    /// change keeps it.
    func update(timeline: SongTimeline, sections: [RenderSection], parts: ResolvedParts) {
        let shape = timeline.chords.map { "\($0.pass).\($0.position).\($0.token)" }
        if shape != self.shape {
            if !self.shape.isEmpty {
                clear()
            }
            self.shape = shape
            let units = Self.units(of: sections, timeline: timeline)
            if units != self.units {
                self.units = units
            }
        }
        if timeline != self.timeline {
            self.timeline = timeline
        }
        if parts != self.parts {
            self.parts = parts
        }
        if let anchor, !timeline.chords.indices.contains(anchor) {
            clear()
        }
    }

    /// Each rendered chord unit's timeline index: the n-th `.chord` chord of a line is the
    /// n-th sounding chord written on that line, in its own (not a stub's) pass.
    static func units(of sections: [RenderSection], timeline: SongTimeline) -> [ChordUnitKey: Int] {
        var byLine: [BlockPath: [Int]] = [:]
        for (index, chord) in timeline.chords.enumerated() where !chord.isSilent {
            guard timeline.passes.indices.contains(chord.pass) else { continue }
            let pass = timeline.passes[chord.pass]
            guard pass.section == pass.content, pass.section == chord.position.section else {
                continue
            }
            byLine[chord.line, default: []].append(index)
        }
        var result: [ChordUnitKey: Int] = [:]
        for section in sections {
            for item in section.items {
                guard case let .lyrics(line) = item, let indices = byLine[line.path] else {
                    continue
                }
                let chords = line.chords.filter { $0.kind == .chord }
                for (chord, index) in zip(chords, indices) {
                    result[ChordUnitKey(line: line.path, offset: chord.offset)] = index
                }
            }
        }
        return result
    }

    /// The timeline index of the chord unit at `offset` on `line`.
    func index(line: BlockPath, offset: Int) -> Int? {
        units[ChordUnitKey(line: line, offset: offset)]
    }

    // MARK: Gestures

    /// A plain click or play: the invisible anchor (any span is cleared).
    func setAnchor(_ index: Int) {
        guard timeline.chords.indices.contains(index) else { return }
        anchor = index
        end = nil
    }

    /// A shift-click: the span from the anchor to `index` (again: moves the landing); with
    /// no anchor it anchors.
    func extend(to index: Int) {
        guard timeline.chords.indices.contains(index) else { return }
        guard anchor != nil else {
            setAnchor(index)
            return
        }
        end = index
    }

    /// The span `range` at once (the lane, Song > Create Bass Fill... from a list).
    func select(_ range: ClosedRange<Int>) {
        guard timeline.chords.indices.contains(range.lowerBound),
              timeline.chords.indices.contains(range.upperBound)
        else { return }
        anchor = range.lowerBound
        end = range.upperBound
    }

    /// VoiceOver's "Start fill here": the anchor, keeping a landing already chosen.
    func start(at index: Int) {
        guard timeline.chords.indices.contains(index) else { return }
        anchor = index
    }

    /// VoiceOver's "End fill here".
    func finish(at index: Int) {
        extend(to: index)
    }

    /// Esc, a click on empty space, an edit.
    func clear() {
        if anchor != nil {
            anchor = nil
        }
        if end != nil {
            end = nil
        }
    }

    // MARK: Reading

    /// Where chord `index` sits in the span: (1-based place, count), nil outside it.
    func place(of index: Int) -> (place: Int, count: Int)? {
        guard let span, span.contains(index) else { return nil }
        return (index - span.lowerBound + 1, span.count)
    }

    /// Whether chord `index` is the span's landing.
    func isLanding(_ index: Int) -> Bool {
        span?.upperBound == index
    }

    /// The chord's name as written ("E", "A").
    func name(of index: Int) -> String {
        timeline.chords.indices.contains(index) ? timeline.chords[index].token : ""
    }
}
