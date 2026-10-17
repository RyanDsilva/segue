#if os(macOS)
    import AppKit
    import Editing

    /// Metrics and text attributes of the visual canvas (mockup E2 b): 24 / 400 lyrics with
    /// line height 1.25, a 31pt chord lane above every lyric row (26pt pill + 4pt gap +
    /// 1pt air), 13 / 700 section labels with a hairline, 28pt between sections.
    @MainActor
    enum CanvasTypesetting {
        /// Pill: 16 / 700 text, padding 2 x 8, 1pt border, radius 6.
        static let pillHeight: CGFloat = 26
        static let pillHorizontalPadding: CGFloat = 8
        static let pillCornerRadius: CGFloat = 6
        /// Space between a pill and the lyric below it.
        static let pillGap: CGFloat = 4
        /// Space after a pill before the next chord's pill (mockup margin-right 8).
        static let pillTrailing: CGFloat = 8
        /// Space between stacked pills at one offset.
        static let stackSpacing: CGFloat = 4
        /// The chord lane above each lyric row.
        static let laneHeight: CGFloat = 31
        static let lyricLineHeight: CGFloat = 30
        /// Space between lyric lines and after a section label (mockup gap 10).
        static let lineSpacing: CGFloat = 10

        static func pillWidth(_ text: String) -> CGFloat {
            let width = (text as NSString).size(withAttributes: [.font: EditorStyle.pillFont]).width
            return ceil(width) + pillHorizontalPadding * 2 + 2
        }

        /// The width a group of chords stacked at one offset takes.
        static func groupWidth(_ chords: [RenderChord]) -> CGFloat {
            let widths = chords.map { pillWidth($0.text) }
            return widths.reduce(0, +) + stackSpacing * CGFloat(max(widths.count - 1, 0))
        }

        /// The attributed text of one paragraph, terminated by `separator` ("\n" or "").
        static func attributed(
            _ paragraph: CanvasParagraph,
            separator: String,
        ) -> NSAttributedString {
            let text = paragraph.text + separator
            let result = NSMutableAttributedString(
                string: text,
                attributes: attributes(for: paragraph),
            )
            if let line = paragraph.lyricLine {
                applyChordRoom(line, to: result)
            }
            return result
        }

        private static func attributes(for paragraph: CanvasParagraph)
            -> [NSAttributedString.Key: Any]
        {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = paragraph.spaceBefore
            var attributes: [NSAttributedString.Key: Any] = [:]
            switch paragraph.role {
            case .lyrics:
                // Every row gets the chord lane above it; TextKit puts the extra line height
                // above the glyphs.
                style.minimumLineHeight = laneHeight + lyricLineHeight
                style.maximumLineHeight = laneHeight + lyricLineHeight
                style.paragraphSpacing = lineSpacing
                attributes[.font] = EditorStyle.canvasLyricFont
                attributes[.foregroundColor] = EditorStyle.ink
            case .label:
                style.minimumLineHeight = 18
                style.maximumLineHeight = 18
                style.paragraphSpacing = lineSpacing
                attributes[.font] = EditorStyle.labelFont
                attributes[.foregroundColor] = EditorStyle.muted
            case .comment:
                style.paragraphSpacing = lineSpacing
                attributes[.font] = EditorStyle.commentFont
                attributes[.foregroundColor] = EditorStyle.muted
            case .stanzaBreak:
                style.minimumLineHeight = 6
                style.maximumLineHeight = 6
                attributes[.font] = NSFont.systemFont(ofSize: 4)
            case .verbatim:
                style.minimumLineHeight = 20
                style.maximumLineHeight = 20
                attributes[.font] = EditorStyle.verbatimFont
                attributes[.foregroundColor] = EditorStyle.ink
            case .textModeLink:
                style.paragraphSpacing = lineSpacing
                attributes[.font] = EditorStyle.grotesk(.semiBold, size: 13)
                attributes[.foregroundColor] = EditorStyle.cueText
                attributes[.link] = CanvasLink.textMode
                attributes[.cursor] = NSCursor.pointingHand
            case .emptyNote, .repeatNote:
                style.paragraphSpacing = lineSpacing
                attributes[.font] = EditorStyle.canvasLyricFont
                attributes[.foregroundColor] = EditorStyle.muted
            }
            attributes[.paragraphStyle] = style
            return attributes
        }

        /// Widens the lyric where pills would collide: adds kerning after the character
        /// before each chord, so a chord's pill (plus its trailing space) fits before the
        /// next chord, like the mockup's flowing segments.
        private static func applyChordRoom(_ line: RenderLine, to text: NSMutableAttributedString) {
            let groups = groups(of: line.chords)
            guard groups.count > 1 else { return }
            let lyrics = line.lyrics
            let font = EditorStyle.canvasLyricFont
            for (current, next) in zip(groups, groups.dropFirst()) {
                let from = LyricOffsets.utf16(current.offset, in: lyrics)
                let to = LyricOffsets.utf16(next.offset, in: lyrics)
                guard to > from else { continue }
                let span = (lyrics as NSString).substring(with: NSRange(
                    location: from,
                    length: to - from,
                ))
                let natural = (span as NSString).size(withAttributes: [.font: font]).width
                let needed = groupWidth(current.chords) + pillTrailing
                guard natural < needed else { continue }
                // The kern goes on the last character before the next chord.
                let lastCharacter = LyricOffsets.utf16(next.offset - 1, in: lyrics)
                let range = NSRange(location: lastCharacter, length: to - lastCharacter)
                text.addAttribute(.kern, value: needed - natural, range: range)
            }
        }

        struct ChordGroup {
            var offset: Int
            var chords: [RenderChord]
        }

        static func groups(of chords: [RenderChord]) -> [ChordGroup] {
            var groups: [ChordGroup] = []
            for chord in chords {
                if let last = groups.indices.last, groups[last].offset == chord.offset {
                    groups[last].chords.append(chord)
                } else {
                    groups.append(ChordGroup(offset: chord.offset, chords: [chord]))
                }
            }
            return groups
        }
    }

    /// Link targets inside the canvas text.
    enum CanvasLink {
        static let textMode = URL(string: "segue-editor:text-mode")!
    }
#endif
