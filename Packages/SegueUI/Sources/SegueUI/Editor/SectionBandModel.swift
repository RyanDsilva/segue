#if os(macOS)
    import ChordPro
    import Editing

    /// One band in the visual editor's section lane (P3-11, direction B): a section, a run
    /// of lines outside any section (an empty slot), or a `{chorus}` repeat outside any
    /// section (a hollow marker). Built from the canvas projection and the document, so it
    /// always matches what is on screen.
    struct SectionBand: Equatable {
        enum Kind: Equatable {
            /// A `{start_of_...}` section; `editable` is false for tab/grid.
            case section(path: BlockPath, kind: SectionKind, label: String?, editable: Bool)
            /// Lines outside any section.
            case slot
            /// A top-level `{chorus}`: not resizable, not a section.
            case repeatRef(label: String)
        }

        var kind: Kind
        /// The canvas paragraphs it spans (contiguous).
        var paragraphs: ClosedRange<Int>

        var sectionPath: BlockPath? {
            if case let .section(path, _, _, _) = kind {
                return path
            }
            return nil
        }

        /// What the cap shows: the label, else the kind's plain name.
        var title: String {
            switch kind {
            case let .section(_, kind, label, _):
                label ?? SectionLabels.displayName(kind)
            case .slot:
                ""
            case let .repeatRef(label):
                label
            }
        }
    }

    /// The bands of one projection, plus each paragraph's source block path (what edge
    /// drags and wraps address).
    struct SectionBandModel: Equatable {
        var bands: [SectionBand] = []
        /// Paragraph index -> the block path it stands for (nil for notes and links).
        var paths: [BlockPath?] = []

        init() {}

        init(projection: CanvasProjection, document: SongDocument) {
            let repeats = Self.chorusRefPaths(in: document)
            var repeatIndex = 0
            var owners: [Owner?] = []
            for paragraph in projection.paragraphs {
                let path = Self.path(of: paragraph, repeats: repeats, next: &repeatIndex)
                paths.append(path)
                owners.append(Self.owner(
                    of: paragraph,
                    path: path,
                    previous: owners.last.flatMap(\.self),
                ))
            }
            var index = 0
            while index < owners.count {
                guard let owner = owners[index] else {
                    index += 1
                    continue
                }
                var end = index
                while end + 1 < owners.count, owners[end + 1] == owner,
                      !(owner.isSlot && projection.paragraphs[end + 1].spaceBefore > 0)
                {
                    end += 1
                }
                if let band = Self.band(owner, paragraphs: index ... end, document: document) {
                    bands.append(band)
                }
                index = end + 1
            }
        }

        /// The band holding paragraph `index`.
        func band(containing index: Int) -> SectionBand? {
            bands.first { $0.paragraphs.contains(index) }
        }

        /// The band of a section header path.
        func band(of section: BlockPath) -> SectionBand? {
            bands.first { $0.sectionPath == section }
        }

        /// The section bands after `band`, nearest first.
        func sections(after band: SectionBand) -> [SectionBand] {
            bands.filter {
                $0.sectionPath != nil && $0.paragraphs.lowerBound > band.paragraphs.upperBound
            }
        }

        // MARK: - Building

        private enum Owner: Equatable {
            case section(Int)
            case slot
            case repeatRef(BlockPath)

            var isSlot: Bool {
                self == .slot
            }
        }

        /// The block path a paragraph stands for; repeats take the next `{chorus}` path.
        private static func path(
            of paragraph: CanvasParagraph,
            repeats: [BlockPath],
            next repeatIndex: inout Int,
        ) -> BlockPath? {
            switch paragraph.role {
            case let .lyrics(line): return line.path
            case let .comment(item), let .stanzaBreak(item), let .verbatim(item): return item
            case let .label(section, _, _): return section
            case let .textModeLink(section): return section
            case .repeatNote:
                defer { repeatIndex += 1 }
                return repeats.indices.contains(repeatIndex) ? repeats[repeatIndex] : nil
            case .emptyNote: return nil
            }
        }

        private static func owner(
            of paragraph: CanvasParagraph,
            path: BlockPath?,
            previous: Owner?,
        ) -> Owner? {
            if case .emptyNote = paragraph.role {
                return nil
            }
            if case .repeatNote = paragraph.role {
                guard let path else { return nil }
                return path.item == nil ? .repeatRef(path) : .section(path.block)
            }
            if case let .label(section, _, _) = paragraph.role {
                return section.map { .section($0.block) }
            }
            guard let path else {
                // A link under a tab/grid continuation part belongs to the section before.
                if case .section = previous {
                    return previous
                }
                return nil
            }
            if path.item != nil {
                return .section(path.block)
            }
            return .slot
        }

        private static func band(
            _ owner: Owner,
            paragraphs: ClosedRange<Int>,
            document: SongDocument,
        ) -> SectionBand? {
            switch owner {
            case let .section(block):
                guard document.blocks.indices.contains(block),
                      case let .section(section) = document.blocks[block]
                else { return nil }
                let label = section.label.flatMap { $0.isEmpty ? nil : $0 }
                return SectionBand(
                    kind: .section(
                        path: BlockPath(block: block),
                        kind: section.kind,
                        label: label,
                        editable: !DirectiveLine.isVerbatimSection(section.kind),
                    ),
                    paragraphs: paragraphs,
                )
            case .slot:
                return SectionBand(kind: .slot, paragraphs: paragraphs)
            case let .repeatRef(path):
                guard document.blocks.indices.contains(path.block),
                      case let .chorusRef(ref) = document.blocks[path.block]
                else { return nil }
                let label = ref.label.flatMap { $0.isEmpty ? nil : $0 } ?? "Chorus"
                return SectionBand(kind: .repeatRef(label: label), paragraphs: paragraphs)
            }
        }

        /// Every `{chorus}` in document order (the render model emits one repeat for each).
        private static func chorusRefPaths(in document: SongDocument) -> [BlockPath] {
            var result: [BlockPath] = []
            for (index, block) in document.blocks.enumerated() {
                switch block {
                case .chorusRef:
                    result.append(BlockPath(block: index))
                case let .section(section):
                    for (item, inner) in section.items.enumerated() {
                        if case .chorusRef = inner {
                            result.append(BlockPath(block: index, item: item))
                        }
                    }
                default:
                    continue
                }
            }
            return result
        }
    }
#endif
