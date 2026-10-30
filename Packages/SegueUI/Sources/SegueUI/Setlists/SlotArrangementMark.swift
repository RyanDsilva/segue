#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// A set row's lines under the title: the slot note, then the arrangement mark.
    struct SlotDetailLines: View {
        let entry: SetlistEntry
        let record: SongRecord?
        let openArrangement: (() -> Void)?

        var body: some View {
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                    .accessibilityIdentifier(AccessibilityID.entryNote)
            }
            SlotArrangementMark(entry: entry, record: record, open: openArrangement)
        }
    }

    /// A set row's arrangement line (P3-16, P8-3, R122, R123): "Custom · " and the roadmap
    /// ("Custom · I:CH V1 C V2 C B C O:1"), or in the cue colour the out-of-date note; a click
    /// opens Arrange Sections.
    struct SlotArrangementMark: View {
        let entry: SetlistEntry
        let record: SongRecord?
        let open: (() -> Void)?

        var body: some View {
            if let arrangement = entry.arrangement, let record {
                let units = SongSections.units(of: record.document)
                let outOfDate = ArrangementResolver.resolve(arrangement, units: units).isOutOfDate
                Button { open?() } label: {
                    Label(
                        outOfDate ? "Arrangement out of date - full song on stage"
                            : ArrangementDraft.markText(arrangement, units: units),
                        systemImage: outOfDate ? "exclamationmark.triangle.fill" : "scissors",
                    )
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(outOfDate ? Theme.color.cueText : Theme.color.muted)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help(outOfDate
                    ? "The song's sections changed since it was arranged. Click to update."
                    : "Custom arrangement for this gig. Click to edit it.")
                .accessibilityLabel(outOfDate
                    ? "Arrangement out of date. The full song will be shown on stage."
                    : "Custom arrangement, " + ArrangementDraft.countsText(arrangement))
                .accessibilityIdentifier(AccessibilityID.arrangementMark)
            }
        }
    }
#endif
