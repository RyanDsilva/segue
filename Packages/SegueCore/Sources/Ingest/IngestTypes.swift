import ChordPro
import MusicTheory

// Phase 3 deterministic paste pipeline (docs/phases/3-workstreams/P3-1-deterministic-pipeline.md).
// Value types shared by the pipeline stages and by P3-2's refinement merge.

/// Where the text came from. `.crd` and `.txt` files take the same path as a paste (R76).
public enum IngestOrigin: Sendable, Equatable, Hashable {
    case paste
    /// A file read by import; `extension` is lowercased, without the dot (`txt`, `crd`).
    case file(extension: String)
}

/// The shape of the whole text.
public enum TextFormat: String, Sendable, Equatable, Hashable {
    /// Directives and/or inline `[chords]` only: already ChordPro (A29: skips review).
    case chordPro
    /// Chord lines above lyric lines.
    case chordsOverLyrics
    /// Lyrics with no chords anywhere.
    case bareLyrics
    /// Chords over lyrics together with inline ChordPro, or ChordPro with plain headers.
    case mixed
    /// Lyrics with inline `[chords]` and no ChordPro directives (chord-site copies): segmented
    /// and labelled like any paste, never passed through as finished ChordPro.
    case inlineChords
}

/// What one normalized line is.
public enum LineClass: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Mostly chord symbols (strict parsing, stop list applied).
    case chordLine
    /// Lyric text, possibly with inline `[chords]`.
    case lyricLine
    /// A section header: `[Verse]`, `Chorus:`, `(Chorus)`, `V1`, `Mukhda:`.
    case headerLine
    /// A ChordPro directive line, or a lone repeat mark such as `(x2)`.
    case directive
    /// Guitar tab notation (`e|--0--`).
    case tab
    case blank
    /// Title/artist/key/capo/tempo and chord-site credit lines.
    case metadata
    /// Text code could not place (notes and credits at the top or bottom of a sheet).
    case unknown
}

/// Section vocabulary shared with the model tasks (spike `Vocab.labels`).
public enum SectionLabel: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case intro
    case verse
    case prechorus
    case chorus
    case bridge
    case instrumental
    case outro
    /// Title, credits, notes: not part of the song body.
    case other

    /// The ChordPro section name (`start_of_<name>`); `nil` for `.other`.
    public var sectionName: String? {
        self == .other ? nil : rawValue
    }
}

/// One normalized source line.
public struct IngestLine: Sendable, Equatable, Hashable {
    /// 0-based index into `IngestResult.lines` (what refinements refer to).
    public var index: Int
    /// The normalized text (whitespace, HTML residue and line endings cleaned; lyric
    /// characters untouched).
    public var text: String
    public var lineClass: LineClass

    public init(index: Int, text: String, lineClass: LineClass) {
        self.index = index
        self.text = text
        self.lineClass = lineClass
    }
}

/// A parsed section header line.
public struct HeaderInfo: Sendable, Equatable, Hashable {
    /// The header as the user wrote it, without brackets, parentheses or the colon
    /// (`[Verse 1]` -> `Verse 1`, `Chorus: (x2)` -> `Chorus (x2)`). Kept as the section label.
    public var text: String
    /// The section kind the header names, if it names a known one (`Mukhda` -> chorus).
    public var label: SectionLabel?
    /// Chords written on the header line itself (`Intro: C G Am F` -> `C G Am F`).
    public var trailingChords: String?

    public init(text: String, label: SectionLabel?, trailingChords: String? = nil) {
        self.text = text
        self.label = label
        self.trailingChords = trailingChords
    }
}

/// Cheap facts about a block, shown to a model next to the block (spike "hints" mode).
public struct BlockHints: Sendable, Equatable, Hashable {
    public var headerLabel: SectionLabel?
    /// Index of the earliest block with (mostly) the same lyrics.
    public var sameLyricsAs: Int?
    public var chordsOnly: Bool
    public var guitarTab: Bool
    /// The block has no chords although the sheet has chords elsewhere.
    public var noChords: Bool

    public init(
        headerLabel: SectionLabel? = nil,
        sameLyricsAs: Int? = nil,
        chordsOnly: Bool = false,
        guitarTab: Bool = false,
        noChords: Bool = false,
    ) {
        self.headerLabel = headerLabel
        self.sameLyricsAs = sameLyricsAs
        self.chordsOnly = chordsOnly
        self.guitarTab = guitarTab
        self.noChords = noChords
    }

    /// The spike's wording ("header says chorus; same lyrics as Block 3"), empty when none.
    public var summary: String {
        var parts: [String] = []
        if let headerLabel {
            parts.append("header says \(headerLabel.rawValue)")
        }
        if guitarTab {
            parts.append("guitar tab, no lyrics")
        } else if chordsOnly {
            parts.append("chords only, no lyrics")
        } else {
            if noChords {
                parts.append("no chords")
            }
            if let sameLyricsAs {
                parts.append("same lyrics as Block \(sameLyricsAs)")
            }
        }
        return parts.joined(separator: "; ")
    }
}

/// What a block becomes in the converted song.
public enum BlockRole: String, Sendable, Equatable, Hashable {
    /// Song body: rendered as a section.
    case content
    /// Title/credit/notes block at the top or bottom of the sheet: its metadata lines become
    /// directives, anything else becomes `{comment}` lines.
    case metadata
    /// Already ChordPro (directives, explicit sections): copied verbatim.
    case passthrough
}

/// Who decided a block's label.
public enum LabelSource: String, Sendable, Equatable, Hashable {
    /// A header in the sheet named it.
    case header
    /// Nothing named it: rendered as an unlabelled `{start_of_verse}` placeholder.
    case placeholder
    /// The block's content named it: a guitar tab staff with no header is instrumental.
    case content
    /// Repetition named it (R101): an unheaded block repeating a named block takes its label;
    /// two unnamed blocks with the same lyrics are choruses.
    case repetition
    /// It continues the named section right before it (a blank line inside a section).
    case continuation
    /// A refinement (model) named it.
    case refined
    /// Not a song section (metadata or passthrough blocks).
    case notSection
}

/// A run of non-blank lines (split on blank lines; a lone header joins the next block).
public struct IngestBlock: Sendable, Equatable, Hashable {
    public var index: Int
    public var lines: [IngestLine]
    public var header: HeaderInfo?
    public var role: BlockRole
    /// The section kind used for rendering; `nil` for metadata/passthrough blocks and
    /// unlabelled placeholders.
    public var label: SectionLabel?
    public var labelSource: LabelSource
    public var hints: BlockHints

    public init(
        index: Int,
        lines: [IngestLine],
        header: HeaderInfo?,
        role: BlockRole,
        label: SectionLabel?,
        labelSource: LabelSource,
        hints: BlockHints,
    ) {
        self.index = index
        self.lines = lines
        self.header = header
        self.role = role
        self.label = label
        self.labelSource = labelSource
        self.hints = hints
    }

    /// True for a song section nothing has named yet.
    public var isUnlabelled: Bool {
        role == .content && labelSource == .placeholder
    }
}

/// Song metadata found by code (or set by a refinement).
public struct IngestMetadata: Sendable, Equatable, Hashable {
    public var title: String?
    public var artists: [String]
    public var composer: String?
    public var lyricist: String?
    public var album: String?
    /// The key as `{key}` will say it: the shapes key when a capo is set (phase 1 ruling).
    public var key: String?
    public var capo: Int?
    public var tempo: Int?

    public init(
        title: String? = nil,
        artists: [String] = [],
        composer: String? = nil,
        lyricist: String? = nil,
        album: String? = nil,
        key: String? = nil,
        capo: Int? = nil,
        tempo: Int? = nil,
    ) {
        self.title = title
        self.artists = artists
        self.composer = composer
        self.lyricist = lyricist
        self.album = album
        self.key = key
        self.capo = capo
        self.tempo = tempo
    }
}

/// What a model may look at to find title/artist/key (spike `metadataPrompt`).
public struct MetadataCandidates: Sendable, Equatable, Hashable {
    /// The first lines of a chord-free block at the top of the sheet (at most 8).
    public var topLines: [String]
    /// The first lines of a chord-free block at the bottom of the sheet (at most 4).
    public var bottomLines: [String]
    /// Every chord in song order (repeats included).
    public var chords: [String]
}

/// The open questions a model may answer. Everything is by index: a model never returns
/// lyric text.
public struct RefinementQuestions: Sendable, Equatable, Hashable {
    /// Content blocks no header named (rendered as `{start_of_verse}` placeholders).
    public var unheadedBlocks: [Int]
    /// `nil` when there is nothing to look at.
    public var metadataCandidates: MetadataCandidates?
    /// Indices of `.unknown` lines.
    public var unknownLines: [Int]

    public var isEmpty: Bool {
        unheadedBlocks.isEmpty && metadataCandidates == nil && unknownLines.isEmpty
    }
}

/// Something the review sheet should show.
public enum IngestDiagnostic: Sendable, Equatable, Hashable {
    /// A junk line (ads, ratings, navigation, "Tabbed by") the normalizer dropped.
    case removedLine(text: String, rule: String)
    /// A line code could not place; rendered as a `{comment}`.
    case unknownLine(index: Int, text: String)
    /// A chord token that does not parse; `line` is the 1-based line in the result text.
    case unparseableChord(token: String, line: Int)
    /// A content block rendered as an unlabelled `{start_of_verse}` placeholder.
    case unlabelledBlock(index: Int)
    /// A problem the ChordPro parser reported on the result text.
    case parser(Diagnostic)
    /// A model's refinement of this block would have changed a lyric word, so it was
    /// rejected and the block keeps its deterministic result (LyricGuard, spec section 3).
    case refinementRejected(block: Int)
}

/// Metadata a model filled in (marked apart from rule-based results in the review sheet).
/// Artists are never one: they come from code only (R174).
public enum RefinedField: String, Sendable, Equatable, Hashable, CaseIterable {
    case title
}

/// Answers from a model, all by index (P3-2 fills it; `IngestResult.reassembled` renders it).
public struct Refinements: Sendable, Equatable, Hashable {
    /// Section labels by block index.
    public var labels: [Int: SectionLabel]
    public var title: String?
    public var key: String?
    /// Line classes by line index (for `.unknown` lines).
    public var lineClasses: [Int: LineClass]

    public init(
        labels: [Int: SectionLabel] = [:],
        title: String? = nil,
        key: String? = nil,
        lineClasses: [Int: LineClass] = [:],
    ) {
        self.labels = labels
        self.title = title
        self.key = key
        self.lineClasses = lineClasses
    }
}
