// Owner: unit C (Editing). Chord walking over a parsed document.

import ChordPro
import MusicTheory

extension SongDocument {
    /// Every chord token in song order, skipping tab/grid bodies (verbatim text).
    var chordTokens: [ChordToken] {
        var result: [ChordToken] = []
        func visit(_ line: Line) {
            for segment in line.segments {
                if let chord = segment.chord {
                    result.append(ChordToken(parsing: chord))
                }
            }
        }
        for block in blocks {
            switch block {
            case let .line(line):
                visit(line)
            case let .section(section) where !DirectiveLine.isVerbatimSection(section.kind):
                for case let .line(line) in section.items {
                    visit(line)
                }
            default:
                break
            }
        }
        return result
    }

    /// The parsed chords (no `N.C.` or unknown tokens), for key detection.
    var chartChords: [ChartChord] {
        chordTokens.compactMap(\.chord)
    }

    /// Values of every `{define}`, in source order (sections included).
    var defineValues: [String] {
        var result: [String] = []
        func visit(_ blocks: [Block]) {
            for block in blocks {
                switch block {
                case let .directive(directive) where directive.name == "define":
                    result.append(directive.value ?? "")
                case let .section(section):
                    visit(section.items)
                default:
                    break
                }
            }
        }
        visit(blocks)
        return result
    }
}
