#if os(macOS)
    import ChordPro
    import SwiftUI

    /// The library heading's credits under the title (P8-8 section 3.6, direction A, Ryan's
    /// pick): the artists as "A, B", then Movie / Album with a film mark. Double-click (or
    /// Edit Artists / Edit Movie / Album) turns a line into its field in place: the artist
    /// chips, each commit already written, or the album field. Escape or focus leaving ends
    /// editing. A read-only song shows both lines and edits neither.
    struct SongHeadingCredits: View {
        let artists: [String]
        let album: String?
        let host: SongCardHost
        @State private var editing: SongCardField?
        @State private var focus = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                artistsLine
                albumLine
            }
        }

        // MARK: Artists

        @ViewBuilder private var artistsLine: some View {
            if editing == .artist {
                ArtistChipField(
                    artists: artists,
                    suggestions: host.knownArtists,
                    focusRequest: focus,
                    onEndEditing: { editing = nil },
                    onChange: host.writeArtists,
                )
                .frame(maxWidth: 520, alignment: .leading)
                // The chips' text lines up with the title above.
                .padding(.leading, -6)
                .onAppear { focus += 1 }
            } else if let names = ArtistNames.display(artists) {
                Text(names)
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) { begin(.artist) }
                    .contextMenu { editMenu }
                    .help(host.isReadOnly ? "" : "Double-click to edit the artists")
                    .accessibilityIdentifier(AccessibilityID.songCardArtist)
                    .accessibilityAction(named: "Edit Artists") { begin(.artist) }
            } else if !host.isReadOnly {
                addButton("Add artist", systemImage: nil, field: .artist)
                    .font(Theme.font.body)
                    .accessibilityIdentifier(AccessibilityID.songCardArtist)
            }
        }

        // MARK: Movie / Album

        @ViewBuilder private var albumLine: some View {
            if editing == .album {
                AlbumField(
                    album: album,
                    suggestions: host.knownAlbums,
                    focusRequest: focus,
                    onEndEditing: { editing = nil },
                    onCommit: host.writeAlbum,
                )
                .frame(maxWidth: 360, alignment: .leading)
                .padding(.leading, -8)
                .onAppear { focus += 1 }
            } else if let album {
                Label {
                    Text(album)
                } icon: {
                    Image(systemName: "film")
                        .font(.system(size: 11, weight: .semibold))
                }
                .labelStyle(CreditLabelStyle())
                .font(SchibstedGrotesk.medium.font(size: 13))
                .foregroundStyle(Theme.color.muted)
                .onTapGesture(count: 2) { begin(.album) }
                .contextMenu { editMenu }
                .help(host.isReadOnly ? "" : "Double-click to edit the movie or album")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Movie or album: \(album)")
                .accessibilityIdentifier(AccessibilityID.songCardAlbum)
                .accessibilityAction(named: "Edit Movie / Album") { begin(.album) }
            } else if !host.isReadOnly {
                addButton("Add movie or album", systemImage: "film", field: .album)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .opacity(0.8)
                    .accessibilityIdentifier(AccessibilityID.songCardAlbum)
            }
        }

        // MARK: Editing

        @ViewBuilder private var editMenu: some View {
            Button("Edit Artists") { begin(.artist) }
                .disabled(host.isReadOnly)
            Button("Edit Movie / Album") { begin(.album) }
                .disabled(host.isReadOnly)
        }

        private func addButton(_ title: String, systemImage: String?, field: SongCardField)
            -> some View
        {
            Button {
                begin(field)
            } label: {
                if let systemImage {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .labelStyle(CreditLabelStyle())
                } else {
                    Text(title)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.color.muted)
        }

        private func begin(_ field: SongCardField) {
            guard !host.isReadOnly else { return }
            editing = field
        }
    }

    /// A credit line's mark and text, tight and baseline-aligned.
    private struct CreditLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                configuration.icon
                configuration.title
            }
        }
    }
#endif
