import Foundation

/// Per-line classes and the whole-text format.
public enum FormatDetector {
    /// The class of each line, in order. Context-free except that a line under a chord line
    /// is always a lyric (or another chord line).
    public static func classify(_ lines: [String]) -> [LineClass] {
        var classes: [LineClass] = []
        for line in lines {
            let underChords = classes.last == .chordLine
            classes.append(classify(line, underChordLine: underChords))
        }
        return classes
    }

    static func classify(_ line: String, underChordLine: Bool) -> LineClass {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .blank
        }
        if isDirective(trimmed) || ChordLines.isRepeatMark(trimmed) {
            return .directive
        }
        if ChordLines.isChordLine(line) {
            return .chordLine
        }
        if ChordLines.isTabLine(line) {
            return .tab
        }
        if ChordLines.isChordLegend(line) {
            return .unknown
        }
        if HeaderParser.parse(line) != nil, !underChordLine || trimmed.hasPrefix("[") {
            return .headerLine
        }
        if underChordLine {
            return .lyricLine
        }
        if MetadataExtractor.keyValueFields(line) != nil {
            return .metadata
        }
        return .lyricLine
    }

    /// The whole-text format from line classes.
    public static func format(lines: [String], classes: [LineClass]) -> TextFormat {
        var chordLines = 0
        var inline = 0
        var directives = 0
        var structural = 0
        for (line, lineClass) in zip(lines, classes) {
            switch lineClass {
            case .chordLine: chordLines += 1
            case .lyricLine where ChordLines.hasInlineChords(line): inline += 1
            case .directive where isDirective(line.trimmingCharacters(in: .whitespaces)):
                directives += 1
            case .headerLine, .metadata, .tab: structural += 1
            default: break
            }
        }
        if chordLines > 0 {
            return inline > 0 || directives > 0 ? .mixed : .chordsOverLyrics
        }
        if directives == 0, inline > 0 {
            return structural > 0 ? .mixed : .inlineChords
        }
        if inline > 0 || directives > 0 {
            return structural > 0 && !hasSectionDirectives(lines) ? .mixed : .chordPro
        }
        return .bareLyrics
    }

    /// `{...}` on its own line.
    static func isDirective(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }

    /// `{start_of_*}`, `{soc}`, `{sov}`, `{sob}`, `{sot}` and their ends.
    static func isSectionDirective(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: /(?i)\{\s*(?:start_of_|end_of_|so[cvbtg]\b|eo[cvbtg]\b).*\}/) != nil
    }

    private static func hasSectionDirectives(_ lines: [String]) -> Bool {
        lines.contains(where: isSectionDirective)
    }
}
