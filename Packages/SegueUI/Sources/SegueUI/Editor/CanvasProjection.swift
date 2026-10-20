#if os(macOS)
    import AppKit
    import ChordPro
    import Editing

    /// One paragraph of the visual canvas text. The canvas is a projection of the
    /// `RenderModel`: section labels and lyric lines are editable text, everything else is
    /// read-only, and chords are drawn as pills over the lyrics (never part of the text).
    struct CanvasParagraph: Equatable {
        enum Role: Equatable {
            /// A section header. Editable when it stands for a `{start_of_...}` line.
            case label(section: BlockPath?, fallback: String, editable: Bool)
            case lyrics(RenderLine)
            case comment(BlockPath)
            case stanzaBreak(BlockPath)
            /// A tab/grid body line (read-only).
            case verbatim(BlockPath)
            /// "Edit in text mode" under a tab/grid label.
            case textModeLink(section: BlockPath?)
            /// `{chorus}`: "Repeat Chorus".
            case repeatNote
            /// The song has no sections yet.
            case emptyNote
        }

        var text: String
        var role: Role
        /// Extra space above (the gap between sections).
        var spaceBefore: CGFloat = 0

        var isLyrics: Bool {
            if case .lyrics = role {
                return true
            }
            return false
        }

        var lyricLine: RenderLine? {
            if case let .lyrics(line) = role {
                return line
            }
            return nil
        }

        var isEditable: Bool {
            switch role {
            case .lyrics: true
            case let .label(_, _, editable): editable
            default: false
            }
        }
    }

    /// The canvas text as paragraphs, with their UTF-16 starts.
    struct CanvasProjection: Equatable {
        static let sectionGap: CGFloat = 28

        var paragraphs: [CanvasParagraph]
        /// UTF-16 start of each paragraph in the joined text (paragraphs are separated by
        /// one "\n"; the last has none).
        private(set) var starts: [Int]
        /// Lyric line path -> paragraph index.
        private(set) var lyricParagraphs: [BlockPath: Int]

        init(paragraphs: [CanvasParagraph]) {
            self.paragraphs = paragraphs
            var starts: [Int] = []
            var lyricParagraphs: [BlockPath: Int] = [:]
            var offset = 0
            for (index, paragraph) in paragraphs.enumerated() {
                starts.append(offset)
                offset += paragraph.text.utf16.count + 1
                if let line = paragraph.lyricLine {
                    lyricParagraphs[line.path] = index
                }
            }
            self.starts = starts
            self.lyricParagraphs = lyricParagraphs
        }

        /// The projection of a render model.
        init(model: RenderModel) {
            var paragraphs: [CanvasParagraph] = []
            for section in model.sections {
                var gap: CGFloat = paragraphs.isEmpty ? 0 : Self.sectionGap
                let fallback = Self.kindName(section.kind)
                if section.isRepeat {
                    let label = section.label.flatMap { $0.isEmpty ? nil : $0 } ?? "Chorus"
                    paragraphs.append(CanvasParagraph(
                        text: "Repeat \(label)",
                        role: .repeatNote,
                        spaceBefore: gap,
                    ))
                    continue
                }
                let labelText = section.label.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
                // The section band (P3-11) shows a section's label in the lane beside its
                // lines; only a section with no lines keeps a label row to hang its band on.
                if section.path != nil, section.items.isEmpty, section.isEditable {
                    let editable = section.path != nil && section.isEditable
                    paragraphs.append(CanvasParagraph(
                        text: labelText,
                        role: .label(section: section.path, fallback: fallback, editable: editable),
                        spaceBefore: gap,
                    ))
                    gap = 0
                }
                if !section.isEditable {
                    paragraphs.append(CanvasParagraph(
                        text: "Edit in text mode",
                        role: .textModeLink(section: section.path),
                        spaceBefore: gap,
                    ))
                    gap = 0
                }
                for item in section.items {
                    var paragraph = Self.paragraph(for: item)
                    paragraph.spaceBefore = gap
                    gap = 0
                    paragraphs.append(paragraph)
                }
            }
            if paragraphs.isEmpty {
                paragraphs.append(CanvasParagraph(
                    text: "No lyrics yet. Switch to Text to write the song.",
                    role: .emptyNote,
                ))
            }
            self.init(paragraphs: paragraphs)
        }

        private static func paragraph(for item: RenderItem) -> CanvasParagraph {
            switch item {
            case let .lyrics(line):
                CanvasParagraph(text: line.lyrics, role: .lyrics(line))
            case let .comment(text, _, path):
                CanvasParagraph(text: text, role: .comment(path))
            case let .stanzaBreak(path):
                CanvasParagraph(text: "", role: .stanzaBreak(path))
            case let .verbatim(text, path):
                CanvasParagraph(text: text, role: .verbatim(path))
            }
        }

        static func kindName(_ kind: SectionKind?) -> String {
            switch kind {
            case .verse: "Verse"
            case .chorus: "Chorus"
            case .bridge: "Bridge"
            case .tab: "Tab"
            case let .custom(name): name.replacingOccurrences(of: "_", with: " ").capitalized
            case nil: ""
            }
        }

        /// The full canvas text.
        var text: String {
            paragraphs.map(\.text).joined(separator: "\n")
        }

        var length: Int {
            guard let last = paragraphs.indices.last else { return 0 }
            return starts[last] + paragraphs[last].text.utf16.count
        }

        /// The paragraph holding a UTF-16 location (a location on a separator belongs to the
        /// paragraph it ends).
        func paragraphIndex(at location: Int) -> Int {
            var low = 0
            var high = starts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if starts[mid] <= location {
                    low = mid
                } else {
                    high = mid - 1
                }
            }
            return max(low, 0)
        }

        /// UTF-16 range of paragraph `index`, without its separator.
        func range(of index: Int) -> NSRange {
            NSRange(location: starts[index], length: paragraphs[index].text.utf16.count)
        }
    }

    /// Lyric-line helpers in lyric offsets (`RenderLine.characterStarts`).
    enum LyricOffsets {
        /// The words of `line` (runs of non-whitespace) as lyric offset ranges.
        static func words(in line: RenderLine) -> [(offsets: Range<Int>, word: String)] {
            var result: [(Range<Int>, String)] = []
            var current = ""
            var start = 0
            for offset in 0 ..< line.lyricCount {
                let character = line.character(at: offset)
                if character.allSatisfy(\.isWhitespace) {
                    if !current.isEmpty {
                        result.append((start ..< offset, current))
                        current = ""
                    }
                } else {
                    if current.isEmpty {
                        start = offset
                    }
                    current += character
                }
            }
            if !current.isEmpty {
                result.append((start ..< line.lyricCount, current))
            }
            return result
        }
    }
#endif
