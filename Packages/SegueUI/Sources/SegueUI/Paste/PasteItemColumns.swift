#if os(macOS)
    import ChordPro
    import Editing
    import Library
    import SwiftUI

    /// One song's two sides (layout "a"): the original as pasted (junk lines struck through,
    /// unknown lines flagged) and the result (the song card in draft mode, then a preview
    /// whose AI-decided labels carry the sparkle, or the ChordPro text in Edit in Text).
    struct PasteItemColumns: View {
        @Bindable var item: PasteReviewItem
        let context: PasteReviewContext
        @State private var isEditingText = false

        var body: some View {
            // Layout "a": the original takes 44%, the result (card and preview) the rest.
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    original
                        .frame(width: (proxy.size.width * 0.44).rounded())
                    Rule(axis: .vertical)
                    result
                        .frame(maxWidth: .infinity)
                }
            }
        }

        // MARK: Original

        private var original: some View {
            VStack(alignment: .leading, spacing: 10) {
                PasteColumnHeading(
                    title: item.fileName.map { "Original · \($0)" } ?? "Original",
                )
                GeometryReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        // At least the viewport's size, so a short text sits top left
                        // instead of centred.
                        originalLines
                            .padding(.bottom, 12)
                            .padding(.trailing, 18)
                            .frame(
                                minWidth: proxy.size.width,
                                minHeight: proxy.size.height,
                                alignment: .topLeading,
                            )
                    }
                }
                .accessibilityIdentifier(AccessibilityID.pasteOriginal)
            }
            .padding(.top, 14)
            .padding(.leading, 18)
        }

        private var originalLines: some View {
            let removed = item.removedLines
            let unknown = item.unknownLines
            let lines = item.original.components(separatedBy: .newlines)
            return VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .foregroundStyle(Theme.color.indicatorOff)
                            .frame(width: 24, alignment: .trailing)
                            .accessibilityHidden(true)
                        Text(line.isEmpty ? " " : line)
                            .strikethrough(!trimmed.isEmpty && removed.contains(trimmed))
                            .foregroundStyle(
                                removed.contains(trimmed) && !trimmed.isEmpty
                                    ? Theme.color.indicatorOff : Theme.color.ink,
                            )
                            .padding(.horizontal, 2)
                            .background(
                                !trimmed.isEmpty && unknown.contains(trimmed)
                                    ? Color.orange.opacity(0.16) : .clear,
                                in: RoundedRectangle(cornerRadius: 3),
                            )
                            .fixedSize()
                    }
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
        }

        // MARK: Result

        private var result: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PasteColumnHeading(title: "Result")
                    if item.hasAIDecisions {
                        HStack(spacing: 3) {
                            SparkleMark()
                            Text("= decided by AI")
                        }
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Sparkles mark what AI decided")
                    }
                    Spacer()
                    Button(isEditingText ? "Preview" : "Edit in Text") {
                        isEditingText.toggle()
                    }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .accessibilityIdentifier(AccessibilityID.pasteEditToggle)
                }
                .padding(.trailing, 18)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        card
                        Rule()
                        if isEditingText {
                            TextEditor(text: textBinding)
                                .font(.system(size: 12.5, design: .monospaced))
                                .autocorrectionDisabled()
                                .frame(minHeight: 320)
                                .accessibilityLabel("ChordPro text")
                                .accessibilityIdentifier(AccessibilityID.pasteResultText)
                        } else {
                            PasteChartPreview(item: item)
                        }
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 14)
                }
            }
            .padding(.top, 14)
            .padding(.leading, 18)
        }

        private var card: some View {
            VStack(alignment: .leading, spacing: 8) {
                SongCardDraft(
                    source: textBinding,
                    metadata: $item.metadata,
                    knownArtists: context.knownArtists,
                    knownTags: context.knownTags,
                )
                HStack(spacing: 10) {
                    Button("Swap Title and Artist", systemImage: "arrow.up.arrow.down") {
                        item.swapTitleAndArtist()
                    }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .disabled(!item.canSwapTitleAndArtist)
                    .help("Some sites write “Artist - Title”")
                    .accessibilityIdentifier(AccessibilityID.pasteSwap)
                    if !item.aiFields.isEmpty {
                        HStack(spacing: 4) {
                            SparkleMark()
                            Text(aiFieldsText)
                        }
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }

        private var aiFieldsText: String {
            switch (item.aiFields.contains(.title), item.aiFields.contains(.artist)) {
            case (true, true): "Title and artist decided by AI"
            case (true, false): "Title decided by AI"
            default: "Artist decided by AI"
            }
        }

        /// Edits from the card and the text editor go through `edit` (refinement stops).
        private var textBinding: Binding<String> {
            Binding(get: { item.text }, set: { item.edit($0) })
        }
    }

    /// "ORIGINAL" / "RESULT".
    struct PasteColumnHeading: View {
        let title: String

        var body: some View {
            Text(title.uppercased())
                .font(SchibstedGrotesk.bold.font(size: 11))
                .tracking(0.6)
                .foregroundStyle(Theme.color.muted)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// The accent sparkle that marks an AI decision (design D1).
    struct SparkleMark: View {
        var body: some View {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.color.cue)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Chart preview

    /// The result as the performer will read it: section labels in the margin (AI-decided
    /// ones with the sparkle), chords over lyrics, notes in italics (amber dot when code
    /// could not place the line).
    struct PasteChartPreview: View {
        let item: PasteReviewItem

        var body: some View {
            let document = SourceSnapshot(text: item.text).document
            let marked = item.aiSectionOrdinals(in: document)
            let unknown = item.unknownLines
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rows(document).enumerated()), id: \.offset) { _, row in
                    switch row {
                    case let .section(ordinal, label, lines):
                        sectionView(label: label, isAI: marked.contains(ordinal), lines: lines)
                    case let .line(line):
                        lyricRow(label: nil, isAI: false, line: line)
                    case let .note(text):
                        noteRow(text, flagged: unknown.contains(text))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.pasteResult)
        }

        enum Row {
            case section(ordinal: Int, label: String, lines: [ChordPro.Line])
            case line(ChordPro.Line)
            case note(String)
        }

        private func rows(_ document: SongDocument) -> [Row] {
            var rows: [Row] = []
            var ordinal = 0
            for block in document.blocks {
                switch block {
                case let .section(section):
                    let lines = section.items.compactMap { item -> ChordPro.Line? in
                        if case let .line(line) = item {
                            return line
                        }
                        return nil
                    }
                    rows.append(.section(
                        ordinal: ordinal,
                        label: Self.label(section),
                        lines: lines,
                    ))
                    ordinal += 1
                case let .line(line):
                    rows.append(.line(line))
                case let .commentDirective(comment):
                    rows.append(.note(comment.text.trimmingCharacters(in: .whitespaces)))
                default:
                    continue
                }
            }
            return rows
        }

        static func label(_ section: ChordPro.Section) -> String {
            if let label = section.label, !label.isEmpty {
                return label
            }
            return switch section.kind {
            case .chorus: "Chorus"
            case .verse: "Verse"
            case .bridge: "Bridge"
            case .tab: "Tab"
            case let .custom(name): name.prefix(1).uppercased() + name.dropFirst()
            }
        }

        private func sectionView(label: String, isAI: Bool, lines: [ChordPro.Line]) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    lyricRow(label: index == 0 ? label : nil, isAI: isAI, line: line)
                }
                if lines.isEmpty {
                    lyricRow(label: label, isAI: isAI, line: ChordPro.Line(segments: []))
                }
            }
        }

        private func lyricRow(label: String?, isAI: Bool, line: ChordPro.Line) -> some View {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Group {
                    if let label {
                        HStack(spacing: 3) {
                            Text(label)
                            if isAI {
                                SparkleMark()
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label)
                        .accessibilityValue(isAI ? "AI" : "")
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier(AccessibilityID.pasteSectionLabel)
                        .help(isAI ? "\(label): labelled by AI" : label)
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .font(SchibstedGrotesk.bold.font(size: 12))
                .foregroundStyle(Theme.color.muted)
                .frame(width: 96, alignment: .leading)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(line.segments.enumerated()), id: \.offset) { _, segment in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(segment.chord ?? " ")
                                .font(SchibstedGrotesk.bold.font(size: 12))
                                .foregroundStyle(Theme.color.cueText)
                            Text(segment.text.isEmpty ? " " : segment.text)
                                .font(SchibstedGrotesk.medium.font(size: 14))
                                .foregroundStyle(Theme.color.ink)
                        }
                        .fixedSize()
                    }
                }
            }
        }

        private func noteRow(_ text: String, flagged: Bool) -> some View {
            HStack(spacing: 0) {
                Text("Note")
                    .font(SchibstedGrotesk.bold.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 96, alignment: .leading)
                if flagged {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                        .padding(.trailing, 6)
                        .help("Segue could not place this line, so it is kept as a note")
                }
                Text(text)
                    .font(SchibstedGrotesk.medium.font(size: 13).italic())
                    .foregroundStyle(Theme.color.muted)
            }
        }
    }

    // MARK: - Batch list (R96)

    /// Every file that needs converting, each with its checkbox (ticked by default) and
    /// its refinement state; selecting one shows its preview and song card.
    struct PasteBatchList: View {
        @Bindable var review: PasteReviewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                PasteColumnHeading(title: "\(review.items.count) files to convert")
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(review.items) { item in
                            row(item)
                            Rule()
                        }
                    }
                }
                Text("Unticked files are not imported.")
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .padding(14)
            }
            .background(Theme.color.surfaceAlt)
        }

        private func row(_ item: PasteReviewItem) -> some View {
            let isSelected = review.selected?.id == item.id
            let title = SourceSnapshot(text: item.text).document.metadata.title
            return HStack(alignment: .top, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { item.isTicked },
                    set: { review.setTicked($0, for: item.id) },
                )) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(item.fileName ?? "Song")
                .accessibilityIdentifier(AccessibilityID.pasteBatchTick)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled")
                        .font(SchibstedGrotesk.bold.font(size: 13))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    Text(item.fileName ?? "")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                }
                .opacity(item.isTicked ? 1 : 0.5)
                Spacer(minLength: 4)
                if case .running = item.status {
                    ProgressView().controlSize(.mini)
                        .accessibilityLabel("Refining")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.color.line : .clear)
            .contentShape(Rectangle())
            .onTapGesture { review.selectedID = item.id }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(item.fileName ?? "Song")
            .accessibilityIdentifier(AccessibilityID.pasteBatchRow)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
#endif
