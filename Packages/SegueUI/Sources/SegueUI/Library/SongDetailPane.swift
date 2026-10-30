#if os(macOS)
    import Editing
    import Library
    import Setlists
    import SwiftUI

    /// The library preview pane (layout a): title and artist (double-click to edit in
    /// place) with Edit, the song card's token strip (R80), the song's metadata
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
            .background(Theme.color.ground)
        }

        private func header(_ render: RenderModel) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    titleView(render)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        moreMenu
                        SongSessionButtons(songID: record.id)
                        Button("Edit") { model.beginEditing(record) }
                            .buttonStyle(.segueSecondary)
                            .help(record.isReadOnly ? "This song is read-only" : "Edit ChordPro")
                            .disabled(record.isReadOnly)
                            .accessibilityIdentifier(AccessibilityID.editSong)
                    }
                    .controlSize(.large)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                }
                artistView
            }
        }

        // MARK: Title and artist, edited in place

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

        @ViewBuilder private var artistView: some View {
            let artist = record.document.metadata.artists.first ?? ""
            if editingHeading == .artist {
                headingField(
                    "Artist",
                    font: Theme.font.body,
                    identifier: AccessibilityID.songCardArtist,
                )
                .textInputSuggestions {
                    ForEach(artistCompletions, id: \.self) { name in
                        Text(name).textInputCompletion(name)
                    }
                }
            } else if artist.isEmpty {
                Button("Add artist") { beginHeadingEdit(.artist, current: "") }
                    .buttonStyle(.plain)
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .disabled(record.isReadOnly)
                    .accessibilityIdentifier(AccessibilityID.songCardArtist)
            } else {
                Text(artist)
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .onTapGesture(count: 2) { beginHeadingEdit(.artist, current: artist) }
                    .contextMenu {
                        Button("Edit Artist") { beginHeadingEdit(.artist, current: artist) }
                            .disabled(record.isReadOnly)
                    }
                    .help(record.isReadOnly ? "" : "Double-click to edit the artist")
                    .accessibilityIdentifier(AccessibilityID.sheetKey)
                    .accessibilityAction(named: "Edit Artist") {
                        beginHeadingEdit(.artist, current: artist)
                    }
            }
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

        private var artistCompletions: [String] {
            let typed = headingDraft.trimmingCharacters(in: .whitespaces).lowercased()
            guard !typed.isEmpty else { return [] }
            return Array(model.knownArtists.filter {
                $0.lowercased().hasPrefix(typed) && $0.lowercased() != typed
            }.prefix(6))
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
            case .artist where headingDraft.trimmingCharacters(in: .whitespaces)
                != (metadata.artists.first ?? ""):
                SongCardWrite.artist(headingDraft)
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
                knownTags: model.tagNames,
                perform: { operation in
                    Task { await model.editSongSource(id: id, operation) }
                },
                editMetadata: { change in
                    Task { await model.editMetadata(id: id, change) }
                },
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
                if render.sections.isEmpty {
                    Text("No lyrics yet.")
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                } else {
                    SongSheetView(sections: render.sections, style: .preview)
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
