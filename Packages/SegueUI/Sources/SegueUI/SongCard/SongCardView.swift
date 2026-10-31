#if os(macOS)
    import ChordPro
    import Editing
    import Library
    import Setlists
    import SwiftUI

    /// The song card (R80, direction 2 "Tokens"): one line of value tokens (Key, Tempo,
    /// Length, Capo, Time); each opens a small popover with its control. Missing set
    /// essentials are dashed tokens with a dot. `.expanded` (Start blank, draft mode) also
    /// shows Title and Artist fields and every token, so nothing hides behind "+".
    struct SongCardView: View {
        enum Layout: Equatable {
            /// The strip alone (library detail pane under the heading, editor under the top bar).
            case strip
            /// Title and Artist fields plus every token (a new song or a draft).
            case expanded
        }

        let host: SongCardHost
        var layout: Layout = .strip
        /// The Help button opening the guide's song card page; off where the surrounding
        /// sheet has its own (the paste review's draft card).
        var showsHelp = true
        var timeIt: TimeItModel = .shared
        var router: SongCardFocusRouter = .shared

        @State private var open: SongCardField?
        @State private var draftTitle = ""
        @State private var draftArtist = ""
        @FocusState private var focus: SongCardField?
        @FocusState private var lengthFocused: Bool

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
                draftArtist = values.artists.first ?? ""
                takeFocusRequest()
            }
            .onChange(of: router.pending) { _, _ in takeFocusRequest() }
            .onChange(of: values.title) { _, new in
                if focus != .title {
                    draftTitle = new
                }
            }
            .onChange(of: values.artists) { _, new in
                if focus != .artist {
                    draftArtist = new.first ?? ""
                }
            }
        }

        // MARK: Title and artist (expanded)

        private func textFields(_ values: SongCardValues) -> some View {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    label("Title")
                    TextField("Title", text: $draftTitle, prompt: Text("Song title"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .focused($focus, equals: .title)
                        .onSubmit { commitTitle(values) }
                        .accessibilityIdentifier(AccessibilityID.songCardTitle)
                }
                GridRow {
                    label("Artist")
                    TextField("Artist", text: $draftArtist, prompt: Text("Artist"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .focused($focus, equals: .artist)
                        .onSubmit { commitArtist(values) }
                        .textInputSuggestions {
                            ForEach(artistCompletions, id: \.self) { artist in
                                Text(artist).textInputCompletion(artist)
                            }
                        }
                        .accessibilityIdentifier(AccessibilityID.songCardArtist)
                }
            }
            .onChange(of: focus) { old, _ in
                if old == .title {
                    commitTitle(values)
                }
                if old == .artist {
                    commitArtist(values)
                }
            }
        }

        private var artistCompletions: [String] {
            let typed = draftArtist.trimmingCharacters(in: .whitespaces).lowercased()
            guard !typed.isEmpty else { return [] }
            return Array(host.knownArtists.filter {
                $0.lowercased().hasPrefix(typed) && $0.lowercased() != typed
            }.prefix(6))
        }

        private func commitTitle(_ values: SongCardValues) {
            guard draftTitle.trimmingCharacters(in: .whitespaces) != values.title else { return }
            host.perform(SongCardWrite.title(draftTitle))
        }

        private func commitArtist(_ values: SongCardValues) {
            let first = draftArtist.trimmingCharacters(in: .whitespaces)
            guard first != (values.artists.first ?? "") else { return }
            host.perform(SongCardWrite.artists([first] + values.artists.dropFirst()))
        }

        private func label(_ text: String) -> some View {
            Text(text)
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
                .gridColumnAlignment(.leading)
        }

        // MARK: Tokens

        private func tokens(_ values: SongCardValues) -> some View {
            FlowLayout(spacing: 7) {
                keyToken(values)
                tempoToken(values)
                lengthToken(values)
                if values.capo > 0 || layout == .expanded || open == .capo {
                    capoToken(values)
                }
                if values.time != nil || layout == .expanded || open == .time {
                    timeToken(values)
                }
                if layout == .strip, values.capo == 0 || values.time == nil {
                    addMenu(values)
                }
            }
        }

        private func keyToken(_ values: SongCardValues) -> some View {
            token(.key, title: values.key, placeholder: "Key", essential: true) {
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
                placeholder: "Tempo",
                essential: true,
            ) {
                TempoEditorView(current: values.tempo) { text in
                    write(SongCardWrite.tempo(text))
                }
            }
        }

        private func lengthToken(_ values: SongCardValues) -> some View {
            let running = timeIt.isTiming(host.songID)
            let title = values.length
                .map { SetlistTiming.format($0) } ?? (running ? "Timing…" : nil)
            return token(.length, title: title, placeholder: "Length", essential: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Length")
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.muted)
                    LengthField(
                        songID: host.songID,
                        length: values.length,
                        timeIt: timeIt,
                        focus: $lengthFocused,
                    ) { seconds in
                        host.perform(.setLength(seconds))
                    }
                    Text("m:ss, or seconds. Used for set timing.")
                        .font(SchibstedGrotesk.medium.font(size: 11))
                        .foregroundStyle(Theme.color.muted)
                }
                .padding(12)
                .frame(width: 250, alignment: .leading)
                .onAppear { lengthFocused = true }
            }
        }

        private func capoToken(_ values: SongCardValues) -> some View {
            token(
                .capo,
                title: values.capo > 0 ? "Capo \(values.capo)" : nil,
                placeholder: "Capo",
                essential: false,
            ) {
                CapoEditorView(capo: values.capo) { capo in
                    host.perform(SongCardWrite.capo(capo))
                }
            }
        }

        private func timeToken(_ values: SongCardValues) -> some View {
            token(.time, title: values.time, placeholder: "Time", essential: false) {
                TimeEditorView(current: values.time) { text in
                    write(SongCardWrite.time(text))
                }
                .frame(minWidth: 230, alignment: .leading)
            }
        }

        /// Adds Capo or Time when the strip hides them (absent values).
        private func addMenu(_ values: SongCardValues) -> some View {
            Menu {
                if values.capo == 0 {
                    Button("Capo") { open = .capo }
                }
                if values.time == nil {
                    Button("Time Signature") { open = .time }
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
            .help("Add a capo or time signature")
            .accessibilityLabel("Add capo or time signature")
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
            case .album, .artist, .title:
                if layout == .expanded {
                    focus = field
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
            .accessibilityLabel(title.map { "\(placeholder): \($0)" } ?? "\(placeholder): not set")
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
