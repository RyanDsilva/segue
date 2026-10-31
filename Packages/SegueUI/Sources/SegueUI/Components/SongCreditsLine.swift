#if os(macOS)
    import ChordPro
    import SwiftUI

    /// A song's credits on one muted line (P8-8 section 4.2): "A, B · Kalank", then an
    /// optional trailing note ("  ·  12 plays"). When the line is too narrow, Movie / Album
    /// truncates first, then the artists; the trailing note keeps its room. Shows nothing
    /// when there is nothing to say. The caller sets font and colour.
    struct SongCreditsLine: View {
        let artists: [String]
        let album: String?
        var trailing: String?

        var body: some View {
            let names = ArtistNames.display(artists)
            if names != nil || album != nil || trailing != nil {
                HStack(spacing: 0) {
                    if let names {
                        Text(names)
                            .layoutPriority(2)
                    }
                    if let album {
                        Text(names == nil ? album : " · \(album)")
                            .layoutPriority(1)
                    }
                    if let trailing {
                        Text(names == nil && album == nil ? trailing : "  ·  \(trailing)")
                            .layoutPriority(3)
                    }
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
    }
#endif
