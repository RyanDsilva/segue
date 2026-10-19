import ChordPro
import MusicTheory

/// Checks a converted document: every chord token parses (strict MusicTheory: "Do" is never
/// a chord); collects unparseable tokens and unknown lines for the review sheet.
enum Validator {
    struct Report: Equatable {
        /// Every parsed chord in song order (for key inference).
        var chords: [ChartChord]
        var diagnostics: [IngestDiagnostic]
    }

    static func validate(
        _ document: SongDocument,
        parserDiagnostics: [Diagnostic],
        lines: [IngestLine],
    ) -> Report {
        var report = Report(chords: [], diagnostics: parserDiagnostics.map(IngestDiagnostic.parser))
        var lineNumber = 0
        for block in document.blocks {
            lineNumber += 1
            switch block {
            case let .line(line):
                check(line, lineNumber: lineNumber, into: &report)
            case let .section(section):
                for item in section.items {
                    lineNumber += 1
                    if case let .line(line) = item {
                        check(line, lineNumber: lineNumber, into: &report)
                    }
                }
                lineNumber += 1
            default:
                continue
            }
        }
        for line in lines where line.lineClass == .unknown {
            report.diagnostics.append(.unknownLine(index: line.index, text: line.text))
        }
        return report
    }

    private static func check(_ line: Line, lineNumber: Int, into report: inout Report) {
        for chord in line.segments.compactMap(\.chord) {
            switch ChordToken(parsing: chord) {
            case let .chord(parsed):
                report.chords.append(parsed)
            case .noChord:
                continue
            case let .unknown(unknown):
                report.diagnostics.append(
                    .unparseableChord(token: unknown.original, line: lineNumber),
                )
            }
        }
    }
}
