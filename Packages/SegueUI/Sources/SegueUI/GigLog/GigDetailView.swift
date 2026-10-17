#if os(macOS)
    import Library
    import Shows
    import Support
    import SwiftUI

    /// One gig: what was played in order (requests marked), what was skipped, and the
    /// editable venue, date, rating and notes. Edits save on their own after a pause.
    struct GigDetailView: View {
        let entry: GigLogEntry
        let model: GigLogViewModel
        @State private var draft = Draft()
        @State private var isConfirmingDelete = false

        /// The editable fields as typed (dates as `Date` for the picker).
        private struct Draft: Equatable {
            var venue = ""
            var date = Date.now
            var notes = ""
            var rating: Int?

            init() {}

            init(_ details: GigDetails, fallbackDay: CalendarDay) {
                venue = details.venue ?? ""
                date = (details.date ?? fallbackDay).date
                notes = details.notes ?? ""
                rating = details.rating
            }

            var details: GigDetails {
                let venue = venue.trimmingCharacters(in: .whitespacesAndNewlines)
                let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                return GigDetails(
                    venue: venue.isEmpty ? nil : venue,
                    date: CalendarDay(date),
                    notes: notes.isEmpty ? nil : self.notes,
                    rating: rating,
                )
            }
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    fields
                    Rule()
                    GigPlayedList(entry: entry)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { draft = Draft(entry.details, fallbackDay: fallbackDay) }
            .task(id: draft) {
                // Save after a short pause in typing; a newer edit cancels this one.
                do {
                    try await Task.sleep(for: .milliseconds(600))
                } catch {
                    return
                }
                await save()
            }
            .onDisappear { Task { await save() } }
            .confirmationDialog("Delete this gig?", isPresented: $isConfirmingDelete) {
                Button("Delete Gig", role: .destructive) {
                    Task { await model.delete(entry.id) }
                }
                .accessibilityIdentifier(AccessibilityID.gigDelete + ".confirm")
            } message: {
                Text("Its show file is deleted and its songs no longer count as played.")
            }
        }

        private var fallbackDay: CalendarDay {
            CalendarDay(entry.startedAt)
        }

        private func save() async {
            guard draft != Draft() else { return }
            var details = draft.details
            // An undated gig shows its start day in the picker; that is not an edit.
            if entry.details.date == nil, details.date == fallbackDay {
                details.date = nil
            }
            guard details != entry.details else { return }
            await model.update(details, of: entry.id)
        }

        private var header: some View {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gig")
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.muted)
                    Text(entry.details.venue ?? entry.setlistName)
                        .font(SchibstedGrotesk.extraBold.font(size: 30))
                        .tracking(Theme.tracking.title * 30)
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityIdentifier(AccessibilityID.gigTitle)
                    Text(summary)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityIdentifier(AccessibilityID.gigSummary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Delete…") { isConfirmingDelete = true }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.large)
                    .accessibilityIdentifier(AccessibilityID.gigDelete)
            }
        }

        /// "Friday Set · 21:04-22:31 · 9 played, 1 skipped, 1 request".
        private var summary: String {
            let requests = entry.played.count(where: \.fromRequest)
            var counts = ["\(entry.played.count) played"]
            if !entry.skipped.isEmpty {
                counts.append("\(entry.skipped.count) skipped")
            }
            if requests > 0 {
                counts.append(requests == 1 ? "1 request" : "\(requests) requests")
            }
            var parts = [
                entry.setlistName,
                "\(GigText.time(entry.startedAt))–\(GigText.time(entry.endedAt))",
                counts.joined(separator: ", "),
            ]
            if entry.closure == .stale {
                parts.append("closed automatically")
            }
            return parts.joined(separator: " · ")
        }

        private var fields: some View {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    label("Venue")
                    TextField("Venue", text: $draft.venue, prompt: Text("Where you played"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .accessibilityIdentifier(AccessibilityID.gigVenue)
                }
                GridRow {
                    label("Date")
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier(AccessibilityID.gigDate)
                }
                GridRow {
                    label("Rating")
                    RatingPicker(rating: $draft.rating)
                }
                GridRow {
                    label("Notes")
                    TextEditor(text: $draft.notes)
                        .font(Theme.font.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(maxWidth: 520, minHeight: 70, maxHeight: 120)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                        }
                        .accessibilityIdentifier(AccessibilityID.gigNotes)
                }
            }
        }

        private func label(_ text: String) -> some View {
            Text(text)
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
                .frame(minWidth: 60, alignment: .leading)
        }
    }

    /// Five stars; clicking the current rating clears it (rating is optional).
    private struct RatingPicker: View {
        @Binding var rating: Int?

        var body: some View {
            HStack(spacing: 4) {
                ForEach(GigDetails.ratingRange, id: \.self) { value in
                    Button {
                        rating = rating == value ? nil : value
                    } label: {
                        Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundStyle(value <= (rating ?? 0)
                                ? Theme.color.ink : Theme.color.lineStrong)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                    .accessibilityAddTraits(rating == value ? .isSelected : [])
                    .accessibilityIdentifier(AccessibilityID.gigRating(value))
                }
                Text(rating == nil ? "Not rated" : "Click again to clear")
                    .font(.callout)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.leading, 6)
            }
        }
    }

    /// Played songs in play order (requests and added songs marked) and skipped ones.
    private struct GigPlayedList: View {
        let entry: GigLogEntry

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Played")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                    .padding(.bottom, 8)
                ForEach(Array(entry.played.enumerated()), id: \.offset) { offset, played in
                    row(
                        number: "\(offset + 1)",
                        title: played.item.title,
                        marker: marker(played),
                        time: GigText.time(played.startedAt),
                        length: GigText.length(played.duration),
                    )
                    .accessibilityIdentifier(AccessibilityID.gigPlayedRow)
                }
                if entry.played.isEmpty {
                    Text("Nothing was played to the end.")
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                }
                if !entry.skipped.isEmpty {
                    Text("Skipped")
                        .font(Theme.font.sectionHeading)
                        .foregroundStyle(Theme.color.ink)
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    ForEach(entry.skipped) { item in
                        row(number: "-", title: item.title, marker: nil, time: "", length: "")
                            .opacity(0.6)
                            .accessibilityIdentifier(AccessibilityID.gigSkippedRow)
                    }
                }
            }
        }

        private func marker(_ played: PlayedSong) -> String? {
            if played.fromRequest {
                return "Request"
            }
            return played.item.origin == .inserted ? "Added" : nil
        }

        private func row(
            number: String,
            title: String,
            marker: String?,
            time: String,
            length: String,
        ) -> some View {
            HStack(spacing: 8) {
                Text(number)
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 32, alignment: .leading)
                Text(title)
                    .font(SchibstedGrotesk.semiBold.font(size: 15))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                if let marker {
                    KeyChip(key: marker)
                }
                Spacer(minLength: 8)
                Text(time)
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 64, alignment: .trailing)
                Text(length)
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 56, alignment: .trailing)
            }
            .font(SchibstedGrotesk.medium.font(size: 14))
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rule() }
            .accessibilityElement(children: .combine)
        }
    }
#endif
