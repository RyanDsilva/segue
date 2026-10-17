import Foundation

// ChordPro AST for phase 0 (docs/phases/0-walking-skeleton.md "AST", amended by
// docs/decisions.md "Phase 0 build rulings").
//
// Round-trip model: the block list is the single source of truth. Every node keeps its
// original source spelling in a `Trivia` value, so an unchanged node re-serializes
// byte-for-byte; a node built in code (or whose meaning was edited) serializes canonically,
// re-spelling only what changed. Trivia never takes part in equality or hashing: two nodes
// are equal when they mean the same thing, however they were written.
//
// Stable read-only helpers for consumers: `SongDocument.metadata`,
// `SongDocument.plainLyrics`, `SongDocument.displaySections`.

/// A parsed ChordPro song: the body as an ordered list of blocks, plus metadata derived
/// from its metadata directives.
public struct SongDocument: Sendable, Equatable, Hashable {
    /// The song body in source order. Metadata directives live here too (as `.directive`),
    /// so their position and spelling survive a round trip.
    public var blocks: [Block] {
        didSet { metadata = Metadata(blocks: blocks) }
    }

    /// Values of the metadata directives in `blocks` (`title`, `artist`, `key`, ...).
    /// Read-only: it is derived from `blocks` and refreshed whenever they change.
    public private(set) var metadata: Metadata

    public init(blocks: [Block] = []) {
        self.blocks = blocks
        metadata = Metadata(blocks: blocks)
    }
}

/// Song metadata from ChordPro metadata directives. The first occurrence wins for single
/// valued fields; values that do not parse (e.g. `{capo: two}`) are `nil` and produce a
/// parser diagnostic.
public struct Metadata: Sendable, Equatable, Hashable {
    /// `{title}` / `{t}`.
    public var title: String?
    /// `{subtitle}` / `{st}`.
    public var subtitle: String?
    /// `{artist}`; repeatable, in source order.
    public var artists: [String]
    /// `{key}`, verbatim (e.g. "G", "F#m"). Parsed into a Tonic key in phase 1.
    public var key: String?
    /// `{capo}`.
    public var capo: Int?
    /// `{tempo}` in BPM.
    public var tempo: Double?
    /// `{time}`, verbatim (e.g. "4/4").
    public var time: String?
    /// `{duration}` in seconds (source may be `mm:ss`, `h:mm:ss` or seconds).
    public var duration: TimeInterval?
    /// Other metadata: `{meta: name value}` plus the standard metadata directives without a
    /// dedicated field (`sorttitle`, `composer`, `lyricist`, `arranger`, `copyright`,
    /// `album`, `year`), keyed by lowercased name, values in source order.
    public var extra: [String: [String]]

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        artists: [String] = [],
        key: String? = nil,
        capo: Int? = nil,
        tempo: Double? = nil,
        time: String? = nil,
        duration: TimeInterval? = nil,
        extra: [String: [String]] = [:],
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artists = artists
        self.key = key
        self.capo = capo
        self.tempo = tempo
        self.time = time
        self.duration = duration
        self.extra = extra
    }
}

/// One element of the song body. Every case except `.section` is exactly one source line.
public enum Block: Sendable, Equatable, Hashable {
    /// A `{start_of_x}` ... `{end_of_x}` section.
    case section(Section)
    /// A lyric line.
    case line(Line)
    /// A `#` file comment (not shown to the performer).
    case fileComment(FileComment)
    /// A `{comment}` / `{c}` / `{ci}` / `{cb}` / `{highlight}` directive (shown).
    case commentDirective(CommentDirective)
    /// Any other directive: metadata (`{title}`, `{key}`, `{meta}`, ...) or unknown,
    /// kept and re-serialized verbatim.
    case directive(Directive)
    /// `{chorus}` (repeat the chorus), with optional label.
    case chorusRef(ChorusRef)
    /// An empty or whitespace-only line.
    case blank(BlankLine)
}

/// A labelled region of the song, e.g. `{start_of_verse: Verse 2}` ... `{end_of_verse}`.
public struct Section: Sendable, Equatable, Hashable {
    public var kind: SectionKind
    /// Optional label from the start directive's value (`Verse 2`).
    public var label: String?
    /// The section body: lines, comments, directives, chorus refs and blanks. Sections do
    /// not nest; the parser never puts a `.section` here.
    public var items: [Block]
    /// Spelling of the start directive line.
    public var startTrivia: Trivia
    /// Spelling of the end directive line (empty when the source never closed the section;
    /// the serializer then writes a canonical end directive).
    public var endTrivia: Trivia

    public init(kind: SectionKind, label: String? = nil, items: [Block] = []) {
        self.kind = kind
        self.label = label
        self.items = items
        startTrivia = Trivia()
        endTrivia = Trivia()
    }
}

/// The type of a section.
public enum SectionKind: Sendable, Equatable, Hashable {
    case verse
    case chorus
    case bridge
    case tab
    /// Generic `start_of_<name>` section; payload is `<name>` as written.
    case custom(String)
}

/// A lyric line: chords interleaved with lyric text.
public struct Line: Sendable, Equatable, Hashable {
    public var segments: [Segment]
    /// Source spelling (line ending).
    public var trivia: Trivia

    public init(segments: [Segment] = []) {
        self.segments = segments
        trivia = Trivia()
    }
}

/// A run of lyric text, optionally with the chord that sits above its start.
public struct Segment: Sendable, Equatable, Hashable {
    /// Chord text kept verbatim in v0 (e.g. "G", "F#m7/E"). A typed Tonic-backed chord is
    /// added in phase 1 alongside this field.
    public var chord: String?
    /// Lyric text following the chord (may be empty, e.g. a trailing chord). Leading and
    /// trailing whitespace is kept as written.
    public var text: String

    public init(chord: String? = nil, text: String) {
        self.chord = chord
        self.text = text
    }
}

/// A `#` comment line. `text` is everything after the `#`, verbatim.
public struct FileComment: Sendable, Equatable, Hashable {
    public var text: String
    public var trivia: Trivia

    public init(text: String) {
        self.text = text
        trivia = Trivia()
    }
}

/// How a comment directive asks to be displayed.
public enum CommentStyle: Sendable, Equatable, Hashable {
    /// `{comment}` / `{c}`.
    case plain
    /// `{comment_italic}` / `{ci}`.
    case italic
    /// `{comment_box}` / `{cb}`.
    case box
    /// `{highlight}`.
    case highlight
}

/// A performer-visible comment directive, e.g. `{c: Repeat x2}`.
public struct CommentDirective: Sendable, Equatable, Hashable {
    public var style: CommentStyle
    /// The comment text (empty for a bare `{c}`).
    public var text: String
    public var trivia: Trivia

    public init(style: CommentStyle = .plain, text: String) {
        self.style = style
        self.text = text
        trivia = Trivia()
    }
}

/// A metadata or unknown directive, preserved for verbatim re-serialization.
public struct Directive: Sendable, Equatable, Hashable {
    /// Canonical name: lowercased, short forms expanded (`t` -> `title`). The spelling as
    /// written is kept in `trivia`.
    public var name: String
    /// Value after `:` or space, if any (`{x:}` has value `""`, `{x}` has `nil`).
    public var value: String?
    public var trivia: Trivia

    public init(name: String, value: String? = nil) {
        self.name = name
        self.value = value
        trivia = Trivia()
    }
}

/// `{chorus}`: repeat the chorus here.
public struct ChorusRef: Sendable, Equatable, Hashable {
    /// Optional label from `{chorus: Label}`.
    public var label: String?
    public var trivia: Trivia

    public init(label: String? = nil) {
        self.label = label
        trivia = Trivia()
    }
}

/// An empty or whitespace-only line (the whitespace is trivia).
public struct BlankLine: Sendable, Equatable, Hashable {
    public var trivia: Trivia

    public init() {
        trivia = Trivia()
    }
}

/// How a source line ended.
public enum LineEnding: String, Sendable, Equatable, Hashable {
    case lf = "\n"
    case crlf = "\r\n"
    /// Last line of a file without a trailing newline.
    case endOfFile = ""
}

/// The original source spelling of one line: its exact text (directive alias, separator,
/// whitespace) and line ending. Filled in by the parser; empty for nodes built in code.
///
/// Trivia never affects equality or hashing (every `Trivia` equals every other), so
/// documents compare by meaning. It is opaque on purpose: consumers read the AST, the
/// serializer reads the trivia.
public struct Trivia: Sendable, Hashable {
    /// Exact source text of the line, without its line ending.
    public let source: String?
    /// The line's ending as written.
    public let lineEnding: LineEnding?

    init(source: String? = nil, lineEnding: LineEnding? = nil) {
        self.source = source
        self.lineEnding = lineEnding
    }

    public static func == (_: Self, _: Self) -> Bool {
        true
    }

    public func hash(into _: inout Hasher) {}
}

/// A non-fatal problem found while parsing (the parser never throws).
public struct Diagnostic: Sendable, Equatable, Hashable {
    /// 1-based source line.
    public var line: Int
    /// 1-based column (in `Character`s) where the problem starts.
    public var column: Int
    /// Human-readable description.
    public var message: String

    public init(line: Int, column: Int, message: String) {
        self.line = line
        self.column = column
        self.message = message
    }
}

/// A section as the performer sees it, produced by `SongDocument.displaySections`.
public struct DisplaySection: Sendable, Equatable, Hashable {
    /// Section kind; `nil` for lyric lines outside any section.
    public var kind: SectionKind?
    /// Label to show (the section's label, or "Chorus" for an unlabelled chorus repeat);
    /// `nil` when there is none.
    public var label: String?
    /// The lyric lines, in order. A blank line inside a section is a `Line` with no
    /// segments (stanza break); leading and trailing blanks are dropped. Empty for a repeat.
    public var lines: [Line]
    /// True for a `{chorus}` repeat reference.
    public var isRepeat: Bool

    public init(kind: SectionKind?, label: String?, lines: [Line], isRepeat: Bool = false) {
        self.kind = kind
        self.label = label
        self.lines = lines
        self.isRepeat = isRepeat
    }
}
