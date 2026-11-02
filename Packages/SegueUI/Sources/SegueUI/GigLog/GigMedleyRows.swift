#if os(macOS)
    import Library
    import Setlists
    import Shows
    import SwiftUI

    extension AccessibilityID {
        /// A medley's header row in the Gig Log's Played list (P9-3 8.3).
        static let gigMedleyRow = "segue.gig.medley"
        /// A member row nested under it.
        static let gigMedleyMember = "segue.gig.medley.member"
    }

    /// The Played list's rows for one played slot (P9-3 8.3, the parent/child rule): a song,
    /// or a medley header ("4  Love medley", the first member's start, "Medley · 3 songs")
    /// with its members nested under it as "4a", "4b" (each with its arrangement line) and
    /// any skipped member shown muted as "skipped".
    struct GigPlayedSlotRows: View {
        let slot: PlayedSlot
        /// The slot's 1-based number in the played order.
        let number: Int

        var body: some View {
            switch slot {
            case let .song(played):
                GigPlayedRow(
                    number: "\(number)",
                    title: played.item.title,
                    marker: Self.marker(played),
                    time: GigText.time(played.startedAt),
                    detail: GigPlayedListLines.arrangementLine(played.item),
                )
                .accessibilityIdentifier(AccessibilityID.gigPlayedRow)
            case let .medley(_, title, members, skipped):
                medley(title: title, members: members, skipped: skipped)
            }
        }

        @ViewBuilder
        private func medley(title: String?, members: [PlayedSong], skipped: [ShowItem])
            -> some View
        {
            let count = members.first?.item.medley?.count ?? members.count + skipped.count
            GigPlayedRow(
                number: "\(number)",
                title: GigMedleyText.title(title),
                marker: nil,
                time: members.first.map { GigText.time($0.startedAt) } ?? "",
                detail: count == 1
                    ? uiString("Medley · \(count) song") : uiString("Medley · \(count) songs"),
            )
            .accessibilityIdentifier(AccessibilityID.gigMedleyRow)
            ForEach(GigMedleyText.rows(members: members, skipped: skipped), id: \.id) { row in
                switch row.kind {
                case let .played(played):
                    GigPlayedRow(
                        number: GigMedleyText.label(number, row.index),
                        title: played.item.title,
                        marker: Self.marker(played),
                        time: GigText.time(played.startedAt),
                        detail: GigPlayedListLines.arrangementLine(played.item),
                        indent: 24,
                    )
                    .accessibilityIdentifier(AccessibilityID.gigMedleyMember)
                case let .skipped(item):
                    GigPlayedRow(
                        number: GigMedleyText.label(number, row.index),
                        title: item.title,
                        marker: nil,
                        time: "skipped",
                        indent: 24,
                    )
                    .opacity(0.6)
                    .accessibilityIdentifier(AccessibilityID.gigMedleyMember)
                }
            }
        }

        static func marker(_ played: PlayedSong) -> String? {
            if played.fromRequest {
                return "Request"
            }
            return played.item.origin == .inserted ? "Added" : nil
        }
    }

    /// The pure text of the nested medley rows (tested in process).
    enum GigMedleyText {
        struct Row {
            enum Kind {
                case played(PlayedSong)
                case skipped(ShowItem)
            }

            var kind: Kind
            /// The member's index in the medley as planned (its letter).
            var index: Int
            var id: ShowItemID
        }

        /// "Love medley", or "Medley" when untitled.
        static func title(_ title: String?) -> String {
            SetlistMedley(title: title, members: []).displayTitle
        }

        /// "4b": the slot number and the member's letter.
        static func label(_ number: Int, _ index: Int) -> String {
            Setlist.memberLabel(slot: number, index: index)
        }

        /// Played and skipped members in medley order.
        static func rows(members: [PlayedSong], skipped: [ShowItem]) -> [Row] {
            let played = members.map { song in
                Row(kind: .played(song), index: song.item.medley?.index ?? 0, id: song.item.itemId)
            }
            let missed = skipped.map { item in
                Row(kind: .skipped(item), index: item.medley?.index ?? 0, id: item.itemId)
            }
            return (played + missed).sorted { $0.index < $1.index }
        }

        /// A skipped item as the Skipped list names it: "Tum Hi Ho (in Love medley)".
        static func skippedTitle(_ item: ShowItem) -> String {
            guard let medley = item.medley else { return item.title }
            return "\(item.title) (in \(title(medley.title)))"
        }
    }

    /// One row of the Played and Skipped lists.
    struct GigPlayedRow: View {
        let number: String
        let title: String
        let marker: String?
        let time: String
        var detail: String?
        /// Nested member rows sit this far right of the number column.
        var indent: CGFloat = 0

        var body: some View {
            HStack(spacing: 8) {
                Text(number)
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SchibstedGrotesk.semiBold.font(size: 15))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(SchibstedGrotesk.medium.font(size: 13))
                            .foregroundStyle(Theme.color.muted)
                            .lineLimit(2)
                    }
                }
                .padding(.leading, indent)
                if let marker {
                    KeyChip(key: marker)
                }
                Spacer(minLength: 8)
                Text(time)
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 64, alignment: .trailing)
            }
            .font(SchibstedGrotesk.medium.font(size: 14))
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rule() }
            .accessibilityElement(children: .combine)
        }
    }
#endif
