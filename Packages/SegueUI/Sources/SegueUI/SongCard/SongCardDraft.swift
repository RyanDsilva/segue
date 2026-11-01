#if os(macOS)
    import ChordPro
    import Library
    import SwiftUI

    /// The song card in draft mode (R80, for P3-4's paste review sheet): the expanded card
    /// plus proficiency and tags, editing an in-memory song. Nothing is written to disk;
    /// the sheet saves `source` and `metadata` when the user accepts.
    public struct SongCardDraft: View {
        @Binding var source: String
        @Binding var metadata: SongMetadata
        let knownArtists: [String]
        let knownAlbums: [String]
        let knownTags: [String]
        /// The converter's splits still standing, each with Keep as one under the artists.
        let artistSplits: [ArtistSplit]
        let keepAsOne: (ArtistSplit) -> Void
        @State private var standIn = SongID.standIn()

        public init(
            source: Binding<String>,
            metadata: Binding<SongMetadata>,
            knownArtists: [String] = [],
            knownAlbums: [String] = [],
            knownTags: [String] = [],
            artistSplits: [ArtistSplit] = [],
            keepAsOne: @escaping (ArtistSplit) -> Void = { _ in },
        ) {
            _source = source
            _metadata = metadata
            self.knownArtists = knownArtists
            self.knownAlbums = knownAlbums
            self.knownTags = knownTags
            self.artistSplits = artistSplits
            self.keepAsOne = keepAsOne
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                SongCardView(
                    host: .draft(
                        source: $source,
                        metadata: $metadata,
                        songID: standIn,
                        knownArtists: knownArtists,
                        knownAlbums: knownAlbums,
                        knownTags: knownTags,
                    ),
                    layout: .expanded,
                    showsHelp: false,
                    artistSplits: artistSplits,
                    keepAsOne: keepAsOne,
                )
                Grid(
                    alignment: .leadingFirstTextBaseline,
                    horizontalSpacing: 14,
                    verticalSpacing: 10,
                ) {
                    GridRow {
                        label("Proficiency")
                        ProficiencyPicker(selection: metadata.proficiency) {
                            metadata.proficiency = $0
                        }
                    }
                    GridRow {
                        label("Tags")
                        TagEditor(tags: metadata.tags, suggestions: knownTags) { metadata.tags = $0
                        }
                    }
                }
            }
        }

        private func label(_ text: String) -> some View {
            Text(text)
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
                .gridColumnAlignment(.leading)
        }
    }
#endif
