// P8-7a (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 5.3, R167 Q3). Every
// `{time}`, `{tempo}` and `{key}` applies from where it is written. Pure.

import ChordPro
import Editing
import MusicTheory

/// The song's `{time}`, `{tempo}` and `{key}` in source order: the song's own value (what
/// `Metadata` reads; the library, filters and header keep it) until a later directive
/// changes it, from the first line after that directive.
public struct PositionalDirectives: Sendable, Hashable {
    public struct Change<Value: Sendable & Hashable>: Sendable, Hashable {
        public var path: BlockPath
        public var value: Value
    }

    public var keys: KeyTrack
    /// The song's `{time}` (4/4 when absent or unreadable).
    public var meter: Meter
    public var meterChanges: [Change<Meter>]
    /// The song's `{tempo}` (the first readable one).
    public var tempo: Double?
    public var tempoChanges: [Change<Double>]
    /// Whether the song writes a `{time}` at all (the one-chord-line estimate needs one).
    public var timeWritten: Bool

    public init(document: SongDocument) {
        let metadata = document.metadata
        keys = KeyTrack(document: document)
        meter = Meter(time: metadata.time)
        meterChanges = document.positionalChanges(
            named: "time",
            songValue: .firstWritten,
            parse: Meter.init(parsing:),
        ).map { Change(path: $0.path, value: $0.value) }
        tempo = metadata.tempo
        tempoChanges = document.positionalChanges(
            named: "tempo",
            songValue: .firstParsed,
            parse: Metadata.parseTempo,
        ).map { Change(path: $0.path, value: $0.value) }
        timeWritten = metadata.time != nil
    }

    /// The meter in effect for a block at `path`.
    public func meter(at path: BlockPath) -> Meter {
        meterChanges.last { $0.path < path }?.value ?? meter
    }

    public func tempo(at path: BlockPath) -> Double? {
        tempoChanges.last { $0.path < path }?.value ?? tempo
    }

    /// The written key in effect.
    public func key(at path: BlockPath) -> SongKey? {
        keys.key(at: path)
    }

    /// The three maps over the song's written chords (`sections`: its `RenderModel.sections`):
    /// each change applies from the first `.chord` chord (lyric or grid) whose line is after
    /// the directive.
    public static func scan(_ document: SongDocument, sections: [RenderSection]) -> PositionalMaps {
        Self(document: document).maps(sections)
    }

    /// `scan` over directives already read.
    func maps(_ sections: [RenderSection]) -> PositionalMaps {
        let directives = self
        guard !meterChanges.isEmpty || !tempoChanges.isEmpty || !keys.changes.isEmpty else {
            return PositionalMaps(
                meters: MeterMap(initial: meter),
                tempos: TempoMap(initial: tempo),
                keys: KeyMap(initial: keys.song.writtenKey),
            )
        }
        let lines = Self.chordLines(sections)
        func position(after path: BlockPath) -> ChordPosition? {
            lines.first { $0.path > path }?.first
        }
        let meters = MeterMap(
            initial: directives.meter,
            changes: directives.meterChanges.compactMap { change in
                position(after: change.path).map { MeterMap.Change(from: $0, value: change.value) }
            },
        )
        let tempos = TempoMap(
            initial: directives.tempo,
            changes: directives.tempoChanges.compactMap { change in
                position(after: change.path).map { TempoMap.Change(from: $0, value: change.value) }
            },
        )
        let keys = KeyMap(
            initial: directives.keys.song.writtenKey,
            changes: directives.keys.changes.compactMap { change in
                position(after: change.path).map { KeyMap.Change(from: $0, value: change.key) }
            },
        )
        return PositionalMaps(meters: meters, tempos: tempos, keys: keys)
    }

    /// Each line holding a `.chord` chord, in written order, with its first chord's position.
    static func chordLines(_ sections: [RenderSection])
        -> [(path: BlockPath, first: ChordPosition)]
    {
        var result: [(BlockPath, ChordPosition)] = []
        for (index, section) in sections.enumerated() {
            if GridParser.isGrid(section) {
                var ordinal = 0
                var last: BlockPath?
                for chord in GridParser.writtenChords(section) {
                    if chord.line != last {
                        result.append((chord.line, ChordPosition(section: index, chord: ordinal)))
                        last = chord.line
                    }
                    ordinal += 1
                }
                continue
            }
            var ordinal = 0
            for item in section.items {
                guard case let .lyrics(line) = item else { continue }
                let count = line.chords.count { $0.kind == .chord }
                if count > 0 {
                    result.append((line.path, ChordPosition(section: index, chord: ordinal)))
                }
                ordinal += count
            }
        }
        return result
    }
}

/// The meter, tempo and key maps of a song (`PositionalDirectives.scan`).
public struct PositionalMaps: Sendable, Hashable {
    public var meters: MeterMap
    public var tempos: TempoMap
    public var keys: KeyMap

    public init(meters: MeterMap, tempos: TempoMap, keys: KeyMap) {
        self.meters = meters
        self.tempos = tempos
        self.keys = keys
    }
}
