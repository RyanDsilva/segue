import Foundation

/// A junk line the normalizer dropped.
struct RemovedLine: Equatable {
    var text: String
    var rule: String
}

/// Cleans pasted text without touching lyric characters beyond whitespace: line endings,
/// tabs, invisible characters, HTML entities and tag residue, trailing whitespace, and junk
/// lines (ratings, "Tabbed by", navigation, ads, page controls and widgets, comment sections)
/// by `JunkRules`.
/// Smart quotes are straightened only in non-lyric lines, after classification
/// (`straightenQuotes`).
enum Normalizer {
    struct Output: Equatable {
        var lines: [String]
        var removed: [RemovedLine]
    }

    static func normalize(_ text: String) -> Output {
        var body = text
        if body.first == "\u{FEFF}" {
            body.removeFirst()
        }
        body = body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        body = decodeHTML(body)
        let lines = body.components(separatedBy: "\n").map(cleanLine)
        return dropJunk(lines)
    }

    /// Curly quotes to straight ones (only for header, metadata and note lines).
    static func straightenQuotes(_ line: String) -> String {
        var result = line
        for (curly, straight) in [
            ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
        ] {
            result = result.replacingOccurrences(of: curly, with: straight)
        }
        return result
    }

    // MARK: - Characters

    private static func cleanLine(_ line: String) -> String {
        var result = ""
        for character in line {
            switch character {
            case "\u{00A0}", "\u{202F}", "\u{2007}":
                result.append(" ")
            case "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}":
                continue
            default:
                result.append(character)
            }
        }
        if result.contains("\t") {
            result = ChordLines.isTabLine(result) ? result : expandTabs(result)
        }
        while let last = result.last, last.isWhitespace {
            result.removeLast()
        }
        return result
    }

    /// Tabs to spaces with tab stops every 8 columns (so chord columns survive).
    static func expandTabs(_ line: String) -> String {
        var result = ""
        var column = 0
        for character in line {
            if character == "\t" {
                let spaces = 8 - column % 8
                result += String(repeating: " ", count: spaces)
                column += spaces
            } else {
                result.append(character)
                column += 1
            }
        }
        return result
    }

    // MARK: - HTML

    private static func decodeHTML(_ text: String) -> String {
        var result = text.replacing(/(?i)<br\s*\/?>\n?/, with: "\n")
        result = result.replacing(
            /(?i)<\/?(?:b|i|u|em|strong|span|div|p|pre|font|a|code|small|big|su[pb])(?:\s[^<>]*)?>/,
            with: "",
        )
        guard result.contains("&") else { return result }
        return result.replacing(/&(#[0-9]{1,6}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,8});/) { match in
            decodeEntity(String(match.output.1)) ?? String(match.output.0)
        }
    }

    private static func decodeEntity(_ name: String) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            return UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map {
                String(Character($0))
            }
        }
        if name.hasPrefix("#") {
            return UInt32(name.dropFirst()).flatMap { Unicode.Scalar($0) }.map {
                String(Character($0))
            }
        }
        return namedEntities[name.lowercased()]
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "hellip": "\u{2026}", "ndash": "\u{2013}", "mdash": "\u{2014}", "eacute": "\u{E9}",
    ]

    // MARK: - Junk

    /// Drops junk lines that are not lyrics: a line directly under a chord line or with
    /// inline chords is never junk. A comment section ("Comments (12)") is dropped to the end
    /// of its block.
    private static func dropJunk(_ lines: [String]) -> Output {
        var kept: [String] = []
        var removed: [RemovedLine] = []
        var inCommentSection = false
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                inCommentSection = false
                kept.append(line)
                continue
            }
            let underChords = index > 0 && ChordLines.isChordLine(lines[index - 1])
            if inCommentSection {
                // A chord line ends the comment thread (the song goes on).
                guard ChordLines.isChordLine(line) else {
                    removed.append(RemovedLine(text: line, rule: "comment section"))
                    continue
                }
                inCommentSection = false
            }
            guard !underChords, !ChordLines.hasInlineChords(line), !ChordLines.isTabLine(line),
                  !ChordLines.isChordLine(line),
                  let rule = JunkRules.match(line)
            else {
                kept.append(line)
                continue
            }
            removed.append(RemovedLine(text: line, rule: rule.name))
            inCommentSection = rule.startsCommentSection
        }
        return Output(lines: kept, removed: removed)
    }
}
