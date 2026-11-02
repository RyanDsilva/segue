#if os(macOS)
    import Library
    import SwiftUI

    // P8-8 section 3.6: the song card's credit editors, in the strip's Artists and
    // Movie / Album popovers. Each change is one edit through the host (one undo step).

    extension SongCardHost {
        /// One chip field change: one edit and its feature key (Split counts apart).
        func writeArtists(_ change: ArtistChipChange) {
            perform(SongCardWrite.artists(change.artists))
            recordFeature?(change.edit == .split ? .artistSplit : .songArtists)
        }

        /// A committed Movie / Album (blank clears).
        func writeAlbum(_ album: String) {
            perform(SongCardWrite.album(album))
            recordFeature?(.songAlbum)
        }
    }

    /// The Artists popover: the chip field with the library's names, focused on open.
    struct ArtistsEditor: View {
        let host: SongCardHost
        let artists: [String]
        @State private var focus = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Artists", bundle: #bundle)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                ArtistChipField(
                    artists: artists,
                    suggestions: host.knownArtists,
                    focusRequest: focus,
                    undoManager: host.undoManager,
                    onChange: host.writeArtists,
                )
                Text("Return or comma adds an artist. Drag to reorder.", bundle: #bundle)
                    .font(SchibstedGrotesk.medium.font(size: 11))
                    .foregroundStyle(Theme.color.muted)
            }
            .padding(12)
            .frame(width: 320, alignment: .leading)
            .onAppear { focus += 1 }
        }
    }

    /// The Movie / Album popover, focused on open; Return or Escape closes it.
    struct AlbumEditor: View {
        let host: SongCardHost
        let album: String?
        let onDone: () -> Void
        @State private var focus = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Movie / Album", bundle: #bundle)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                AlbumField(
                    album: album,
                    suggestions: host.knownAlbums,
                    focusRequest: focus,
                    onEndEditing: onDone,
                    undoManager: host.undoManager,
                    onCommit: host.writeAlbum,
                )
            }
            .padding(12)
            .frame(width: 280, alignment: .leading)
            .onAppear { focus += 1 }
        }
    }
#endif
