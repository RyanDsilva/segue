#if os(macOS)
    import ChordPro
    import SwiftUI

    /// A song's credits on one muted line (P8-8 section 4.2): "A, B · Kalank", then an
    /// optional trailing note ("  ·  12 plays"). When the line is too narrow, Movie / Album
    /// is dropped first, then the artists truncate. Shows nothing when there is nothing to
    /// say. The caller sets font and colour.
    struct SongCreditsLine: View {
        let artists: [String]
        let album: String?
        var trailing: String?

        var body: some View {
            let names = ArtistNames.display(artists)
            let full = Self.join([names, album].compactMap(\.self), " · ")
            if full != nil || trailing != nil {
                // The whole line when it fits; else without Movie / Album (never a dangling
                // separator); else the artists truncated at the end.
                ViewThatFits(in: .horizontal) {
                    line(full)
                    if album != nil, names != nil {
                        line(names)
                    }
                    line(names ?? full)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.join([full, trailing].compactMap(\.self), ", ") ?? "")
            }
        }

        private func line(_ credits: String?) -> some View {
            Text(Self.join([credits, trailing].compactMap(\.self), "  ·  ") ?? "")
                .lineLimit(1)
        }

        private static func join(_ parts: [String], _ separator: String) -> String? {
            parts.isEmpty ? nil : parts.joined(separator: separator)
        }
    }
#endif
