#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// R107: "3 songs left out: no length ▾", tinted like the builder's unknown button. It
    /// opens the missing-lengths list for the songs the request matched but the packer left
    /// out (they are not in the set), each with an inline length field and Open Song.
    struct LeftOutButton: View {
        let songs: [SongID]
        let library: LibraryViewModel
        @State private var isOpen = false

        var body: some View {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(Self.title(songs.count))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(SchibstedGrotesk.semiBold.font(size: 12))
                .foregroundStyle(Theme.color.cueText)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Theme.color.cue.opacity(isOpen ? 0.18 : 0.09)))
                .overlay(Capsule().strokeBorder(Theme.color.cue.opacity(0.55), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Songs the request matched that have no length, so they could not be timed")
            .accessibilityIdentifier(AccessibilityID.assistantLeftOut)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                LeftOutLengthsList(songs: songs, library: library)
            }
        }

        /// "1 song left out: no length", "3 songs left out: no length".
        static func title(_ count: Int) -> String {
            count == 1 ? "1 song left out: no length" : "\(count) songs left out: no length"
        }
    }

    /// The left-out songs, by title, each with P3-5's length field and Open Song (P3-12's
    /// missing-lengths list, for songs that are not in the set).
    struct LeftOutLengthsList: View {
        let songs: [SongID]
        let library: LibraryViewModel
        @Environment(\.openSongForLength) private var openSong

        var body: some View {
            let rows = songs.compactMap(library.song(id:))
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LeftOutButton.title(rows.count))
                        .font(SchibstedGrotesk.bold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                    Text("They match the request but have no length. Type one (m:ss), "
                        + "then Rebuild to include them.")
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.id) { record in
                            Rule()
                            row(record)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .frame(width: 500)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.assistantLeftOutList)
        }

        private func row(_ record: SongRecord) -> some View {
            let title = SongSummary.title(record)
            return HStack(spacing: 12) {
                Text(title)
                    .font(SchibstedGrotesk.semiBold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LengthField(songID: record.id, length: nil) { seconds in
                    Task { await library.editSongSource(id: record.id, .setLength(seconds)) }
                }
                .frame(width: 210)
                .environment(\.analyticsContext, .builder)
                Button("Open Song") { openSong(record.id) }
                    .buttonStyle(.link)
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
                    .help("Show \(title) in the Library with its Length field ready")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }
#endif
