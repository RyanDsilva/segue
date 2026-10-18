#if os(macOS)
    import Library
    import Shows
    import Support
    import SwiftUI

    /// The Gig log destination: finished gigs newest first beside the selected gig.
    struct GigLogPane: View {
        @Bindable var model: GigLogViewModel

        var body: some View {
            HStack(spacing: 0) {
                list
                    .frame(width: 360)
                Rule(axis: .vertical)
                Group {
                    if let entry = model.selected {
                        GigDetailView(entry: entry, model: model)
                            .id(entry.id)
                    } else {
                        ContentUnavailableView(
                            "No Gig Selected",
                            systemImage: "music.mic",
                            description: Text("Finished shows appear here."),
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.color.ground)
            }
            .navigationTitle("Gig Log")
            .navigationSubtitle(model.entries.count == 1 ? "1 gig" : "\(model.entries.count) gigs")
            .task { await model.reload() }
        }

        private var list: some View {
            SelectableList(items: model.entries, selection: $model.selection) { entry in
                GigLogRow(entry: entry)
            }
            .accessibilityIdentifier(AccessibilityID.gigLogList)
            .background(Theme.color.ground)
            .overlay {
                if model.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Gigs Yet", systemImage: "music.mic")
                    } description: {
                        Text("When you end a show, it is logged here with what you played.")
                    }
                    .accessibilityIdentifier(AccessibilityID.gigLogEmpty)
                }
            }
        }
    }

    /// "Fri 23 Oct 2026" / "The Anchor · Friday Set" / "9 played" and the rating.
    private struct GigLogRow: View {
        let entry: GigLogEntry

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(GigText.day(entry))
                        .font(SchibstedGrotesk.semiBold.font(size: 15))
                        .foregroundStyle(Theme.color.ink)
                    Text([entry.details.venue, entry.setlistName].compactMap(\.self)
                        .joined(separator: " · "))
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(entry.played.count) played")
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                    if let rating = entry.details.rating {
                        RatingDots(rating: rating)
                    }
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.gigLogRow)
        }
    }

    /// A read-only 1-5 rating as small filled/empty stars.
    struct RatingDots: View {
        let rating: Int

        var body: some View {
            HStack(spacing: 2) {
                ForEach(GigDetails.ratingRange, id: \.self) { value in
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.system(size: 9))
                        .foregroundStyle(
                            value <= rating ? Theme.color.ink : Theme.color.indicatorOff,
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rated \(rating) of 5")
        }
    }

    enum GigText {
        /// The gig's date ("Fri 23 Oct 2026"): its set date, else the day it started.
        static func day(_ entry: GigLogEntry) -> String {
            (entry.details.date ?? CalendarDay(entry.startedAt)).displayText
        }

        /// "21:04"
        static func time(_ date: Date) -> String {
            date.formatted(date: .omitted, time: .shortened)
        }

        /// "3:40" for a duration in seconds.
        static func length(_ seconds: TimeInterval) -> String {
            let whole = max(Int(seconds.rounded()), 0)
            return whole >= 3600
                ? String(format: "%d:%02d:%02d", whole / 3600, whole % 3600 / 60, whole % 60)
                : String(format: "%d:%02d", whole / 60, whole % 60)
        }
    }
#endif
