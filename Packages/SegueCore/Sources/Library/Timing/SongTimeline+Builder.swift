// P8-7a (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 5.4, P8-6 section
// 7.1). The layers, chord by chord: the user's correction, else the chart's marks or grid,
// else the song's rule; a chordless lyric line extends the chord before it. Pure.

import ChordPro
import Editing
import Foundation
import MusicTheory

extension SongTimeline {
    struct Builder {
        let sections: [RenderSection]
        let directives: PositionalDirectives
        let rule: TimingRule
        let applied: [ChordPosition: ChordBeatsOverride]
        let unmatched: [ChordBeatsOverride]
        /// Each `{chorus}` stub's own source line, by render section index.
        let stubPaths: [Int: BlockPath]
        var entries: [Entry] = []
        var passes: [TimedPass] = []
        /// Plays so far, by content section.
        private var plays: [Int: Int] = [:]

        init(
            document: SongDocument,
            sections: [RenderSection],
            units: [SongSectionUnit],
            timing: ChordTiming,
        ) {
            self.sections = sections
            directives = PositionalDirectives(document: document)
            rule = timing.rule ?? .each(.bar)
            let resolved = timing.chords.isEmpty
                ? (applied: [:], unmatched: [])
                : ChordAnchors.resolve(timing.chords, units: units, sections: sections)
            applied = resolved.applied
            unmatched = resolved.unmatched
            stubPaths = Self.stubPaths(document, sections: sections)
            entries.reserveCapacity(64)
        }

        /// The k-th `{chorus}` in source order is the k-th repeat render section.
        static func stubPaths(
            _ document: SongDocument,
            sections: [RenderSection],
        ) -> [Int: BlockPath] {
            var refs: [BlockPath] = []
            for (index, block) in document.blocks.enumerated() {
                switch block {
                case .chorusRef:
                    refs.append(BlockPath(block: index))
                case let .section(section):
                    for (item, inner) in section.items.enumerated() {
                        if case .chorusRef = inner {
                            refs.append(BlockPath(block: index, item: item))
                        }
                    }
                case .blank, .commentDirective, .directive, .fileComment, .line:
                    break
                }
            }
            let repeats = sections.indices.filter { sections[$0].isRepeat }
            return Dictionary(uniqueKeysWithValues: zip(repeats, refs).map { ($0, $1) })
        }

        // MARK: Passes

        mutating func play(_ play: PlayedPass) {
            let section = sections[play.index]
            let isStub = section.isRepeat && section.items.isEmpty
            let content = isStub ? SongSections.repeatTarget(of: play.index, in: sections)
                : play.index
            let stubPath = isStub ? stubPaths[play.index] : nil
            var occurrence = 1
            if let content {
                occurrence = plays[content, default: 0] + 1
                plays[content] = occurrence
            }
            let start = stubPath ?? section.path ?? Self.firstPath(of: section)
            let pass = passes.count
            passes.append(TimedPass(
                section: play.index,
                content: content ?? play.index,
                occurrence: occurrence,
                mode: play.mode,
                position: play.position,
                start: 0,
                end: 0,
                meter: start.map(directives.meter(at:)) ?? directives.meter,
                tempo: start.map(directives.tempo(at:)) ?? directives.tempo,
                key: start.map(directives.key(at:)) ?? directives.keys.song.writtenKey,
            ))
            guard let content else { return }
            let first = entries.count
            let context = Context(
                pass: pass,
                content: content,
                occurrence: occurrence,
                at: stubPath,
            )
            if GridParser.isGrid(sections[content]) {
                grid(sections[content], context: context)
            } else {
                lyrics(sections[content], context: context)
            }
            if first < entries.count {
                let chord = entries[first].chord
                passes[pass].meter = chord.meter
                passes[pass].tempo = chord.tempo
                passes[pass].key = chord.key
            }
        }

        struct Context {
            var pass: Int
            var content: Int
            var occurrence: Int
            /// A stub's own line: what it plays takes the values in effect there.
            var at: BlockPath?
        }

        static func firstPath(of section: RenderSection) -> BlockPath? {
            for item in section.items {
                switch item {
                case let .lyrics(line): return line.path
                case let .comment(_, _, path), let .stanzaBreak(path), let .verbatim(_, path):
                    return path
                case .fillTab:
                    continue
                }
            }
            return nil
        }

        // MARK: Lyric lines

        private mutating func lyrics(_ section: RenderSection, context: Context) {
            var ordinal = 0
            for item in section.items {
                guard case let .lyrics(line) = item else { continue }
                let values = values(at: context.at ?? line.path)
                let timed = line.chords.filter { $0.kind == .chord || $0.kind == .noChord }
                if timed.isEmpty {
                    let unknown = line.chords.contains {
                        $0.kind == .unknown && !ChordBeats.isMark($0.original)
                    }
                    if !unknown, !line.lyrics.trimmingCharacters(in: .whitespaces).isEmpty {
                        extendLast(by: lineExtension(values.meter))
                    }
                    continue
                }
                let estimates = ChordBeats.estimate(
                    line,
                    perBar: values.meter.pulses,
                    hasTime: directives.timeWritten,
                )
                let rules = ruleLengths(count: timed.count, meter: values.meter)
                var estimateIndex = 0
                for (index, chord) in timed.enumerated() {
                    var entry = entry(
                        chord.original,
                        at: ChordPosition(section: context.content, chord: ordinal),
                        line: line.path,
                        context: context,
                        values: values,
                        length: rules[index],
                        silent: chord.kind == .noChord,
                    )
                    if chord.kind == .chord {
                        ordinal += 1
                        let estimate = estimates.indices.contains(estimateIndex)
                            ? estimates[estimateIndex] : nil
                        estimateIndex += 1
                        if !correct(&entry), let beats = estimate?.beats {
                            entry.length = beats * values.meter.ticksPerPulse
                            entry.chord.source = .chart
                        }
                    }
                    entries.append(entry)
                }
            }
        }

        /// What is in effect for a line (or a stub) at `path`.
        struct Values {
            var meter: Meter
            var tempo: Double?
            var key: SongKey?
        }

        private func values(at path: BlockPath) -> Values {
            Values(
                meter: directives.meter(at: path),
                tempo: directives.tempo(at: path),
                key: directives.key(at: path),
            )
        }

        // swiftlint:disable:next function_parameter_count
        private func entry(
            _ token: String,
            at position: ChordPosition,
            line: BlockPath,
            context: Context,
            values: Values,
            length: Int,
            silent: Bool,
        ) -> Entry {
            Entry(
                chord: TimedChord(
                    position: position,
                    pass: context.pass,
                    occurrence: context.occurrence,
                    token: token,
                    line: line,
                    onset: 0,
                    length: 0,
                    push: nil,
                    source: .rule,
                    meter: values.meter,
                    tempo: values.tempo,
                    key: values.key,
                    isSilent: silent,
                ),
                length: length,
                push: nil,
                extendable: true,
            )
        }

        /// Applies the user's correction for the entry's chord, if any.
        private func correct(_ entry: inout Entry) -> Bool {
            guard let override = applied[entry.chord.position] else { return false }
            entry.length = override.ticks ?? override.beats * entry.chord.meter.ticksPerPulse
            entry.chord.source = override.source == .tap ? .tap : .user
            entry.push = override.push
            entry.extendable = false
            return true
        }

        // MARK: Grids

        private mutating func grid(_ section: RenderSection, context: Context) {
            guard let start = context.at ?? Self.firstPath(of: section) else { return }
            let meter = directives.meter(at: start)
            let chart = GridParser.parse(section, header: section.label, meter: meter)
            if chart.leadingTicks > 0 {
                extendLast(by: chart.leadingTicks)
            }
            var next = 0
            for chord in chart.chords {
                var values = values(at: context.at ?? chord.line)
                // One grid counts in one meter, the one in effect where it starts.
                values.meter = meter
                var entry = entry(
                    chord.token,
                    at: ChordPosition(section: context.content, chord: chord.ordinal ?? next),
                    line: chord.line,
                    context: context,
                    values: values,
                    length: chord.length,
                    silent: chord.isSilent,
                )
                entry.chord.source = .grid
                if let ordinal = chord.ordinal {
                    next = ordinal + 1
                    _ = correct(&entry)
                }
                entries.append(entry)
            }
        }

        // MARK: The rule

        /// One length per timed chord on a line, by the song's rule.
        private func ruleLengths(count: Int, meter: Meter) -> [Int] {
            switch rule {
            case let .each(unit):
                let length = switch unit {
                case .halfBar: meter.ticksPerBar / 2
                case .bar: meter.ticksPerBar
                case .twoBars: 2 * meter.ticksPerBar
                }
                return Array(repeating: length, count: count)
            case let .beats(beats):
                return Array(repeating: beats * meter.ticksPerPulse, count: count)
            case let .line(bars):
                // Whole beats shared evenly, the remainder one beat at a time to the first.
                let total = bars * meter.pulses
                let share = total / count
                let remainder = total % count
                return (0 ..< count).map { index in
                    max(1, share + (index < remainder ? 1 : 0)) * meter.ticksPerPulse
                }
            }
        }

        /// What a chordless lyric line adds to the chord before it: one bar, or `n` bars
        /// under "each line lasts n bars".
        private func lineExtension(_ meter: Meter) -> Int {
            if case let .line(bars) = rule {
                return bars * meter.ticksPerBar
            }
            return meter.ticksPerBar
        }

        /// Lengthens the last chord unless the user set its length.
        private mutating func extendLast(by ticks: Int) {
            guard let last = entries.indices.last, entries[last].extendable else { return }
            entries[last].length += ticks
        }
    }
}
