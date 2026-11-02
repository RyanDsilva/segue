#if os(macOS)
    import ChordPro
    import Editing
    import Library
    import Setlists
    import SwiftUI

    /// The song card (R80, direction 2 "Tokens"): one line of value tokens (Key, Tempo,
    /// Capo, Time); each opens a small popover with its control. Missing set
    /// essentials are dashed tokens with a dot. `.expanded` (Start blank, draft mode) also
    /// shows Title, Artists and Movie / Album and every token, so nothing hides behind "+".
    struct SongCardView: View {
        enum Layout: Equatable {
            /// The strip alone (library detail pane under the heading, editor under the top bar).
            case strip
            /// Title, Artists and Movie / Album plus every token (a new song or a draft).
            case expanded
        }

        let host: SongCardHost
        var layout: Layout = .strip
        /// The Help button opening the guide's song card page; off where the surrounding
        /// sheet has its own (the paste review's draft card).
        var showsHelp = true
        /// Artists and Movie / Album as the strip's first two tokens, each opening its field
        /// in a popover (P8-8 section 3.6: the editor's strip).
        var showsCreditTokens = false
        /// Draft mode (the review sheet): the converter's splits under the Artists field,
        /// each with Keep as one (P8-8 section 3.7).
        var artistSplits: [ArtistSplit] = []
        var keepAsOne: (ArtistSplit) -> Void = { _ in }
        var router: SongCardFocusRouter = .shared

        @State private var open: SongCardField?
        @State private var draftTitle = ""
        /// Bumped to put the caret in the expanded card's Artists or Movie / Album field.
        @State private var artistsFocus = 0
        @State private var albumFocus = 0
        @FocusState private var focus: SongCardField?

        var body: some View {
            let values = host.values
            VStack(alignment: .leading, spacing: 12) {
                if layout == .expanded {
                    textFields(values)
                        .disabled(host.isReadOnly)
                }
                HStack(alignment: .top, spacing: 8) {
                    tokens(values)
                        .disabled(host.isReadOnly)
                    if showsHelp {
                        Spacer(minLength: 0)
                        // A read-only song still has help.
                        GuideHelpButton(.songCard)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.songCard)
            .onAppear {
                draftTitle = values.title
                takeFocusRequest()
            }
            .onChange(of: router.pending) { _, _ in takeFocusRequest() }
            .onChange(of: values.title) { _, new in
                if focus != .title {
                    draftTitle = new
                }
            }
        }

        // MARK: Title, artists and Movie / Album (expanded; P8-8 direction A)

        private func textFields(_ values: SongCardValues) -> some View {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    label("Title")
                    titleField(values)
                }
                GridRow {
                    label("Artists")
                    VStack(alignment: .leading, spacing: 5) {
                        ArtistChipField(
                            artists: values.artists,
                            suggestions: host.knownArtists,
                            focusRequest: artistsFocus,
                            onChange: host.writeArtists,
                        )
                        ForEach(artistSplits, id: \.original) { split in
                            ArtistSplitLine(split: split) { keepAsOne(split) }
                        }
                    }
                    .frame(maxWidth: 320, alignment: .leading)
                }
                GridRow {
                    label("Movie / Album")
                    AlbumField(
                        album: values.album,
                        suggestions: host.knownAlbums,
                        focusRequest: albumFocus,
                        onCommit: host.writeAlbum,
                    )
                    .frame(maxWidth: 320, alignment: .leading)
                }
            }
            .onChange(of: focus) { old, _ in
                if old == .title {
                    commitTitle(values)
                }
            }
        }

        /// The title, in the same box as the Artists and Movie / Album fields.
        private func titleField(_ values: SongCardValues) -> some View {
            TextField(
                uiString("Title"),
                text: $draftTitle,
                prompt: Text("Song title", bundle: #bundle),
            )
            .textFieldStyle(.plain)
            .font(Font(ArtistChipField.inputFont))
            // The same box as the Artists and Movie / Album fields: 18 + 5 + 5.
            .frame(height: 18)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        focus == .title ? Theme.color.cue : Theme.color.controlBorder,
                        lineWidth: 1,
                    )
            }
            .frame(maxWidth: 320)
            .focused($focus, equals: .title)
            .onSubmit { commitTitle(values) }
            .accessibilityIdentifier(AccessibilityID.songCardTitle)
        }

        private func commitTitle(_ values: SongCardValues) {
            guard draftTitle.trimmingCharacters(in: .whitespaces) != values.title else { return }
            host.perform(SongCardWrite.title(draftTitle))
        }

        private func label(_ text: String) -> some View {
            Text(text)
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
                .gridColumnAlignment(.leading)
        }

        // MARK: Tokens

        private func tokens(_ values: SongCardValues) -> some View {
            // "+" never sits alone on a line (the library pane at the smallest window).
            FlowLayout(spacing: 7, keepsLastWithPrevious: showsAddMenu(values)) {
                if showsCreditTokens {
                    artistsToken(values)
                    albumToken(values)
                }
                keyToken(values)
                tempoToken(values)
                if values.capo > 0 || layout == .expanded || open == .capo {
                    capoToken(values)
                }
                if values.time != nil || layout == .expanded || open == .time {
                    timeToken(values)
                }
                if showsAddMenu(values) {
                    addMenu(values)
                }
            }
        }

        // MARK: Credits (P8-8)

        /// "Arijit Singh +1": the first artist and how many more; the popover holds the chips.
        private func artistsToken(_ values: SongCardValues) -> some View {
            token(
                .artist,
                title: Self.artistsTitle(values.artists),
                placeholder: uiString("Artists"),
                essential: false,
            ) {
                ArtistsEditor(host: host, artists: values.artists)
            }
        }

        private func albumToken(_ values: SongCardValues) -> some View {
            token(
                .album,
                title: values.album,
                placeholder: uiString("Movie / Album"),
                essential: false,
            ) {
                AlbumEditor(host: host, album: values.album) { open = nil }
            }
        }

        static func artistsTitle(_ artists: [String]) -> String? {
            guard let first = artists.first else { return nil }
            return artists.count == 1 ? first : "\(first) +\(artists.count - 1)"
        }

        private func keyToken(_ values: SongCardValues) -> some View {
            token(.key, title: values.key, placeholder: uiString("Key"), essential: true) {
                KeyPickerView(
                    current: values.key,
                    detected: values.detectedKey,
                    capo: values.capo,
                ) { key in
                    host.perform(SongCardWrite.key(key))
                    open = nil
                }
            }
        }

        private func tempoToken(_ values: SongCardValues) -> some View {
            token(
                .tempo,
                title: values.tempoText.map { "\($0) BPM" },
                placeholder: uiString("Tempo"),
                essential: true,
            ) {
                TempoEditorView(current: values.tempo) { text in
                    write(SongCardWrite.tempo(text))
                }
            }
        }

        private func capoToken(_ values: SongCardValues) -> some View {
            token(
                .capo,
                title: values.capo > 0 ? "Capo \(values.capo)" : nil,
                placeholder: uiString("Capo"),
                essential: false,
            ) {
                CapoEditorView(capo: values.capo) { capo in
                    host.perform(SongCardWrite.capo(capo))
                }
            }
        }

        private func timeToken(_ values: SongCardValues) -> some View {
            token(.time, title: values.time, placeholder: uiString("Time"), essential: false) {
                TimeEditorView(current: values.time) { text in
                    write(SongCardWrite.time(text))
                }
                .frame(minWidth: 230, alignment: .leading)
            }
        }

        private func showsAddMenu(_ values: SongCardValues) -> Bool {
            layout == .strip && (values.capo == 0 || values.time == nil)
        }

        /// Adds Capo or Time when the strip hides them (absent values).
        private func addMenu(_ values: SongCardValues) -> some View {
            Menu {
                if values.capo == 0 {
                    Button(uiString("Capo")) { open = .capo }
                }
                if values.time == nil {
                    Button(uiString("Time Signature")) { open = .time }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help(uiString("Add a capo or time signature"))
            .accessibilityLabel(uiString("Add capo or time signature"))
            .accessibilityIdentifier(AccessibilityID.songCardAdd)
        }

        /// Writes a validated value: closes the popover, or returns the problem to show.
        private func write(_ result: Result<EditOperation, SongCardWrite.Problem>) -> String? {
            switch result {
            case let .success(operation):
                host.perform(operation)
                open = nil
                return nil
            case let .failure(problem):
                return problem.message
            }
        }

        private func token(
            _ field: SongCardField,
            title: String?,
            placeholder: String,
            essential: Bool,
            @ViewBuilder editor: @escaping () -> some View,
        ) -> some View {
            let isOpen = Binding(
                get: { open == field },
                set: { open = $0 ? field : (open == field ? nil : open) },
            )
            return SongCardToken(
                title: title,
                placeholder: placeholder,
                isMissingEssential: essential && title == nil,
                isActive: open == field,
            ) {
                open = open == field ? nil : field
            }
            .focused($focus, equals: field)
            .popover(isPresented: isOpen, arrowEdge: .bottom) {
                editor()
            }
            .accessibilityIdentifier(AccessibilityID.songCardToken(field))
        }

        private func takeFocusRequest() {
            guard let field = router.take(for: host.songID) else { return }
            switch field {
            case .title:
                if layout == .expanded {
                    focus = field
                }
            case .artist:
                if layout == .expanded {
                    artistsFocus += 1
                }
            case .album:
                if layout == .expanded {
                    albumFocus += 1
                }
            default:
                open = field
            }
        }
    }

    /// One token: a filled pill with its value, or, for a missing set essential, a dashed
    /// ghost with the essentials dot.
    struct SongCardToken: View {
        let title: String?
        let placeholder: String
        let isMissingEssential: Bool
        let isActive: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    if isMissingEssential {
                        EssentialsDot()
                    }
                    Text(title ?? placeholder)
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .foregroundStyle(title == nil ? Theme.color.muted : Theme.color.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(title == nil ? Color.clear : Theme.color.surfaceAlt),
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isActive ? Theme.color.cue : Theme.color.controlBorder,
                            style: StrokeStyle(
                                lineWidth: 1,
                                dash: title == nil && !isActive ? [3, 2] : [],
                            ),
                        )
                        .opacity(title == nil || isActive ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isMissingEssential ? SetEssential.help : "Change the \(placeholder.lowercased())")
            .accessibilityLabel(title
                .map { "\(placeholder): \($0)" } ?? uiString("\(placeholder): not set"))
            .accessibilityHint(isMissingEssential ? SetEssential.help : "")
        }
    }

    /// The quiet set-essentials dot (R80, R110): on the card's missing tokens, library rows
    /// and the builder's library column.
    struct EssentialsDot: View {
        var body: some View {
            Circle()
                .fill(Theme.color.indicatorOff)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }
#endif
