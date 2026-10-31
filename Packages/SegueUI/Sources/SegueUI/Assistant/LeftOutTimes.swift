#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// "2 songs left out: no tempo ▾" (P8-8 section 5.4), tinted like the builder's unknown
    /// button. It opens the list of the songs the request matched but the packer left out
    /// under a length target because they have no time (they are not in the set), each with
    /// the no-time list's row: a Tempo field when the song has no tempo, and Open Song.
    struct LeftOutButton: View {
        let songs: [SongID]
        let library: LibraryViewModel
        @State private var isOpen = false

        var body: some View {
            let title = Self.title(songs.count, reasons: reasons)
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(title)
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
            .help("Songs the request matched that have no time, so they could not be packed")
            .accessibilityIdentifier(AccessibilityID.assistantLeftOut)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                LeftOutTimesList(songs: songs, library: library, title: title)
            }
        }

        private var reasons: Set<UnknownTime> {
            Set(songs
                .compactMap { library.song(id: $0).flatMap { library.times.song($0).unknown } })
        }

        /// "1 song left out: no tempo", "3 songs left out: no time" (reasons differ).
        static func title(_ count: Int, reasons: Set<UnknownTime>) -> String {
            let reason = reasons == [.noTempo] ? "no tempo"
                : reasons == [.noChords] ? "no chords" : "no time"
            return count == 1 ? "1 song left out: \(reason)" : "\(count) songs left out: \(reason)"
        }
    }

    /// The left-out songs, by title, each with an inline Tempo field (no tempo) and Open Song.
    struct LeftOutTimesList: View {
        let songs: [SongID]
        let library: LibraryViewModel
        let title: String
        @Environment(\.openSong) private var openSong

        var body: some View {
            let rows = songs.compactMap(library.song(id:))
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SchibstedGrotesk.bold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                    Text("They match the request but have no time. Type or tap a tempo, "
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
            let reason = library.times.song(record).unknown
            return HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SchibstedGrotesk.semiBold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    if reason == .noChords {
                        Text("No chords to time")
                            .font(SchibstedGrotesk.medium.font(size: 12))
                            .foregroundStyle(Theme.color.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if reason == .noTempo {
                    InlineTempoField { text in
                        MissingTimesList.writeTempo(text, song: record.id, library: library)
                    }
                }
                Button("Open Song") { openSong(record.id) }
                    .buttonStyle(.link)
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
                    .help("Show \(title) in the Library")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }
#endif
