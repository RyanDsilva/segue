import ChordPro
import Editing
import Library
import SwiftUI

/// Sizes for rendering a song body. Colours come from `Theme.color` and resolve per
/// appearance, so the same view draws the light editor preview and the dark stage.
struct SongSheetStyle: Equatable {
    /// Lyric point size; chords are `FontTokens.chordToLyricRatio` of it.
    var lyricSize: CGFloat
    /// Width of the section label column (brand.md section 7: 64).
    var gutterWidth: CGFloat = 64
    /// Vertical space between sections.
    var sectionSpacing: CGFloat

    var chordSize: CGFloat {
        FontTokens.liveChordSize(forLyricSize: lyricSize)
    }

    /// Extra space between wrapped rows (line height 1.25).
    var rowSpacing: CGFloat {
        lyricSize * 0.25
    }

    /// Gap between a chord and the lyric below it.
    var chordGap: CGFloat {
        1
    }

    /// Editor preview and song detail (mockup E2 a: 18pt lyrics, 15pt chords).
    static let preview = Self(lyricSize: 18, gutterWidth: 76, sectionSpacing: 22)
    /// Live view (brand.md section 6: default 24).
    static let stage = Self(lyricSize: 24, sectionSpacing: 32)
}

/// Renders a song body from a `RenderModel`: a section label gutter on the left, lyric
/// lines with each display chord above its character. Used by the editor preview, the song
/// page and the live view, so they always agree on what a chord displays as.
struct SongSheetView: View {
    let sections: [RenderSection]
    let style: SongSheetStyle
    /// The editor's "Looks like a key change" chips, each above its section (P8-7 6.2).
    var keyChanges: [KeyChangeSuggestion] = []
    /// The fill span being selected (P8-7 12.1): its capsule gets a row under the landing.
    @Environment(\.chordSpan) var span

    var body: some View {
        // One lazy row per item: a 200-line song only builds the rows on screen, and typing
        // re-renders only the row whose content changed (rows are Equatable).
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(SheetRow.rows(
                of: sections,
                style: style,
                keyChanges: keyChanges,
                capsuleAfter: capsuleLine,
            )) { row in
                SheetRowView(row: row, style: style).equatable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row of the sheet: a section's label gutter (first row only) and one item.
struct SheetRow: Identifiable, Equatable {
    enum Content: Equatable {
        case item(RenderItem)
        case repeatNote(String)
        /// The key-change chip above a section (the editor's preview only).
        case keyChange(KeyChangeSuggestion)
        /// "Create Bass Fill..." under the line holding a fill span's landing (P8-7 12.1).
        case fillCapsule
    }

    /// Section id and item index: stable while the structure is unchanged.
    let id: String
    let label: String?
    let isChorus: Bool
    let content: Content
    let topSpacing: CGFloat
    /// The section's header, on its first row (where a directive can go before it).
    var sectionPath: BlockPath?

    static func rows(
        of sections: [RenderSection],
        style: SongSheetStyle,
        keyChanges: [KeyChangeSuggestion] = [],
        capsuleAfter: BlockPath? = nil,
    ) -> [Self] {
        var rows: [Self] = []
        for section in sections {
            var sectionSpacing = rows.isEmpty ? 0 : style.sectionSpacing
            let isChorus = section.kind == .chorus
            if let chip = keyChanges.first(where: { $0.section == section.id }) {
                rows.append(Self(
                    id: "\(section.id).chip",
                    label: nil,
                    isChorus: isChorus,
                    content: .keyChange(chip),
                    topSpacing: sectionSpacing,
                ))
                sectionSpacing = 8
            }
            if section.isRepeat {
                rows.append(Self(
                    id: "\(section.id)",
                    label: nil,
                    isChorus: isChorus,
                    content: .repeatNote(repeatText(section)),
                    topSpacing: sectionSpacing,
                ))
                continue
            }
            for (index, item) in section.items.enumerated() {
                rows.append(Self(
                    id: "\(section.id).\(index)",
                    label: index == 0 ? labelText(section) : nil,
                    isChorus: isChorus,
                    content: .item(item),
                    topSpacing: index == 0 ? sectionSpacing : style.rowSpacing,
                    sectionPath: index == 0 ? section.path : nil,
                ))
                if let capsuleAfter, case let .lyrics(line) = item, line.path == capsuleAfter {
                    rows.append(Self(
                        id: "\(section.id).\(index).fill",
                        label: nil,
                        isChorus: isChorus,
                        content: .fillCapsule,
                        topSpacing: 6,
                    ))
                }
            }
        }
        return rows
    }

    private static func labelText(_ section: RenderSection) -> String {
        if let label = section.label, !label.isEmpty {
            return label
        }
        return switch section.kind {
        case .verse: "Verse"
        case .chorus: "Chorus"
        case .bridge: "Bridge"
        case .tab: "Tab"
        case let .custom(name): name.replacingOccurrences(of: "_", with: " ").capitalized
        case nil: ""
        }
    }

    private static func repeatText(_ section: RenderSection) -> String {
        if let label = section.label, label.caseInsensitiveCompare("Chorus") != .orderedSame {
            return "Repeat \(label)"
        }
        return "Repeat chorus"
    }
}

private struct SheetRowView: View, Equatable {
    let row: SheetRow
    let style: SongSheetStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(row.label ?? "")
                .font(Theme.font.label)
                .foregroundStyle(row.isChorus ? Theme.color.ink : Theme.color.muted)
                .lineLimit(2)
                .frame(width: style.gutterWidth - 12, alignment: .leading)
                .padding(.trailing, 12)
                .accessibilityIdentifier(row.label == nil ? "" : AccessibilityID.sheetSectionLabel)
                .accessibilityHidden(row.label == nil)
                .directiveInsertMenu(before: row.sectionPath)
            switch row.content {
            case let .keyChange(suggestion):
                KeyChangeChipRow(suggestion: suggestion)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .fillCapsule:
                FillSpanCapsuleRow()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case let .repeatNote(text):
                Text(text)
                    .font(Theme.font.liveLyric(size: style.lyricSize))
                    .foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case let .item(.lyrics(line)):
                // The flow layout reports its first row's lyric baseline as its first text
                // baseline, so the label sits on the first lyric, not on the chord above it.
                ItemView(item: .lyrics(line), style: style)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .directiveInsertMenu(before: line.path)
            case let .item(item):
                ItemView(item: item, style: style)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, row.topSpacing)
    }
}

private struct ItemView: View {
    let item: RenderItem
    let style: SongSheetStyle

    var body: some View {
        switch item {
        case let .lyrics(line):
            LyricLineView(line: line, style: style)
        case let .comment(text, commentStyle, _):
            Text(text)
                .font(Theme.font.liveLyric(size: style.lyricSize * 0.8))
                .italic(commentStyle == .italic)
                .foregroundStyle(Theme.color.muted)
                .padding(.horizontal, commentStyle == .box || commentStyle == .highlight ? 6 : 0)
                .padding(.vertical, commentStyle == .box || commentStyle == .highlight ? 2 : 0)
                .background {
                    if commentStyle == .highlight {
                        RoundedRectangle(cornerRadius: 4).fill(Theme.color.surfaceAlt)
                    } else if commentStyle == .box {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.color.controlBorder)
                    }
                }
        case .stanzaBreak:
            // A blank line inside a section.
            Color.clear.frame(height: style.lyricSize * 0.6)
        case let .verbatim(text, _):
            Text(text.isEmpty ? " " : text)
                .font(.system(size: style.lyricSize * 0.75, design: .monospaced))
                .foregroundStyle(Theme.color.ink)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// One lyric line. Each chord sits above its character; the line wraps between words
/// when it is wider than the column (`LyricLineLayout`). Only a row that carries chords has
/// a chord band: a wrapped row without chords sits right under the row above, with no empty
/// band between.
struct LyricLineView: View {
    let line: RenderLine
    let style: SongSheetStyle
    /// A walk-up run whose picker VoiceOver asked for through the line's actions (P8-4b).
    @State private var requestedWalkUp: ChangeID?
    /// The chord at the play-along playhead, underlined (P8-6 10.3).
    @Environment(\.playAlongCue) private var cue
    /// The fill span being selected (P8-7 12.1).
    @Environment(\.chordSpan) var span

    var body: some View {
        let tokens = LyricToken.tokens(for: line)
        if tokens.isEmpty {
            Color.clear.frame(height: style.lyricSize * 0.6)
        } else {
            LyricLineLayout(
                tokens: tokens,
                chordGap: style.chordSize * 0.35,
                chordLyricGap: style.chordGap,
                rowSpacing: style.rowSpacing,
            ) {
                ForEach(tokens) { token in
                    if let chord = token.chord {
                        // A chord unit: the chord (or bass note), then the concert chord
                        // small and muted beside it (P8-4 6.7), measured as one piece so
                        // the next chord and the lyrics never run under it.
                        HStack(alignment: .firstTextBaseline, spacing: style.chordSize * 0.25) {
                            Text(chord)
                                .font(Theme.font.liveChord(size: style.lyricSize))
                                .foregroundStyle(
                                    token.isUnknown ? Theme.color.muted : Theme.color.cueText,
                                )
                                .underline(isCue(token), color: Theme.color.cueText)
                            if let detail = token.detail {
                                Text(detail)
                                    .font(SchibstedGrotesk.medium.font(size: style.chordSize * 0.6))
                                    .foregroundStyle(Theme.color.muted)
                            }
                            if let approach = token.approach {
                                // The walk-up into the next chord (P8-4b 8.8).
                                let size = style.chordSize * 0.6
                                WalkUpRunView(
                                    run: approach,
                                    size: size,
                                    requested: $requestedWalkUp,
                                )
                            }
                        }
                        .fixedSize()
                        .modifier(ChordUnitSpanMark(index: spanIndex(token)))
                        .modifier(ChordUnitPlayback(chord: token.source, line: line.path))
                    }
                    Text(token.text)
                        .font(Theme.font.liveLyric(size: style.lyricSize))
                        .foregroundStyle(Theme.color.ink)
                        .fixedSize()
                }
                // The lyric face's space and line height, measured once per line.
                Text(" ")
                    .font(Theme.font.liveLyric(size: style.lyricSize))
                    .fixedSize()
                    .hidden()
            }
            // One element per line, read chords first (WS2b 4.9.2): "G, D: Van door slides
            // and the street lamps hum".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spokenText(tokens) { spanPlace($0) })
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(AccessibilityID.sheetLine)
            .walkUpActions(tokens.compactMap(\.approach), requested: $requestedWalkUp)
            .modifier(ChordPlayActions(tokens: tokens))
            .modifier(ChordSpanActionsModifier(line: line.path, tokens: tokens))
        }
    }

    /// Whether `token`'s chord is the one at the play-along playhead.
    private func isCue(_ token: LyricToken) -> Bool {
        guard let cue, let source = token.source else { return false }
        return cue.line == line.path && cue.offset == source.offset
    }

    /// A chord unit as spoken: "G" as is; a bass note "3 \u{00B7} B" reads "3, B", and with
    /// the chord beside "B, bass of G slash B" (P8-4 6.7). A chord that is just the note
    /// ("G" beside "G") is not read twice.
    static func spokenChord(_ chord: String, detail: String?) -> String {
        let note = chord.replacingOccurrences(of: " \u{00B7} ", with: ", ")
        let letter = chord.components(separatedBy: " \u{00B7} ").last ?? chord
        guard let detail, detail != letter else { return note }
        return "\(note), bass of \(detail.replacingOccurrences(of: "/", with: " slash "))"
    }

    /// "<chords>: <lyric>", or the lyric alone when the line has no chords.
    static func spokenText(
        _ tokens: [LyricToken],
        span: (LyricToken) -> String? = { _ in nil },
    ) -> String {
        let lyric = tokens.map(\.text).joined().trimmingCharacters(in: .whitespaces)
        let chords = tokens.compactMap { token in
            token.chord.map { chord in
                spokenChord(chord, detail: token.detail)
                    + (span(token).map { ", \($0)" } ?? "")
                    + (token.approach.map { ", \($0.accessibility)" } ?? "")
            }
        }
        guard !chords.isEmpty else { return lyric }
        let spokenChords = chords.joined(separator: ", ")
        return lyric.isEmpty ? spokenChords : "\(spokenChords): \(lyric)"
    }
}

/// A piece of a lyric line: a run of lyric text (at most one word, with its trailing
/// spaces) and the chord above its start, if any. A chord inside a word splits the word into
/// pieces that only `endsWord` tells apart: the line wraps between words, never between the
/// pieces of one word.
struct LyricToken: Identifiable, Equatable {
    let id: Int
    let chord: String?
    let text: String
    var isUnknown = false
    /// The small concert chord beside a bass note (P8-4 6.7).
    var detail: String?
    /// The walk-up run after the chord unit (P8-4b 8.8).
    var approach: ApproachRun?
    /// The chord the unit shows, for hearing it (P8-6 10.1).
    var source: RenderChord?
    /// The line may wrap after this piece: its text ends in whitespace, or it is the last
    /// piece of the line.
    var endsWord = true

    /// Trailing whitespace characters (drawn as space, never counted as ink at a row end).
    var trailingSpaces: Int {
        text.reversed().prefix(while: \.isWhitespace).count
    }

    /// The text has something to draw besides whitespace.
    var hasInk: Bool {
        text.contains { !$0.isWhitespace }
    }

    /// Splits `line` into pieces, keeping each chord on the piece it starts. A chord inside a
    /// word splits it there (the pieces stay one wrap unit). Whitespace stays attached to the
    /// preceding word, so the spacing of the lyric is preserved.
    static func tokens(for line: RenderLine) -> [Self] {
        var tokens = pieces(of: line)
        for index in tokens.indices {
            tokens[index].endsWord = index == tokens.count - 1
                || tokens[index].text.last?.isWhitespace == true
        }
        return tokens
    }

    private static func pieces(of line: RenderLine) -> [Self] {
        var tokens: [Self] = []
        for segment in segments(of: line) {
            let words = words(in: segment.text)
            if words.isEmpty {
                if let chord = segment.chord {
                    tokens.append(Self(
                        id: tokens.count,
                        chord: chord,
                        text: "",
                        isUnknown: segment.isUnknown,
                        detail: segment.detail,
                        approach: segment.approach,
                        source: segment.source,
                    ))
                }
                continue
            }
            for (offset, word) in words.enumerated() {
                let chord = offset == 0 ? segment.chord : nil
                tokens.append(Self(
                    id: tokens.count,
                    chord: chord,
                    text: word,
                    isUnknown: offset == 0 && segment.isUnknown,
                    detail: offset == 0 ? segment.detail : nil,
                    approach: offset == 0 ? segment.approach : nil,
                    source: offset == 0 ? segment.source : nil,
                ))
            }
        }
        return tokens
    }

    private struct Segment {
        var chord: String?
        var text: String
        var isUnknown = false
        var detail: String?
        var approach: ApproachRun?
        var source: RenderChord?
    }

    /// The lyric cut at each chord's offset: text before the first chord, then each chord
    /// with the text up to the next one (stacked chords get empty text).
    /// Lyric offsets go through `RenderLine.utf16Offset`, never `Character` indices of the
    /// joined lyric: a chord between a consonant and its combining sign (`प[G]्यार`) merges
    /// two lyric characters into one there, which would shift every later chord.
    private static func segments(of line: RenderLine) -> [Segment] {
        let utf16 = line.lyrics.utf16
        func text(_ from: Int, _ to: Int) -> String {
            let start = utf16.index(utf16.startIndex, offsetBy: from)
            let end = utf16.index(utf16.startIndex, offsetBy: max(to, from))
            // Decoded from the UTF-16 slice: a String range would round to whole
            // Characters and lose a split inside a merged character.
            return String(decoding: utf16[start ..< end], as: UTF16.self)
        }
        let end = line.utf16Offset(ofLyricOffset: line.lyricCount)
        var segments: [Segment] = []
        let firstStart = line.chords.first.map { line.utf16Offset(ofLyricOffset: $0.offset) }
            ?? end
        if firstStart > 0 {
            segments.append(Segment(chord: nil, text: text(0, firstStart)))
        }
        for (index, chord) in line.chords.enumerated() {
            let start = line.utf16Offset(ofLyricOffset: chord.offset)
            let next = index + 1 < line.chords.count
                ? line.utf16Offset(ofLyricOffset: line.chords[index + 1].offset)
                : end
            segments.append(Segment(
                chord: chord.text,
                text: text(start, next),
                isUnknown: chord.kind == .unknown,
                detail: chord.detail,
                approach: chord.approach,
                source: chord,
            ))
        }
        return segments
    }

    /// "Tum hi ho " -> ["Tum ", "hi ", "ho "]. Leading whitespace forms its own word.
    static func words(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var sawSpace = false
        for character in text {
            if character.isWhitespace {
                sawSpace = true
            } else if sawSpace, !current.isEmpty {
                words.append(current)
                current = ""
                sawSpace = false
            } else {
                sawSpace = false
            }
            current.append(character)
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}
