#if os(macOS)
    import Editing
    import Library
    import Setlists
    import SwiftUI

    /// The library preview pane (layout a): title, artist and performance line with Edit,
    /// the song's metadata (proficiency, tags, play history, notes and cues), then the
    /// chart as its display toggles render it.
    struct SongDetailPane: View {
        let model: LibraryViewModel
        let session: LibrarySession
        let record: SongRecord

        var body: some View {
            let render = SongSummary.renderModel(record, userShapes: model.userShapes)
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
                    Text(title(render))
                        .font(SchibstedGrotesk.extraBold.font(size: 30))
                        .tracking(Theme.tracking.title * 30)
                        .foregroundStyle(Theme.color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(AccessibilityID.songTitle)
                    HStack(spacing: 8) {
                        moreMenu
                        Button("Edit") { model.beginEditing(record) }
                            .buttonStyle(.segueSecondary)
                            .help(record.isReadOnly ? "This song is read-only" : "Edit ChordPro")
                            .disabled(record.isReadOnly)
                            .accessibilityIdentifier(AccessibilityID.editSong)
                    }
                    .controlSize(.large)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                }
                let subtitle = subtitle(render)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(AccessibilityID.sheetKey)
                }
            }
        }

        /// "…": Add to Setlist ▸, Show in Finder, Move to Trash.
        private var moreMenu: some View {
            Menu {
                SongActions(session: session, songID: record.id)
            } label: {
                Image(systemName: "ellipsis")
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

        /// "The Lanterns  ·  G, capo 2, 96  ·  3:40" (the length only when known).
        private func subtitle(_ render: RenderModel) -> String {
            let length = record.document.metadata.duration.map { SetlistTiming.format($0) }
            return [SongSummary.subtitle(render), length]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: "  ·  ")
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
