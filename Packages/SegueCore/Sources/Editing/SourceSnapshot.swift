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

    public init(text: String) {
        self.text = text
        (document, parseDiagnostics) = ChordProParser.parse(text)
    }

    // MARK: - Mapping (unit C)

    /// UTF-16 range of the source line holding `path` (without its line ending). For a
    /// section header path, the `{start_of_...}` line.
    public func sourceRange(of path: BlockPath) -> Range<Int>? {
        fatalError("unimplemented: unit C")
    }

    /// UTF-16 range of a chord token including its brackets (`[G]`).
    public func sourceRange(of chord: ChordRef) -> Range<Int>? {
        fatalError("unimplemented: unit C")
    }

    /// The block whose source line contains `offset` (UTF-16), or `nil` past the end.
    public func path(atSourceOffset offset: Int) -> BlockPath? {
        fatalError("unimplemented: unit C")
    }

    /// Text -> visual cursor mapping: the lyric position at a UTF-16 source offset. Inside a
    /// chord bracket it snaps to that chord's lyric offset; on a non-lyric line it snaps to
    /// the start of the nearest following lyric line (else the preceding one); `nil` when
    /// the song has no lyric lines.
    public func lyricPosition(atSourceOffset offset: Int) -> LyricPosition? {
        fatalError("unimplemented: unit C")
    }

    /// Visual -> text cursor mapping: the UTF-16 source offset of a lyric position (after
    /// any chords that sit at that position).
    public func sourceOffset(of position: LyricPosition) -> Int? {
        fatalError("unimplemented: unit C")
    }

    // MARK: - Derived content (unit C)

    /// Every chord token in source order with its reference (sections included).
    public var chords: [ChordOccurrence] {
        fatalError("unimplemented: unit C")
    }

    /// The song's `{define}`s in source order (malformed ones skipped; they are diagnosed).
    public var chordDefinitions: [ChordDefinition] {
        fatalError("unimplemented: unit C")
    }

    /// Syntax colouring runs intersecting `range` (UTF-16), ascending, non-overlapping.
    public func highlights(in range: Range<Int>) -> [SyntaxHighlight] {
        fatalError("unimplemented: unit C")
    }

    /// Parser diagnostics plus editor checks (unknown chords, malformed `{define}`,
    /// `{define}` for a chord the song never uses), with UTF-16 ranges.
    public var diagnostics: [EditorDiagnostic] {
        fatalError("unimplemented: unit C")
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
