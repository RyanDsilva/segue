import Foundation

// ChordPro AST, frozen for phase 0 (see docs/phases/0-walking-skeleton.md, "AST").
//
// The shape follows the spec exactly. Implementers of the parser/serializer may add
// non-breaking members (computed properties, convenience initialisers, new `extra` keys);
// changing stored properties or enum cases is an interface change for every consumer and
// must be coordinated.

/// A parsed ChordPro song: header metadata plus the body as an ordered list of blocks.
public struct SongDocument: Sendable, Equatable, Hashable {
    /// Values from metadata directives (`title`, `artist`, `key`, ...).
    public var metadata: Metadata
    /// The song body in source order.
    public var blocks: [Block]

    public init(metadata: Metadata = Metadata(), blocks: [Block] = []) {
        self.metadata = metadata
        self.blocks = blocks
    }
}

/// Song metadata from ChordPro metadata directives.
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
    /// `{duration}` in seconds (source may be `mm:ss` or seconds).
    public var duration: TimeInterval?
    /// Other metadata (`{meta: name value}` and metadata directives without a dedicated
    /// field), keyed by lowercased name, values in source order.
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

/// One top-level element of the song body.
public enum Block: Sendable, Equatable, Hashable {
    /// A `{start_of_x}` ... `{end_of_x}` section.
    case section(Section)
    /// A lyric line outside any section.
    case line(Line)
    /// A comment. Spec ambiguity to settle in the parser session: the grammar has both
    /// `#` file comments ("preserved") and the `{comment}`/`{c}` directive; both currently
    /// map here and the serializer must be able to tell them apart for byte-identical
    /// round trips.
    case comment(String)
    /// An unknown directive, kept and re-serialized verbatim.
    case directive(UnknownDirective)
    /// `{chorus}` (repeat the chorus), with optional label.
    case chorusRef(label: String?)
    /// An empty line.
    case blank
}

/// A directive the parser does not understand, preserved for verbatim re-serialization.
public struct UnknownDirective: Sendable, Equatable, Hashable {
    /// Directive name as written in the source (case preserved).
    public var name: String
    /// Value after `:` or space, if any.
    public var value: String?

    public init(name: String, value: String? = nil) {
        self.name = name
        self.value = value
    }
}

/// A labelled region of the song, e.g. `{start_of_verse: Verse 2}`.
public struct Section: Sendable, Equatable, Hashable {
    public var kind: SectionKind
    /// Optional label from the start directive (`Verse 2`).
    public var label: String?
    /// The section body. A blank line inside a section is a `Line` with no segments.
    /// Note: comments/directives inside a section have no slot in the frozen spec shape;
    /// flag it if the parser needs one.
    public var lines: [Line]

    public init(kind: SectionKind, label: String? = nil, lines: [Line] = []) {
        self.kind = kind
        self.label = label
        self.lines = lines
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

    public init(segments: [Segment] = []) {
        self.segments = segments
    }
}

/// A run of lyric text, optionally with the chord that sits above its start.
public struct Segment: Sendable, Equatable, Hashable {
    /// Chord text kept verbatim in v0 (e.g. "G", "F#m7/E"). A typed Tonic-backed chord is
    /// added in phase 1 alongside this field.
    public var chord: String?
    /// Lyric text following the chord (may be empty, e.g. a trailing chord).
    public var text: String

    public init(chord: String? = nil, text: String) {
        self.chord = chord
        self.text = text
    }
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
