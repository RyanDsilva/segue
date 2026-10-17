// Owner: unit C (Editing). Frozen interface: docs/phases/1-interfaces.md.

import ChordPro
import Diagrams
import MusicTheory

/// One immutable version of the song being edited: the source text (the undo-able source of
/// truth held by the text view), its lossless parse, and the mapping between tree addresses
/// and text offsets.
///
/// The editor builds a new snapshot after every text change (parse is < 5 ms for 300
/// lines); tree operations are planned against a snapshot and come back as `SourceChange`s.
public struct SourceSnapshot: Sendable {
    public let text: String
    public let document: SongDocument
    public let parseDiagnostics: [Diagnostic]

    let map: SourceMap

    public init(text: String) {
        self.text = text
        (document, parseDiagnostics) = ChordProParser.parse(text)
        map = SourceMap(text: text, document: document)
    }

    // MARK: - Mapping (unit C)

    /// UTF-16 range of the source line holding `path` (without its line ending). For a
    /// section header path, the `{start_of_...}` line.
    public func sourceRange(of path: BlockPath) -> Range<Int>? {
        map.lineOfPath[path].map { map.lines[$0].contentRange }
    }

    /// UTF-16 range of a chord token including its brackets (`[G]`).
    public func sourceRange(of chord: ChordRef) -> Range<Int>? {
        guard let layout = layout(of: chord.line), layout.chords.indices.contains(chord.index)
        else { return nil }
        return layout.chords[chord.index].range
    }

    /// The block whose source line contains `offset` (UTF-16), or `nil` past the end.
    public func path(atSourceOffset offset: Int) -> BlockPath? {
        guard let index = map.lineIndex(containing: offset), index < map.roles.count else {
            return nil
        }
        return Self.path(of: map.roles[index])
    }

    /// Text -> visual cursor mapping: the lyric position at a UTF-16 source offset. Inside a
    /// chord bracket it snaps to that chord's lyric offset; on a non-lyric line it snaps to
    /// the start of the nearest following lyric line (else the end of the preceding one);
    /// `nil` when the song has no lyric lines.
    public func lyricPosition(atSourceOffset offset: Int) -> LyricPosition? {
        let clamped = min(max(offset, 0), map.length)
        let lineIndex = map.lineIndex(containing: clamped) ?? map.lines.count
        if lineIndex < map.lines.count, case let .block(path) = map.roles[lineIndex],
           let layout = layout(of: path)
        {
            let inLine = min(clamped, layout.lineRange.upperBound)
            return LyricPosition(line: path, offset: layout.lyricOffset(atSourceOffset: inLine))
        }
        for index in lineIndex ..< map.roles.count {
            if case let .block(path) = map.roles[index], layout(of: path) != nil {
                return LyricPosition(line: path, offset: 0)
            }
        }
        for index in stride(from: min(lineIndex, map.roles.count) - 1, through: 0, by: -1) {
            if case let .block(path) = map.roles[index], let layout = layout(of: path) {
                return LyricPosition(line: path, offset: layout.lyricCount)
            }
        }
        return nil
    }

    /// Visual -> text cursor mapping: the UTF-16 source offset of a lyric position (after
    /// any chords that sit at that position).
    public func sourceOffset(of position: LyricPosition) -> Int? {
        layout(of: position.line)?.sourceOffset(ofLyricOffset: position.offset)
    }

    // MARK: - Derived content (unit C)

    /// Every chord token in source order with its reference (sections included; tab and
    /// grid bodies are verbatim text, not chords, and are skipped).
    public var chords: [ChordOccurrence] {
        var result: [ChordOccurrence] = []
        for role in map.roles {
            guard case let .block(path) = role, let layout = layout(of: path) else { continue }
            for (index, chord) in layout.chords.enumerated() {
                result.append(ChordOccurrence(
                    ref: ChordRef(line: path, index: index),
                    token: ChordToken(parsing: chord.text),
                ))
            }
        }
        return result
    }

    /// The song's `{define}`s in source order (malformed ones skipped; they are diagnosed).
    public var chordDefinitions: [ChordDefinition] {
        defineLines.compactMap(\.definition)
    }

    /// Syntax colouring runs intersecting `range` (UTF-16), ascending, non-overlapping.
    public func highlights(in range: Range<Int>) -> [SyntaxHighlight] {
        var result: [SyntaxHighlight] = []
        var index = map.firstLine(endingAfter: range.lowerBound)
        while index < map.lines.count, index < map.roles.count,
              map.lines[index].start < max(range.upperBound, range.lowerBound + 1)
        {
            result += lineHighlights(index)
            index += 1
        }
        return result.filter {
            $0.range.lowerBound < range.upperBound && $0.range.upperBound > range.lowerBound
        }
    }

    /// Parser diagnostics plus editor checks (unknown chords, malformed `{define}`,
    /// `{define}` for a chord the song never uses), with UTF-16 ranges.
    public var diagnostics: [EditorDiagnostic] {
        var result = parseDiagnostics.compactMap(editorDiagnostic(for:))
        for occurrence in chords {
            guard case let .unknown(unknown) = occurrence.token,
                  let range = sourceRange(of: occurrence.ref),
                  let line = map.lineOfPath[occurrence.ref.line]
            else { continue }
            result.append(EditorDiagnostic(
                range: range,
                severity: .warning,
                kind: .unknownChord,
                message: "Unknown chord '\(unknown.original)'",
                line: line + 1,
            ))
        }
        let used = Set(chords.map(\.token.original))
        for define in defineLines {
            let range = map.lines[define.line].contentRange
            if define.definition == nil {
                result.append(EditorDiagnostic(
                    range: range,
                    severity: .error,
                    kind: .malformedDefine,
                    message: "Malformed {define}: expected a chord name with frets or keys",
                    line: define.line + 1,
                ))
            } else if let name = define.name, !used.contains(name) {
                result.append(EditorDiagnostic(
                    range: range,
                    severity: .warning,
                    kind: .unusedDefine,
                    message: "{define} for '\(name)', which the song never uses",
                    line: define.line + 1,
                ))
            }
        }
        return result.sorted {
            ($0.range.lowerBound, $0.line) < ($1.range.lowerBound, $1.line)
        }
    }
}

/// A chord token and where it is.
public struct ChordOccurrence: Sendable, Hashable {
    public var ref: ChordRef
    public var token: ChordToken

    public init(ref: ChordRef, token: ChordToken) {
        self.ref = ref
        self.token = token
    }
}

/// A coloured run in the text editor.
public struct SyntaxHighlight: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// A parseable chord, brackets included.
        case chord
        /// `[N.C.]`.
        case noChord
        /// A chord token we cannot parse (also gets a diagnostic).
        case unknownChord
        /// A metadata or unknown directive line (`{title: ...}`).
        case directive
        /// `{start_of_...}` / `{end_of_...}` / `{chorus}`.
        case sectionMarker
        /// `{comment}` / `{c}` / `{ci}` / `{cb}` / `{highlight}`.
        case commentDirective
        /// `#` file comment.
        case fileComment
    }

    public var range: Range<Int>
    public var kind: Kind

    public init(range: Range<Int>, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}

/// An inline diagnostic for the text editor (and badges in visual mode).
public struct EditorDiagnostic: Sendable, Hashable {
    public enum Severity: Sendable, Hashable {
        case error
        case warning
    }

    public enum Kind: Sendable, Hashable {
        case unknownChord
        case unclosedSection
        case malformedDirective
        case malformedDefine
        case unusedDefine
        /// Any other parser diagnostic.
        case syntax
    }

    /// UTF-16 range in the snapshot text (empty range = a caret position).
    public var range: Range<Int>
    public var severity: Severity
    public var kind: Kind
    public var message: String
    /// 1-based line, for list display.
    public var line: Int

    public init(range: Range<Int>, severity: Severity, kind: Kind, message: String, line: Int) {
        self.range = range
        self.severity = severity
        self.kind = kind
        self.message = message
        self.line = line
    }
}
