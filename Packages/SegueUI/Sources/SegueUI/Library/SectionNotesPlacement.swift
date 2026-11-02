import Library
import SwiftUI

/// The "Shows on" pop-up's choices and the `{chorus}` repeat explanation of the section
/// notes sheet (P3-17, R144, R146), kept apart from the view so they test in process.
enum SectionNotesPlacement {
    struct Choice: Hashable, Identifiable {
        var placement: NotePlacement
        /// "Every time", "Chorus #2", "Chorus #3 (repeat)".
        var title: String
        var isRepeat: Bool

        var id: NotePlacement {
            placement
        }
    }

    /// The explanation under a row whose note sits on (or is headed for) a repeat.
    struct RepeatHint: Hashable {
        var message: String
        /// The button that puts the note in the chart instead.
        var action: String
        /// Where a new note goes when the button is used.
        var chartPlacement: NotePlacement
    }

    /// Every time, then each instance. A chart note on a label written out once hides that
    /// instance: a note there already shows every time the chorus is played or repeated, so
    /// its choices are Every time or a repeat (which makes it a stage note) (R146).
    static func choices(in group: SectionNoteGroup, chart: Bool) -> [Choice] {
        guard group.hasPlacements else { return [] }
        let hidesWrittenOut = chart && group.writtenOut.count == 1
        let instances = group.instances.filter { !(hidesWrittenOut && $0.acceptsChartNotes) }
        return [Choice(placement: .everyTime, title: uiString("Every time"), isRepeat: false)]
            + instances.map { instance in
                Choice(
                    placement: .instance(instance.occurrence),
                    title: "\(group.title) #\(instance.occurrence)"
                        + (instance.isRepeat ? " (repeat)" : ""),
                    isRepeat: instance.isRepeat,
                )
            }
    }

    /// Whether `placement` names a `{chorus}` repeat of `group`.
    static func isRepeat(_ placement: NotePlacement?, in group: SectionNoteGroup) -> Bool {
        guard case let .instance(number) = placement else { return false }
        return group.instance(number)?.isRepeat == true
    }

    /// The hint for a note placed on the repeat `placement`, nil when it is not a repeat or
    /// the label has nowhere in the chart to go.
    static func repeatHint(for placement: NotePlacement?, in group: SectionNoteGroup)
        -> RepeatHint?
    {
        guard case let .instance(number) = placement, let instance = group.instance(number),
              instance.isRepeat, group.acceptsChartNotes
        else { return nil }
        let message = "\(group.title) #\(number) is a {chorus} repeat, so it has no lines of "
            + "its own. A note here shows on stage only."
        if group.writtenOut.count > 1, let root = instance.repeatOf {
            return RepeatHint(
                message: message,
                action: "Put it in \(group.title) #\(root) instead",
                chartPlacement: .instance(root),
            )
        }
        return RepeatHint(
            message: message,
            action: "Show it every time instead",
            chartPlacement: .everyTime,
        )
    }

    /// The confirmation before a stage note on a repeat becomes a chart note, which goes in
    /// the chorus the repeat repeats.
    static func chartConfirmation(for note: SectionNote, in group: SectionNoteGroup) -> String? {
        guard note.isStageOnly, case let .instance(number) = note.placement,
              let instance = group.instance(number), instance.isRepeat
        else { return nil }
        let root = instance.repeatOf.map { "\(group.title) #\($0)" } ?? "the chorus it repeats"
        return "\(group.title) #\(number) is a repeat. In the chart this note goes in \(root) "
            + "and shows every time \(root) is played or repeated."
    }
}

extension SectionNoteEdit {
    /// The existing note this edit names; nil for an add.
    var noteID: SectionNoteID? {
        switch self {
        case let .delete(id), let .pin(id, _, _), let .place(id, _),
             let .setStageOnly(id, _), let .setText(id, _):
            id
        case .add:
            nil
        }
    }
}

#if os(macOS)

    // MARK: Placement controls

    /// The "Shows on" pop-up: a muted caption and a small native pop-up.
    struct PlacementPicker: View {
        let choices: [SectionNotesPlacement.Choice]
        @Binding var selection: NotePlacement
        let identifier: String

        var body: some View {
            HStack(spacing: 6) {
                Text("Shows on", bundle: #bundle)
                    .font(.caption)
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                Picker(uiString("Shows on"), selection: $selection) {
                    ForEach(choices) { choice in
                        Text(choice.title).tag(choice.placement)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .accessibilityLabel(uiString("Shows on"))
                .accessibilityIdentifier(identifier)
            }
        }
    }

    /// The quiet mark on a stage note whose section changed since it was placed.
    struct CheckPlacementMark: View {
        var body: some View {
            Label(uiString("Check placement"), systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.color.muted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().strokeBorder(Theme.color.lineStrong))
                .fixedSize()
                .help(uiString("""
                This section changed since the note was placed. Pick where it shows to confirm.
                """))
                .accessibilityIdentifier(AccessibilityID.sectionNoteCheckPlacement)
        }
    }

    /// Why a note on a `{chorus}` repeat is stage only, with a button that puts it in the
    /// chart instead.
    struct RepeatHintView: View {
        let hint: SectionNotesPlacement.RepeatHint
        let action: () -> Void

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hint.message)
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(hint.action, action: action)
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            .padding(.top, 2)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.sectionNoteRepeatHint)
        }
    }
#endif
