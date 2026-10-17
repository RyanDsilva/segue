// Owner: unit C (Editing). Frozen interface: docs/phases/1-interfaces.md.

import ChordPro
import Diagrams
import MusicTheory

/// A song ready to draw: header, sections with display chords and source addresses, and the
/// diagram strip. One model feeds the editor preview, the visual editor, the live view and
/// (phase 4) PDF, so they can never disagree about what a chord displays as.
public struct RenderModel: Sendable, Equatable {
    public var header: RenderHeader
    public var sections: [RenderSection]
    /// Unique chords in order of first appearance with resolved diagrams; empty when
    /// `options.showDiagrams` is off. Unknown chords and `N.C.` are excluded.
    public var diagrams: [RenderDiagram]
    public var transform: DisplayTransform
    /// The tuning diagrams use: `{meta: tuning ...}` from the song, else `options.tuning`.
    public var tuning: Tuning

    public init(
        header: RenderHeader,
        sections: [RenderSection],
        diagrams: [RenderDiagram],
        transform: DisplayTransform,
        tuning: Tuning,
    ) {
        self.header = header
        self.sections = sections
        self.diagrams = diagrams
        self.transform = transform
        self.tuning = tuning
    }

    /// Builds the model. Sections follow `SongDocument.displaySections` grouping (loose
    /// lines grouped and split at blank lines, `{chorus}` as a repeat), now with comments,
    /// stanza breaks and tab/grid bodies included.
    /// - Parameter userShapes: the user's shape library (lookup order step 2).
    public init(
        document: SongDocument,
        options: DisplayOptions,
        userShapes: UserShapeLibrary = .empty,
    ) {
        let metadata = document.metadata
        let capo = metadata.capo.flatMap { $0 > 0 ? $0 : nil }
        let transform = DisplayTransform(
            options: options,
            key: KeyContext(document: document),
            capo: capo,
        )
        let tuning = metadata.extra["tuning"]?.first.flatMap(Tuning.init(metaValue:))
            ?? options.tuning
        let headerKey = transform.displayKey.map { key in
            options.nashville ? Nashville.header(for: key) : key.name
        }
        self.init(
            header: RenderHeader(
                title: metadata.title,
                subtitle: metadata.subtitle,
                artists: metadata.artists,
                key: headerKey,
                keyStatus: transform.key.status,
                capo: capo,
                tempo: metadata.tempo,
                time: metadata.time,
            ),
            sections: RenderSectionBuilder(transform: transform).sections(of: document),
            diagrams: options.showDiagrams
                ? Self.diagrams(
                    document: document,
                    transform: transform,
                    tuning: tuning,
                    userShapes: userShapes,
                )
                : [],
            transform: transform,
            tuning: tuning,
        )
    }

    private static func diagrams(
        document: SongDocument,
        transform: DisplayTransform,
        tuning: Tuning,
        userShapes: UserShapeLibrary,
    ) -> [RenderDiagram] {
        var seen = Set<String>()
        var entries: [(displayed: ChartChord, concert: ChartChord)] = []
        for token in document.chordTokens {
            guard let displayed = transform.displayed(token).chord,
                  let concert = transform.concert(token).chord,
                  seen.insert(displayed.original).inserted
            else { continue }
            entries.append((displayed, concert))
        }
        let resolver = ShapeResolver(
            defines: document.defineValues.compactMap(ChordDefinition.init(directiveValue:)),
            userLibrary: userShapes,
            tuning: tuning,
        )
        let options = transform.options
        let piano = options.instrument == .piano
            ? resolver.pianoVoicings(for: entries.map(\.concert))
            : []
        let capoFret = options.capoMode == .shapes ? transform.capo : nil
        return entries.enumerated().map { index, entry in
            RenderDiagram(
                name: entry.displayed.original,
                concertName: entry.concert.original,
                guitar: options.instrument == .guitar
                    ? resolver.guitarShape(for: entry.displayed)
                    : nil,
                piano: piano.indices.contains(index) ? piano[index] : nil,
                capoFret: options.instrument == .guitar ? capoFret : nil,
            )
        }
    }
}

/// Title block content.
public struct RenderHeader: Sendable, Equatable {
    public var title: String?
    public var subtitle: String?
    public var artists: [String]
    /// Displayed key: `displayKey.name`, or `Nashville.header(for:)` in Nashville view
    /// ("Am (rel. C)"); `nil` when unknown.
    public var key: String?
    public var keyStatus: KeyStatus
    /// `{capo}`, nil when absent or 0.
    public var capo: Int?
    public var tempo: Double?
    public var time: String?

    public init(
        title: String?,
        subtitle: String?,
        artists: [String],
        key: String?,
        keyStatus: KeyStatus,
        capo: Int?,
        tempo: Double?,
        time: String?,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artists = artists
        self.key = key
        self.keyStatus = keyStatus
        self.capo = capo
        self.tempo = tempo
        self.time = time
    }
}

/// One displayed section.
public struct RenderSection: Sendable, Equatable, Identifiable {
    /// Position in `RenderModel.sections` (stable while the structure is unchanged, so
    /// SwiftUI re-renders only sections whose content changed).
    public var id: Int
    /// The `.section` block (header line), `nil` for loose lines and `{chorus}` repeats.
    public var path: BlockPath?
    public var kind: SectionKind?
    /// Label to show (as `DisplaySection.label`).
    public var label: String?
    public var isRepeat: Bool
    /// False for tab/grid sections: shown verbatim, "Edit in text mode".
    public var isEditable: Bool
    public var items: [RenderItem]

    public init(
        id: Int,
        path: BlockPath?,
        kind: SectionKind?,
        label: String?,
        isRepeat: Bool,
        isEditable: Bool,
        items: [RenderItem],
    ) {
        self.id = id
        self.path = path
        self.kind = kind
        self.label = label
        self.isRepeat = isRepeat
        self.isEditable = isEditable
        self.items = items
    }
}

/// One row of a section.
public enum RenderItem: Sendable, Equatable {
    case lyrics(RenderLine)
    /// A performer-visible `{comment}` (and its italic/box/highlight variants).
    case comment(text: String, style: CommentStyle, path: BlockPath)
    /// A blank line inside a section.
    case stanzaBreak(path: BlockPath)
    /// A tab/grid body line, verbatim (monospaced, read-only).
    case verbatim(text: String, path: BlockPath)
}

/// A lyric line with its display chords.
public struct RenderLine: Sendable, Equatable {
    /// The `.line` block, for tree operations.
    public var path: BlockPath
    /// The lyric text, chords removed (exactly as written; never altered).
    public private(set) var lyrics: String
    /// Chords in source order; `offset`s are non-decreasing.
    public var chords: [RenderChord]
    /// UTF-16 offset into `lyrics` of each lyric offset `0 ... lyricCount`.
    ///
    /// Lyric offsets count `Character`s per text run between chords (docs/phases/
    /// 1-interfaces.md). Joining the runs can merge characters (a chord between `प` and
    /// `्` in `प[G]्यार`), so the joined string's own `Character`s are not lyric offsets:
    /// every conversion goes through this table, never through `lyrics.count`.
    public private(set) var characterStarts: [Int]

    /// A line whose text is one run (no chord splits a character).
    public init(path: BlockPath, lyrics: String, chords: [RenderChord]) {
        self.init(path: path, runs: [lyrics], chords: chords)
    }

    /// A line from its text runs (the text between chords, in order).
    public init(path: BlockPath, runs: [String], chords: [RenderChord]) {
        self.path = path
        self.chords = chords
        var starts: [Int] = []
        var units = 0
        for run in runs {
            for character in run {
                starts.append(units)
                units += character.utf16.count
            }
        }
        starts.append(units)
        lyrics = runs.joined()
        characterStarts = starts
    }

    /// Number of lyric offsets a chord can sit on, minus one (the end).
    public var lyricCount: Int {
        characterStarts.count - 1
    }

    /// UTF-16 offset into `lyrics` of a lyric offset (clamped to `0 ... lyricCount`).
    public func utf16Offset(ofLyricOffset offset: Int) -> Int {
        characterStarts[min(max(offset, 0), lyricCount)]
    }

    /// The lyric offset at (or just before) a UTF-16 offset into `lyrics`.
    public func lyricOffset(atUTF16 utf16: Int) -> Int {
        var low = 0
        var high = lyricCount
        while low < high {
            let mid = (low + high + 1) / 2
            if characterStarts[mid] <= utf16 {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    /// The text of lyric character `offset` (`0 ..< lyricCount`).
    public func character(at offset: Int) -> Substring {
        let units = lyrics.utf16
        let start = units.index(units.startIndex, offsetBy: characterStarts[offset])
        let end = units.index(units.startIndex, offsetBy: characterStarts[offset + 1])
        return lyrics[start ..< end]
    }
}

/// A chord as displayed above a lyric line.
public struct RenderChord: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case chord
        case noChord
        /// Unparseable: shown verbatim and flagged.
        case unknown
    }

    public var ref: ChordRef
    /// Lyric offset the chord sits above (`0 ... RenderLine.lyricCount`; see
    /// `RenderLine.characterStarts`).
    public var offset: Int
    /// Text to draw (transposed / Nashville).
    public var text: String
    /// Source text between the brackets.
    public var original: String
    public var kind: Kind

    public init(ref: ChordRef, offset: Int, text: String, original: String, kind: Kind) {
        self.ref = ref
        self.offset = offset
        self.text = text
        self.original = original
        self.kind = kind
    }
}

/// One entry of the diagram strip.
public struct RenderDiagram: Sendable, Equatable, Identifiable {
    /// The displayed chord name (unique within the strip).
    public var id: String {
        name
    }

    /// Displayed chord name (letter name in the display key, also in Nashville view).
    public var name: String
    /// Concert-pitch chord name (what the piano diagram shows).
    public var concertName: String
    /// Present when `options.instrument == .guitar`.
    public var guitar: ResolvedGuitarShape?
    /// Present when `options.instrument == .piano` (always concert pitch).
    public var piano: PianoVoicing?
    /// Capo fret to draw on guitar diagrams: the song's capo in `.shapes` mode, else nil.
    public var capoFret: Int?

    public init(
        name: String,
        concertName: String,
        guitar: ResolvedGuitarShape?,
        piano: PianoVoicing?,
        capoFret: Int?,
    ) {
        self.name = name
        self.concertName = concertName
        self.guitar = guitar
        self.piano = piano
        self.capoFret = capoFret
    }
}
