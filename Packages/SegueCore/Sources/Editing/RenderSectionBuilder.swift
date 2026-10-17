// Owner: unit C (Editing). Groups a document into `RenderSection`s.

import ChordPro
import MusicTheory

/// Builds render sections with the same grouping as `SongDocument.displaySections` (loose
/// lines grouped and split at blank lines, `{chorus}` as a repeat that splits a section),
/// plus comments, stanza breaks and verbatim tab/grid bodies.
struct RenderSectionBuilder {
    let transform: DisplayTransform
    private var result: [RenderSection] = []

    init(transform: DisplayTransform) {
        self.transform = transform
    }

    func sections(of document: SongDocument) -> [RenderSection] {
        var builder = self
        builder.build(document)
        return builder.result
    }

    private mutating func build(_ document: SongDocument) {
        var loose: [RenderItem] = []
        func flushLoose() {
            if !loose.isEmpty {
                append(RenderSection(
                    id: 0,
                    path: nil,
                    kind: nil,
                    label: nil,
                    isRepeat: false,
                    isEditable: true,
                    items: loose,
                ))
                loose = []
            }
        }
        for (index, block) in document.blocks.enumerated() {
            let path = BlockPath(block: index)
            switch block {
            case .blank:
                flushLoose()
            case let .chorusRef(ref):
                flushLoose()
                appendRepeat(ref)
            case let .line(line):
                loose.append(.lyrics(renderLine(line, path: path)))
            case let .commentDirective(comment):
                loose.append(.comment(text: comment.text, style: comment.style, path: path))
            case let .section(section):
                flushLoose()
                build(section, at: index)
            case .directive, .fileComment:
                break
            }
        }
        flushLoose()
    }

    private mutating func build(_ section: Section, at block: Int) {
        let verbatim = DirectiveLine.isVerbatimSection(section.kind)
        var items: [RenderItem] = []
        var isFirstPart = true
        func flush() {
            while case .stanzaBreak = items.first {
                items.removeFirst()
            }
            while case .stanzaBreak = items.last {
                items.removeLast()
            }
            if isFirstPart || !items.isEmpty {
                append(RenderSection(
                    id: 0,
                    path: isFirstPart ? BlockPath(block: block) : nil,
                    kind: section.kind,
                    label: isFirstPart ? section.label.flatMap { $0.isEmpty ? nil : $0 } : nil,
                    isRepeat: false,
                    isEditable: !verbatim,
                    items: items,
                ))
            }
            items = []
            isFirstPart = false
        }
        for (index, item) in section.items.enumerated() {
            let path = BlockPath(block: block, item: index)
            switch item {
            case .blank:
                items.append(verbatim ? .verbatim(text: "", path: path) : .stanzaBreak(path: path))
            case let .chorusRef(ref):
                flush()
                appendRepeat(ref)
            case let .line(line):
                items.append(verbatim
                    ? .verbatim(text: line.trivia.source ?? Self.text(of: line), path: path)
                    : .lyrics(renderLine(line, path: path)))
            case let .commentDirective(comment):
                items.append(.comment(text: comment.text, style: comment.style, path: path))
            case .directive, .fileComment, .section:
                break
            }
        }
        flush()
    }

    private mutating func appendRepeat(_ ref: ChorusRef) {
        let label = ref.label.flatMap { $0.isEmpty ? nil : $0 } ?? "Chorus"
        append(RenderSection(
            id: 0,
            path: nil,
            kind: .chorus,
            label: label,
            isRepeat: true,
            isEditable: true,
            items: [],
        ))
    }

    /// Appends `section`, numbering it by position.
    private mutating func append(_ section: RenderSection) {
        var section = section
        section.id = result.count
        result.append(section)
    }

    private func renderLine(_ line: Line, path: BlockPath) -> RenderLine {
        var lyrics = ""
        var offset = 0
        var chords: [RenderChord] = []
        for segment in line.segments {
            if let chord = segment.chord {
                let token = ChordToken(parsing: chord)
                let kind: RenderChord.Kind = switch token {
                case .chord: .chord
                case .noChord: .noChord
                case .unknown: .unknown
                }
                chords.append(RenderChord(
                    ref: ChordRef(line: path, index: chords.count),
                    offset: offset,
                    text: transform.display(token),
                    original: chord,
                    kind: kind,
                ))
            }
            lyrics += segment.text
            offset += segment.text.count
        }
        return RenderLine(path: path, lyrics: lyrics, chords: chords)
    }

    private static func text(of line: Line) -> String {
        line.segments.map { ($0.chord.map { "[\($0)]" } ?? "") + $0.text }.joined()
    }
}
