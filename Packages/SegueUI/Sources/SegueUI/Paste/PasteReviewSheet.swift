#if os(macOS)
    import Library
    import ModelPort
    import Services
    import SwiftUI

    // The paste review sheet (spec 6.2, design D1 "Sparkle marks", Ryan's pick 2026-10-19):
    // original left, result right, AI decisions marked with a small accent sparkle, the
    // "Refining with ..." line top right, a one-line footer. It never waits on a model.

    /// What the sheet needs from outside: the AI state for the footer and the actions that
    /// leave it.
    @MainActor
    struct PasteReviewContext {
        var aiEnabled: Bool
        var availability: [ProviderKind: ProviderAvailability]
        var knownArtists: [String]
        var knownTags: [String]
        var accept: () -> Void
        var cancel: () -> Void
        var startBlank: () -> Void
        /// Settings > AI (the quiet download link, R93).
        var openAISettings: () -> Void
        /// The R69 "Open System Settings".
        var openSystemSettings: () -> Void
    }

    struct PasteReviewSheet: View {
        @Bindable var review: PasteReviewModel
        let context: PasteReviewContext

        var body: some View {
            Group {
                switch review.phase {
                case .input:
                    PasteInputView(review: review, context: context)
                case .review:
                    reviewBody
                }
            }
            .background(Theme.color.ground)
            .accessibilityIdentifier(AccessibilityID.pasteSheet)
        }

        private var reviewBody: some View {
            VStack(spacing: 0) {
                header
                Rule()
                HStack(spacing: 0) {
                    if review.isBatch {
                        PasteBatchList(review: review)
                            .frame(width: 260)
                        Rule(axis: .vertical)
                    }
                    if let item = review.selected {
                        PasteItemColumns(item: item, context: context)
                            .id(item.id)
                    }
                }
                .frame(maxHeight: .infinity)
                Rule()
                footer
            }
            .frame(
                minWidth: review.isBatch ? 1180 : 940,
                idealWidth: review.isBatch ? 1320 : 1080,
                minHeight: 560,
                idealHeight: 700,
            )
        }

        // MARK: Header

        private var header: some View {
            HStack(spacing: 10) {
                Text(review.isBatch || review.importMethod != nil ? "Import Songs" : "Review Song")
                    .font(SchibstedGrotesk.extraBold.font(size: 17))
                    .foregroundStyle(Theme.color.ink)
                Text(subtitle)
                    .font(SchibstedGrotesk.medium.font(size: 12.5))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let line = footerContent?.refiningLine {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text(line)
                    }
                    .font(SchibstedGrotesk.medium.font(size: 12.5))
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.pasteRefining)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }

        private var subtitle: String {
            if review.isBatch || review.importMethod != nil {
                let convert = review.items.count
                var parts = [convert == 1 ? "1 file needs converting" :
                    "\(convert) files need converting"]
                let direct = review.directFiles.count
                if direct > 0 {
                    parts.append(direct == 1 ? "1 ChordPro file imports with them" :
                        "\(direct) ChordPro files import with them")
                }
                return parts.joined(separator: "; ")
            }
            switch review.selected?.source {
            case .clipboard, .emptyState, .listPaste: return "from the clipboard"
            case .newSong: return "new song"
            case .fileCrd, .fileTxt, nil: return review.selected?.fileName ?? ""
            }
        }

        // MARK: Footer

        private var footerContent: PasteFooter? {
            guard let item = review.selected else { return nil }
            return PasteFooter.make(
                status: item.status,
                reports: item.reports,
                aiEnabled: context.aiEnabled,
                availability: context.availability,
            )
        }

        private var footer: some View {
            HStack(spacing: 10) {
                if let content = footerContent {
                    footerLine(content)
                }
                Spacer(minLength: 12)
                Button("Cancel", action: context.cancel)
                    .buttonStyle(.segueSecondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AccessibilityID.pasteCancel)
                Button(review.acceptTitle, action: context.accept)
                    .buttonStyle(.seguePrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!review.canAccept)
                    .help("Save to the library (⌘↩)")
                    .accessibilityIdentifier(AccessibilityID.pasteAccept)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }

        @ViewBuilder
        private func footerLine(_ content: PasteFooter) -> some View {
            let item = review.selected
            HStack(spacing: 8) {
                Text(content.producedBy)
                    .accessibilityIdentifier(AccessibilityID.pasteProvider)
                if let item, !item.unknownLines.isEmpty {
                    dot
                    HStack(spacing: 5) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text(item.unknownLines.count == 1 ? "1 line kept as a note" :
                            "\(item.unknownLines.count) lines kept as notes")
                    }
                }
                if let item, !item.badChords.isEmpty {
                    dot
                    Text(item.badChords.count == 1 ? "1 chord not recognised" :
                        "\(item.badChords.count) chords not recognised")
                        .help(item.badChords.joined(separator: ", "))
                }
                if let note = content.note {
                    dot
                    Text(note.text)
                    if note.opensSettings {
                        Button(
                            AIAvailabilityCopy.openSettingsTitle,
                            action: context
                                .openSystemSettings,
                        )
                        .buttonStyle(.link)
                        .accessibilityIdentifier(AccessibilityID.pasteOpenSystemSettings)
                    }
                }
                if content.showsDownloadLink {
                    dot
                    Button(PasteFooter.downloadLinkTitle, action: context.openAISettings)
                        .buttonStyle(.link)
                        .foregroundStyle(Theme.color.ink)
                        .help("Settings > AI: download the local model (about 2.3 GB)")
                        .accessibilityIdentifier(AccessibilityID.pasteDownloadLink)
                }
            }
            .font(SchibstedGrotesk.medium.font(size: 12.5))
            .foregroundStyle(Theme.color.muted)
            .lineLimit(1)
        }

        private var dot: some View {
            Text("·").accessibilityHidden(true)
        }
    }

    // MARK: - Input state (R83)

    /// New Song: "Paste or type a song". Command-V pastes into the text area (the clipboard
    /// is never read before that); a paste moves straight to review, typed text continues
    /// with Continue. "Start blank" opens an empty song.
    struct PasteInputView: View {
        @Bindable var review: PasteReviewModel
        let context: PasteReviewContext
        @FocusState private var isFocused: Bool

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("New Song")
                        .font(SchibstedGrotesk.extraBold.font(size: 17))
                        .foregroundStyle(Theme.color.ink)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                Rule()
                ZStack {
                    TextEditor(text: $review.draftText)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .padding(10)
                        .accessibilityLabel("Song text")
                        .accessibilityIdentifier(AccessibilityID.pasteInput)
                    if review.draftText.isEmpty {
                        VStack(spacing: 8) {
                            Text("Paste or type a song")
                                .font(SchibstedGrotesk.bold.font(size: 18))
                                .foregroundStyle(Theme.color.ink)
                            Text("Chords over lyrics, a chord-site page or ChordPro. ⌘V pastes.")
                                .font(SchibstedGrotesk.medium.font(size: 13))
                                .foregroundStyle(Theme.color.muted)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            Theme.color.lineStrong,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]),
                        ),
                )
                .padding(16)
                Rule()
                HStack(spacing: 10) {
                    Button("Start blank", action: context.startBlank)
                        .buttonStyle(.link)
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityIdentifier(AccessibilityID.pasteStartBlank)
                    Text("opens the editor with the song card")
                        .font(SchibstedGrotesk.medium.font(size: 12.5))
                        .foregroundStyle(Theme.color.muted)
                    Spacer()
                    Button("Cancel", action: context.cancel)
                        .buttonStyle(.segueSecondary)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier(AccessibilityID.pasteCancel)
                    Button("Continue") { review.submitDraft() }
                        .buttonStyle(.seguePrimary)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(review.draftText
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier(AccessibilityID.pasteContinue)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
            }
            .frame(width: 640, height: 440)
            .onAppear { isFocused = true }
            .onChange(of: review.draftText) { old, new in
                // A paste lands as one multi-line change into an empty area: review it at
                // once. Typing goes on until Continue.
                if old.isEmpty, new.contains("\n") {
                    review.submitDraft()
                }
            }
        }
    }
#endif
