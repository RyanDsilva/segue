#if os(macOS)
    import Editing
    import Library
    import Setlists
    import SwiftUI

    /// Opens a song's card on its Length field from the builder (the Library section is
    /// shown first). The root view supplies it; previews and tests leave it empty.
    struct OpenSongAction {
        var run: (SongID) -> Void = { _ in }

        func callAsFunction(_ song: SongID) {
            run(song)
        }
    }

    extension EnvironmentValues {
        @Entry var openSongForLength = OpenSongAction()
    }

    /// The missing-lengths list (R88): exactly the songs in the set (or in one part) that
    /// have no length, in set order, each with an inline length field (one undoable
    /// `{duration}` edit, P3-5's `LengthField`) and Open Song. It updates as lengths land.
    struct MissingLengthsList: View {
        let setlist: Setlist
        let library: LibraryViewModel
        /// The rows to look at (a part's songs); nil for the whole set.
        var within: Set<SetlistItemID>?
        @Environment(\.openSongForLength) private var openSong

        var body: some View {
            let rows = Self.rows(setlist, within: within, library: library)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rows.count == 1 ? "1 song without a length" :
                        "\(rows.count) songs without a length")
                        .font(SchibstedGrotesk.bold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                    Text("In set order. Type a length (m:ss) or open the song to time it.")
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                if rows.isEmpty {
                    Rule()
                    Text("Every song has a length.")
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                        .padding(16)
                }
                ForEach(rows) { row in
                    Rule()
                    rowView(row)
                }
            }
            .frame(width: 440)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.missingLengths)
        }

        private func rowView(_ row: Row) -> some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(SchibstedGrotesk.semiBold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    Text(row.place)
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LengthField(songID: row.song, length: nil) { seconds in
                    Task { await library.editSongSource(id: row.song, .setLength(seconds)) }
                }
                .frame(width: 170)
                Button("Open Song") { openSong(row.song) }
                    .buttonStyle(.link)
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
                    .help("Show \(row.title) in the Library with its Length field ready")
                    .accessibilityIdentifier(AccessibilityID.missingLengthsOpen)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.title)
            .accessibilityIdentifier(AccessibilityID.missingLengthsRow)
        }

        struct Row: Identifiable, Equatable {
            var id: SetlistItemID
            var song: SongID
            var title: String
            /// "Set 2 · #6".
            var place: String
        }

        /// The song slots of `setlist` (inside `within`) whose song has no `{duration}`, in
        /// set order. A song missing from the library is left out (it has no card).
        static func rows(
            _ setlist: Setlist,
            within: Set<SetlistItemID>?,
            library: LibraryViewModel,
        ) -> [Row] {
            var rows: [Row] = []
            var number = 0
            var part = "Set 1"
            let hasParts = setlist.entries.contains(where: \.isBreak)
            for entry in setlist.entries {
                if let info = entry.breakInfo {
                    part = info.label.isEmpty ? "Break" : info.label
                    continue
                }
                number += 1
                guard within?.contains(entry.itemId) ?? true, let song = entry.songId,
                      let record = library.song(id: song),
                      SetlistTiming.directiveLength(of: record) == nil
                else { continue }
                rows.append(Row(
                    id: entry.itemId,
                    song: song,
                    title: SongSummary.title(record),
                    place: hasParts ? "\(part) · #\(number)" : "#\(number)",
                ))
            }
            return rows
        }
    }
#endif
