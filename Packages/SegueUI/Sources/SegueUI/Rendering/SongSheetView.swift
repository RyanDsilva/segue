import ChordPro
import CoreText
import Editing
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

    /// Distance from the top of a lyric line to its lyric baseline, so the section label
    /// can sit on the first lyric's baseline rather than on the chord above it.
    func lyricBaselineOffset(hasChords: Bool) -> CGFloat {
        let lyric = FontMetrics(face: .regular, size: lyricSize)
        let chord = FontMetrics(face: .bold, size: chordSize)
        return (hasChords ? chord.lineHeight + chordGap : 0) + lyric.ascent
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

    var body: some View {
        // One lazy row per item: a 200-line song only builds the rows on screen, and typing
        // re-renders only the row whose content changed (rows are Equatable).
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(SheetRow.rows(of: sections, style: style)) { row in
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
    }

    /// Section id and item index: stable while the structure is unchanged.
    let id: String
    let label: String?
    let isChorus: Bool
    let content: Content
    let topSpacing: CGFloat

    static func rows(of sections: [RenderSection], style: SongSheetStyle) -> [Self] {
        var rows: [Self] = []
        for section in sections {
            let sectionSpacing = rows.isEmpty ? 0 : style.sectionSpacing
            let isChorus = section.kind == .chorus
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
                ))
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
            switch row.content {
            case let .repeatNote(text):
                Text(text)
                    .font(Theme.font.liveLyric(size: style.lyricSize))
                    .foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case let .item(.lyrics(line)):
                let offset = baselineOffset(line)
                ItemView(item: .lyrics(line), style: style)
                    .alignmentGuide(.firstTextBaseline) { $0[.top] + offset }
                    .frame(maxWidth: .infinity, alignment: .leading)
            case let .item(item):
                ItemView(item: item, style: style)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, row.topSpacing)
    }

    /// The label sits on the first lyric's baseline, not on the chord above it.
    private func baselineOffset(_ line: RenderLine) -> CGFloat {
        style.lyricBaselineOffset(hasChords: !line.chords.isEmpty)
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
/// when it is wider than the column.
private struct LyricLineView: View {
    let line: RenderLine
    let style: SongSheetStyle

    var body: some View {
        let tokens = LyricToken.tokens(for: line)
        if tokens.isEmpty {
            Color.clear.frame(height: style.lyricSize * 0.6)
        } else {
            let hasChords = tokens.contains { $0.chord != nil }
            LyricFlowLayout(rowSpacing: style.rowSpacing) {
                ForEach(tokens) { token in
                    TokenView(token: token, showsChordRow: hasChords, style: style)
                }
            }
        }
    }
}

private struct TokenView: View {
    let token: LyricToken
    let showsChordRow: Bool
    let style: SongSheetStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.chordGap) {
            if showsChordRow {
                Text(token.chord ?? " ")
                    .font(Theme.font.liveChord(size: style.lyricSize))
                    .foregroundStyle(token.isUnknown ? Theme.color.muted : Theme.color.cueText)
                    .padding(.trailing, token.chord == nil ? 0 : style.chordSize * 0.35)
                    .accessibilityIdentifier(token.chord == nil ? "" : AccessibilityID.sheetChord)
                    .accessibilityHidden(token.chord == nil)
            }
            Text(token.text)
                .font(Theme.font.liveLyric(size: style.lyricSize))
                .foregroundStyle(Theme.color.ink)
                .accessibilityIdentifier(AccessibilityID.sheetLyric)
        }
        .fixedSize()
    }
}

/// A wrap unit: one word (with its trailing spaces) and the chord above its start, if any.
struct LyricToken: Identifiable, Equatable {
    let id: Int
    let chord: String?
    let text: String
    var isUnknown = false

    /// Splits `line` into words, keeping each chord on the word it starts. A chord inside a
    /// word splits it there. Whitespace stays attached to the preceding word, so the spacing
    /// of the lyric is preserved.
    static func tokens(for line: RenderLine) -> [Self] {
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
                ))
            }
        }
        return tokens
    }

    private struct Segment {
        var chord: String?
        var text: String
        var isUnknown = false
    }

    /// The lyric cut at each chord's offset: text before the first chord, then each chord
    /// with the text up to the next one (stacked chords get empty text).
    private static func segments(of line: RenderLine) -> [Segment] {
        let characters = Array(line.lyrics)
        var segments: [Segment] = []
        let firstOffset = line.chords.first.map { min($0.offset, characters.count) } ?? characters
            .count
        if firstOffset > 0 {
            segments.append(Segment(chord: nil, text: String(characters[0 ..< firstOffset])))
        }
        for (index, chord) in line.chords.enumerated() {
            let start = min(max(chord.offset, 0), characters.count)
            let end = index + 1 < line.chords.count
                ? min(max(line.chords[index + 1].offset, start), characters.count)
                : characters.count
            segments.append(Segment(
                chord: chord.text,
                text: String(characters[start ..< end]),
                isUnknown: chord.kind == .unknown,
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

/// Lays children out left to right, wrapping to a new row when the next child would
/// overflow the proposed width.
struct LyricFlowLayout: Layout {
    var rowSpacing: CGFloat

    /// Child sizes, measured once per layout pass (children are fixed-size tokens).
    struct Cache {
        var sizes: [CGSize]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews _: Subviews,
        cache: inout Cache,
    ) -> CGSize {
        let rows = rows(for: cache.sizes, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache,
    ) {
        var y = bounds.minY
        for row in rows(for: cache.sizes, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = cache.sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size),
                )
                x += size.width
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for sizes: [CGSize], width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, size) in sizes.enumerated() {
            if !row.indices.isEmpty, row.width + size.width > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.indices.append(index)
            row.width += size.width
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}

/// Line metrics of a bundled face, read from Core Text (matches what `Text` lays out).
struct FontMetrics {
    let ascent: CGFloat
    let lineHeight: CGFloat

    init(face: SchibstedGrotesk, size: CGFloat) {
        let font = CTFontCreateWithName(face.rawValue as CFString, size, nil)
        ascent = CTFontGetAscent(font)
        lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }
}
