// Owner: P9-2 (Singer view). The one chord-free drawing of a song (P9-2 section 5): the
// stage, the library and editor previews and P9-1's printed Lyrics part all call it, so a
// song reads the same everywhere. A view, never an edit: nothing here writes anywhere.

import ChordPro
import Foundation
import MusicTheory

/// Turns render sections into singer sections: every chord, chord row, tab and grid gone,
/// lyric text copied byte for byte (romanized Hindi is never touched), comments and section
/// names kept, a wordless part shown as one "Instrumental" row (P9-2 section 5.2).
public enum SingerView {
    /// The text of an instrumental part's placeholder row.
    public static let instrumentalText = "Instrumental"

    /// Singer sections for a preview or a printed sheet: each section through `section(_:)`,
    /// same ids, paths, kinds, labels and order. An unlabelled loose block with nothing left
    /// to sing or read (no words, no comment) is left out, since it has no name to show,
    /// unless it is the song's only content.
    public static func sections(_ sections: [RenderSection]) -> [RenderSection] {
        var result: [RenderSection] = []
        for original in sections {
            var singer = section(original)
            if original.label == nil, !original.isRepeat, isInstrumental(original) {
                // An unlabelled block keeps its directions without claiming an instrumental.
                if case .comment(instrumentalText, .italic, _) = singer.items.last {
                    singer.items.removeLast()
                }
                if singer.items.isEmpty {
                    continue
                }
            }
            result.append(singer)
        }
        if result.isEmpty, let first = sections.first {
            return [section(first)]
        }
        return result
    }

    /// One section (the stage calls it per pass, after its show mode is mapped): lyric lines
    /// without chords, wordless lines, tab, grids and fill tabs dropped, chord-only comments
    /// dropped, stanza breaks collapsed and trimmed. A part with no lyric words left becomes
    /// its surviving comments and one italic "Instrumental" row. A `{chorus}` repeat stub (no
    /// items of its own) is returned unchanged.
    public static func section(_ section: RenderSection) -> RenderSection {
        guard !(section.isRepeat && section.items.isEmpty) else { return section }
        var items: [RenderItem] = []
        for item in section.items {
            guard let kept = singer(item), !isRedundantBreak(kept, after: items) else { continue }
            items.append(kept)
        }
        while case .stanzaBreak = items.last {
            items.removeLast()
        }
        var result = section
        let hasLyrics = items.contains {
            if case .lyrics = $0 {
                true
            } else {
                false
            }
        }
        if hasLyrics {
            result.items = items
            return result
        }
        let comments = items.filter {
            if case .comment = $0 {
                true
            } else {
                false
            }
        }
        if let path = section.path ?? section.items.lazy.compactMap(path(of:)).first {
            result.items = comments + [.comment(text: instrumentalText, style: .italic, path: path)]
        } else {
            result.items = comments
        }
        return result
    }

    /// A stanza break that would lead the section or follow another (collapsed to one).
    private static func isRedundantBreak(_ item: RenderItem, after items: [RenderItem]) -> Bool {
        guard case .stanzaBreak = item else { return false }
        guard let last = items.last else { return true }
        if case .stanzaBreak = last {
            return true
        }
        return false
    }

    /// One item as singer view keeps it (rules 5.2.1-6); nil when it goes.
    private static func singer(_ item: RenderItem) -> RenderItem? {
        switch item {
        case let .lyrics(line):
            guard hasLyricWords(line.lyrics) else { return nil }
            return .lyrics(RenderLine(
                path: line.path,
                lyrics: trimmingTrailingWhitespace(line.lyrics),
                chords: [],
            ))
        case let .comment(text, _, _):
            return isChordLine(text) ? nil : item
        case .stanzaBreak:
            return item
        case .fillTab, .verbatim:
            return nil
        }
    }

    /// A model for previews and print: sections through `sections(_:)`, no diagrams, no
    /// scale line, the header's capo cleared and its key the sounding (concert) key after the
    /// slot's overrides, never a capo shape key or a Nashville number (P9-2 section 6.8).
    public static func model(_ model: RenderModel) -> RenderModel {
        var singer = model
        singer.sections = sections(model.sections)
        singer.diagrams = []
        singer.header.capo = nil
        singer.header.scale = nil
        singer.header.key = model.transform.concertKey?.name
        return singer
    }

    /// Whether a part has no lyric words (P9-2 section 2): nothing a singer sings. A `{chorus}`
    /// repeat stub is not instrumental (its target is).
    public static func isInstrumental(_ section: RenderSection) -> Bool {
        guard !(section.isRepeat && section.items.isEmpty) else { return false }
        return !section.items.contains { item in
            if case let .lyrics(line) = item {
                return hasLyricWords(line.lyrics)
            }
            return false
        }
    }

    /// Whether `text` holds a letter once a trailing or standalone repeat mark ("x2", "X3",
    /// "(x2)", "×2", any count 2-9) is set aside (P9-2 section 5.2 rule 2), and is not a chord
    /// line typed as text ("| G . . | D . . |": its letters are chord names, not words).
    public static func hasLyricWords(_ text: String) -> Bool {
        var words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mark = words.range(of: repeatMark, options: .regularExpression) {
            words.removeSubrange(mark)
        }
        return words.contains(where: \.isLetter) && !isChordLine(words)
    }

    /// A repeat mark at the end of the text, alone or after a space.
    private static let repeatMark = #"(^|\s)\(?\s*[xX×]\s*[2-9]\s*\)?$"#

    /// Whether a comment is a chord line written as a comment (`{c: G D Em C}`): every
    /// space-separated token is a chord symbol, "N.C." or a bar mark, and at least one is a
    /// chord.
    static func isChordLine(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        var chords = 0
        for token in tokens {
            if !token.contains(where: \.isLetter) {
                continue
            }
            switch ChordToken(parsing: String(token)) {
            case .chord:
                chords += 1
            case .noChord:
                continue
            case .unknown:
                return false
            }
        }
        return chords > 0
    }

    /// `text` without the whitespace a chord-only run left at its end; leading and inner
    /// whitespace stays exactly as written.
    static func trimmingTrailingWhitespace(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let before = text.index(before: end)
            guard text[before].isWhitespace else { break }
            end = before
        }
        return String(text[..<end])
    }

    private static func path(of item: RenderItem) -> BlockPath? {
        switch item {
        case let .lyrics(line): line.path
        case let .comment(_, _, path), let .stanzaBreak(path), let .verbatim(_, path): path
        case .fillTab: nil
        }
    }
}
