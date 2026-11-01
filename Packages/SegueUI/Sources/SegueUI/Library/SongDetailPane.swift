#if os(macOS)
    import Editing
    import Library
    import Setlists
    import SwiftUI

    /// The library preview pane (layout a): title, artists and Movie / Album (each
    /// double-click to edit in place) with Edit, the song card's token strip (R80), the song's
    /// metadata
    /// (proficiency, tags, play history, notes and cues), then the chart as its display
    /// toggles render it.
    struct SongDetailPane: View {
        let model: LibraryViewModel
        let session: LibrarySession
        let record: SongRecord
        @State private var editingHeading: SongCardField?
        @State private var headingDraft = ""
        @FocusState private var headingFocused: Bool

        var body: some View {
            let render = SongSummary.renderModel(
                record,
                userShapes: model.userShapes,
                bass: model.instrument?.bassView,
            )
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(render)
                        if let reason = record.readOnly {
                            notice(UserMessage.readOnlyText(reason), systemImage: "lock.fill")
                        }
                        if record.hasDerivedID {
                            notice(
                                "Segue could not read this song's ID from its metadata file, so "
                                    + "setlists lose track of it if the file is renamed.",
                                systemImage: "link.badge.plus",
                            )
                        }
                        SongCardView(host: cardHost)
                            .id(record.id)
                        SongMetadataSection(model: model, record: record)
                        Rule()
                        chart(render)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .followsPlayAlong(model.playAlong?.cue, proxy: proxy)
            }
            .background(Theme.color.ground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let playAlong = model.playAlong, playAlong.isOpen {
                    PlayAlongBar(model: playAlong)
                }
            }
            // The bar follows the song shown; another song stops it.
            .onChange(of: render, initial: true) { feedPlayAlong(render) }
            .modifier(LibraryFills(model: model, record: record, render: render))
            .onChange(of: model.playAlong?.isOpen) { feedPlayAlong(render) }
            // A timing write changes the sidecar only, not the rendered chart.
            .onChange(of: record.sidecar.bass) { feedPlayAlong(render) }
            .onDisappear { model.playAlong?.stop() }
        }

        private func feedPlayAlong(_ render: RenderModel) {
            guard let playAlong = model.playAlong else { return }
            if playAlong.isOpen || model.playAlongSong != record.id {
                model.showPlayAlong(record, render: render)
            }
        }

        /// The narrowest the title gets beside the buttons: a 30pt word or two.
        private static let titleMinWidth: CGFloat = 220

        /// Title and buttons on one line while the title keeps `titleMinWidth`: all four
        /// buttons, else "…" and Edit (Rehearse and Live are in "…", and on the selected
        /// list row). Narrower still, the buttons go under the credits.
        private func header(_ render: RenderModel) -> some View {
            ViewThatFits(in: .horizontal) {
                headerRow(render, sessionButtons: true)
                headerRow(render, sessionButtons: false)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        titleView(render)
                        credits
                    }
                    ViewThatFits(in: .horizontal) {
                        headerButtons(sessionButtons: true)
                        headerButtons(sessionButtons: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private func headerRow(_ render: RenderModel, sessionButtons: Bool) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    // Ideal width is the minimum, so ViewThatFits measures the row at the
                    // narrowest title it allows; laid out, the title takes the rest.
                    titleView(render)
                        .frame(
                            minWidth: Self.titleMinWidth,
                            idealWidth: Self.titleMinWidth,
                            maxWidth: .infinity,
                            alignment: .leading,
                        )
                    headerButtons(sessionButtons: sessionButtons)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                }
                credits
            }
        }

        private func headerButtons(sessionButtons: Bool) -> some View {
            HStack(spacing: 8) {
                moreMenu
                if sessionButtons {
                    SongSessionButtons(songID: record.id)
                }
                Button("Edit") { model.beginEditing(record) }
                    .buttonStyle(.segueSecondary)
                    .help(record.isReadOnly ? "This song is read-only" : "Edit ChordPro")
                    .disabled(record.isReadOnly)
                    .accessibilityIdentifier(AccessibilityID.editSong)
            }
            .controlSize(.large)
            .fixedSize()
        }

        // MARK: Title, edited in place

        @ViewBuilder private func titleView(_ render: RenderModel) -> some View {
            let font = SchibstedGrotesk.extraBold.font(size: 30)
            if editingHeading == .title {
                headingField("Title", font: font, identifier: AccessibilityID.songCardTitle)
            } else {
                Text(title(render))
                    .font(font)
                    .tracking(Theme.tracking.title * 30)
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) { beginHeadingEdit(.title, render: render) }
                    .contextMenu {
                        Button("Edit Title") { beginHeadingEdit(.title, render: render) }
                            .disabled(record.isReadOnly)
                    }
                    .help(record.isReadOnly ? "" : "Double-click to edit the title")
                    .accessibilityIdentifier(AccessibilityID.songTitle)
                    .accessibilityAction(named: "Edit Title") {
                        beginHeadingEdit(.title, render: render)
                    }
            }
        }

        /// Artists and Movie / Album under the title, each edited in place (P8-8, direction
        /// A).
        private var credits: some View {
            SongHeadingCredits(
                artists: record.document.metadata.artists,
                album: record.document.metadata.album,
                host: cardHost,
            )
            .id(record.id)
        }

        private func headingField(_ name: String, font: Font, identifier: String) -> some View {
            TextField(name, text: $headingDraft, prompt: Text(name))
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(Theme.color.ink)
                .focused($headingFocused)
                .onSubmit(commitHeading)
                .onExitCommand { editingHeading = nil }
                .onChange(of: headingFocused) { _, focused in
                    if !focused {
                        commitHeading()
                    }
                }
                .accessibilityLabel(name)
                .accessibilityIdentifier(identifier)
        }

        private func beginHeadingEdit(_ field: SongCardField, render: RenderModel) {
            beginHeadingEdit(field, current: record.document.metadata.title ?? title(render))
        }

        private func beginHeadingEdit(_ field: SongCardField, current: String) {
            guard !record.isReadOnly else { return }
            headingDraft = current
            editingHeading = field
            headingFocused = true
        }

        private func commitHeading() {
            guard let field = editingHeading else { return }
            editingHeading = nil
            let metadata = record.document.metadata
            let operation: EditOperation? = switch field {
            case .title
                where headingDraft.trimmingCharacters(in: .whitespaces) != (metadata.title ?? ""):
                SongCardWrite.title(headingDraft)
            default:
                nil
            }
            if let operation {
                cardHost.perform(operation)
            }
        }

        private var cardHost: SongCardHost {
            let id = record.id
            let model = model
            return SongCardHost(
                document: record.document,
                songID: id,
                isReadOnly: record.isReadOnly,
                metadata: SongMetadata(record.sidecar),
                knownArtists: model.knownArtists,
                knownAlbums: model.knownAlbums,
                knownTags: model.tagNames,
                perform: { operation in
                    Task { await model.editSongSource(id: id, operation) }
                },
                editMetadata: { change in
                    Task { await model.editMetadata(id: id, change) }
                },
                recordFeature: { model.services.record(.featureUsed($0, .library)) },
            )
        }

        /// "…": Add to Setlist ▸, Show in Finder, Move to Trash.
        private var moreMenu: some View {
            Menu {
                SongActions(session: session, songID: record.id)
            } label: {
                // The glyph alone is shorter than a line of text: give it the label height
                // of the text buttons beside it so the two line up.
                Image(systemName: "ellipsis")
                    .frame(minWidth: 18, minHeight: 20)
                    .accessibilityLabel("More")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.segueSecondary)
            .fixedSize()
            .help("Add to a setlist, show in Finder or move to the Trash")
            .accessibilityIdentifier(AccessibilityID.songMoreMenu)
        }

        private func chart(_ render: RenderModel) -> some View {
            VStack(alignment: .leading, spacing: 20) {
                if let playAlong = model.playAlong, !render.sections.isEmpty {
                    // Play along with this chart (P8-6 10.3); the bar opens at the bottom.
                    PlayAlongToggle(model: playAlong)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.bottom, -12)
                }
                if render.sections.isEmpty {
                    Text("No lyrics yet.")
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                } else {
                    SongSheetView(sections: render.sections, style: .preview)
                        // A walk-up run opens the picker (P8-4b 8.9); no undo here.
                        .environment(\.walkUpPicking, model.walkUpPicking(songID: record.id))
                        .environment(\.chordHearing, model.chordHearing(render))
                        .environment(\.walkUpAudition, model.walkUpAudition(render))
                        .environment(\.playAlongCue, model.playAlong?.cue)
                        .environment(\.chordSpan, model.chordSpanActions(record, render: render))
                        .background(SpanEscape(selection: model.spanSelection))
                }
                if !render.diagrams.isEmpty {
                    StripSnapshot(
                        diagrams: render.diagrams,
                        instrument: render.transform.options.instrument,
                        tuning: render.tuning,
                    )
                    .equatable()
                    .padding(.top, 8)
                }
            }
            .textSelection(.enabled)
        }

        private func title(_ render: RenderModel) -> String {
            let title = render.header.title?.trimmingCharacters(in: .whitespaces) ?? ""
            return title.isEmpty ? SongSummary.title(record) : title
        }

        private func notice(_ text: String, systemImage: String) -> some View {
            Label(text, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(Theme.color.muted)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.color.surfaceAlt, in: RoundedRectangle(cornerRadius: 8))
        }
    }
#endif
