#if os(macOS)
    import Editing
    import Library
    import QuartzCore
    import Setlists
    import SwiftUI

    /// Opens a song's card from the builder (the Library section is shown first). The root
    /// view supplies it; previews and tests leave it empty.
    struct OpenSongAction {
        var run: (SongID) -> Void = { _ in }

        func callAsFunction(_ song: SongID) {
            run(song)
        }
    }

    /// An arranged slot's actions from the builder (P3-16): open its Arrange Sections sheet.
    /// The builder supplies them.
    struct SlotArrangementActions {
        var open: (SetlistItemID) -> Void = { _ in }
    }

    extension EnvironmentValues {
        @Entry var openSong = OpenSongAction()
        @Entry var slotArrangementActions = SlotArrangementActions()
    }

    /// The no-time list (P8-8 section 5.5): exactly the song slots in the set (or in one part)
    /// whose time is unknown, in set order. A song with no tempo gets an inline Tempo field
    /// (typed or tapped; Return writes the song's `{tempo}`, one undo step) and Open Song; a
    /// song with no chords says so and offers Open Song. It updates as tempos land.
    struct MissingTimesList: View {
        let setlist: Setlist
        let library: LibraryViewModel
        /// The rows to look at (a part's songs); nil for the whole set.
        var within: Set<SetlistItemID>?
        @Environment(\.openSong) private var openSong

        var body: some View {
            let rows = Self.rows(setlist, within: within, library: library)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rows.count == 1 ? "1 song with no time" :
                        "\(rows.count) songs with no time")
                        .font(SchibstedGrotesk.bold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("In set order. Type or tap a tempo, and the time comes from the bars.")
                            .font(SchibstedGrotesk.medium.font(size: 12))
                            .foregroundStyle(Theme.color.muted)
                        GuideHelpButton(.unknownTimes)
                            .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                if rows.isEmpty {
                    Rule()
                    Text("Every song has a time.")
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                        .padding(16)
                }
                ForEach(rows) { row in
                    Rule()
                    rowView(row)
                }
            }
            .frame(width: 500)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.missingTimes)
        }

        private func rowView(_ row: Row) -> some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(SchibstedGrotesk.semiBold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    Text(row.reason == .noChords ? "\(row.place) · No chords to time" : row.place)
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if row.reason == .noTempo {
                    InlineTempoField { text in
                        Self.writeTempo(text, song: row.song, library: library)
                    }
                }
                Button("Open Song") { openSong(row.song) }
                    .buttonStyle(.link)
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
                    .help("Show \(row.title) in the Library")
                    .accessibilityIdentifier(AccessibilityID.missingTimesOpen)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.title)
            .accessibilityIdentifier(AccessibilityID.missingTimesRow)
        }

        /// Writes `text` as the song's `{tempo}` (one undo step in the library's undo); the
        /// problem message when it is not a tempo.
        @MainActor
        static func writeTempo(
            _ text: String,
            song: SongID,
            library: LibraryViewModel,
        ) -> String? {
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "Enter beats per minute, like 96"
            }
            switch SongCardWrite.tempo(text) {
            case let .failure(problem):
                return problem.message
            case let .success(operation):
                Task {
                    await library.editSongSource(id: song, operation)
                    library.services.record(.featureUsed(.tempoFromSet, .builder))
                }
                return nil
            }
        }

        struct Row: Identifiable, Equatable {
            var id: SetlistItemID
            var song: SongID
            var title: String
            /// "Set 2 · #6".
            var place: String
            var reason: UnknownTime
        }

        /// The song slots of `setlist` (inside `within`) with an unknown time, in set order.
        /// A song missing from the library is left out (it has no card).
        @MainActor
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
                      let reason = library.times.slot(record, arrangement: entry.arrangement)
                          .unknown
                else { continue }
                rows.append(Row(
                    id: entry.itemId,
                    song: song,
                    title: SongSummary.title(record),
                    place: hasParts ? "\(part) · #\(number)" : "#\(number)",
                    reason: reason,
                ))
            }
            return rows
        }
    }

    /// A compact Tempo field with Tap (the song card's tempo parsing and `TapTempo`): Return
    /// commits. `onCommit` returns a problem to show, or nil once written.
    struct InlineTempoField: View {
        let onCommit: (String) -> String?
        @State private var text = ""
        @State private var problem: String?
        @State private var taps = TapTempo()

        var body: some View {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    TextField("Tempo", text: $text, prompt: Text("BPM"))
                        .textFieldStyle(.roundedBorder)
                        .font(SchibstedGrotesk.medium.font(size: 13).monospacedDigit())
                        .frame(width: 64)
                        .onSubmit(commit)
                        .accessibilityLabel("Tempo in beats per minute")
                        .accessibilityIdentifier(AccessibilityID.missingTimesTempo)
                    Text("BPM")
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                    Button("Tap", action: tap)
                        .buttonStyle(.segueSecondary)
                        .help("Tap along with the song; the tempo fills in")
                        .accessibilityHint("Tap repeatedly in time with the song")
                        .accessibilityIdentifier(AccessibilityID.missingTimesTap)
                }
                if let problem {
                    Text(problem)
                        .font(SchibstedGrotesk.medium.font(size: 11))
                        .foregroundStyle(Theme.color.cueText)
                }
            }
        }

        private func tap() {
            if let bpm = taps.tap(at: CACurrentMediaTime()) {
                text = String(bpm)
                problem = nil
            }
        }

        private func commit() {
            problem = onCommit(text)
        }
    }
#endif
