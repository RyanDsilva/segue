import ChordPro
import CoreText
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

    /// Editor preview and song detail.
    static let preview = Self(lyricSize: 17, gutterWidth: 72, sectionSpacing: 22)
    /// Live view (brand.md section 6: default 24).
    static let stage = Self(lyricSize: 24, sectionSpacing: 32)
}

/// Renders a song body from `SongDocument.displaySections`: a section label gutter on the
/// left, lyric lines with each chord above the start of its syllable.
struct SongSheetView: View {
    let sections: [DisplaySection]
    let style: SongSheetStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.sectionSpacing) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                SectionView(section: section, style: style)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionView: View {
    let section: DisplaySection
    let style: SongSheetStyle

    var body: some View {
        let lyricOffset = firstLyricBaselineOffset
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // A collapsed repeat says what it repeats in the lyric column; no gutter label.
            Text(section.isRepeat ? "" : labelText)
                .font(Theme.font.label)
                .foregroundStyle(section.kind == .chorus ? Theme.color.ink : Theme.color.muted)
                .lineLimit(2)
                .frame(width: style.gutterWidth - 12, alignment: .leading)
                .padding(.trailing, 12)
                .accessibilityIdentifier(AccessibilityID.sheetSectionLabel)
            if section.isRepeat {
                Text(repeatText)
                    .font(Theme.font.liveLyric(size: style.lyricSize))
                    .foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: style.rowSpacing) {
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        LyricLineView(line: line, style: style)
                    }
                }
                .alignmentGuide(.firstTextBaseline) { [offset = lyricOffset] dimensions in
                    dimensions[.top] + offset
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var firstLyricBaselineOffset: CGFloat {
        let hasChords = section.lines.first?.segments.contains { $0.chord != nil } ?? false
        return style.lyricBaselineOffset(hasChords: hasChords)
    }

    private var labelText: String {
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

    private var repeatText: String {
        if let label = section.label, label.caseInsensitiveCompare("Chorus") != .orderedSame {
            return "Repeat \(label)"
        }
        return "Repeat chorus"
    }
}

/// One lyric line. Each chord sits above the start of its text; the line wraps between
/// words when it is wider than the column.
private struct LyricLineView: View {
    let line: Line
    let style: SongSheetStyle

    var body: some View {
        let tokens = LyricToken.tokens(for: line)
        if tokens.isEmpty {
            // A blank line inside a section is a stanza break.
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
                    .foregroundStyle(Theme.color.cueText)
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

    /// Splits `line` into words, keeping each chord on the word it starts. Whitespace stays
    /// attached to the preceding word, so the spacing of the lyric is preserved.
    static func tokens(for line: Line) -> [Self] {
        var tokens: [Self] = []
        for segment in line.segments {
            let words = words(in: segment.text)
            if words.isEmpty {
                if let chord = segment.chord {
                    tokens.append(Self(id: tokens.count, chord: chord, text: ""))
                }
                continue
            }
            for (offset, word) in words.enumerated() {
                let chord = offset == 0 ? segment.chord : nil
                tokens.append(Self(id: tokens.count, chord: chord, text: word))
            }
        }
        return tokens
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
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

    private func rows(for subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
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
