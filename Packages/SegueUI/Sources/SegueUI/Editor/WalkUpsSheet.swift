// P8-4b (docs/phases/8-workstreams/P8-4-bass.md sections 8.7, 8.9). The Walk-ups list: the
// song's feel and scale (R170), every chord change grouped under its section with the walk-up
// shown (or "Nothing"), the picker beside a row, and saved walk-ups that no longer match the
// song. Shared by the editor (undoable) and the library (no undo).

import Editing
import Library
import MusicTheory
import SwiftUI

/// What the Walk-ups list shows and does for one song; read inside the sheet's body, so it
/// follows the song as picks and the feel change.
struct WalkUpsSource {
    var title: String
    /// Every change in written order.
    var changes: [ChordChange]
    /// The section label of an annotated section index ("Verse 1"); nil for loose lines.
    var sectionLabel: (Int) -> String?
    /// Saved picks that no longer match, with their text as saved ("Verse 1: G -> C, A B").
    var unmatched: [(pick: WalkUpPick, text: String)]
    /// The song's own feel; nil = the profile's default.
    var feel: BassGenre?
    var defaultFeel: BassGenre
    /// The song's own scale (R170); nil = `defaultScale`, from the feel and key.
    var scale: FillMode?
    var defaultScale: FillMode
    /// The scales a key of the song's quality can use; [] without a key (nothing to choose).
    var scales: [FillMode]
    var density: WalkUpDensity
    /// Set for a song saved by a newer Segue: nothing can change.
    var readOnlyHelp: String?
    var picking: WalkUpPicking
    var setFeel: @MainActor (BassGenre?) -> Void
    var setScale: @MainActor (FillMode?) -> Void
    var remove: @MainActor ([WalkUpPick]) -> Void
    /// The song's saved fills (P8-7 12.1), the "Fills" group.
    var fills: [FillListItem] = []
    /// Opens the fill editor on a saved fill (nil when it no longer applies).
    var openFill: @MainActor (PartID) -> FillEditorModel? = { _ in nil }
    var renameFill: @MainActor (PartID, String) -> Void = { _, _ in }
    var deleteFills: @MainActor ([PartID]) -> Void = { _ in }
    /// How the fill sheet closed (a gig keeps its drafts).
    var fillClosed: @MainActor (FillEditorModel, Bool) -> Void = { _, _ in }
}

/// The Walk-ups list sheet.
struct WalkUpsSheet: View {
    let source: @MainActor () -> WalkUpsSource?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let source = source() {
                header(source)
                Rule()
                list(source)
                if !source.fills.isEmpty {
                    Rule()
                    FillsGroup(source: source)
                }
                if !source.unmatched.isEmpty {
                    Rule()
                    unmatched(source)
                }
            } else {
                Text("This song is no longer available.")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rule()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.seguePrimary)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AccessibilityID.walkUpsDone)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 540, height: 600)
        .background(Theme.color.ground)
        .accessibilityIdentifier(AccessibilityID.walkUpsSheet)
    }

    private func header(_ source: WalkUpsSource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Walk-ups")
                        .font(SchibstedGrotesk.extraBold.font(size: 17))
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(source.title)
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 12)
                feelMenu(source)
                // The scale's default follows the feel, so it sits after it.
                scaleMenu(source)
            }
            if source.density == .off {
                Text("Walk-ups are off on charts. Turn them on in Settings > Instrument.")
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
            } else if let help = source.readOnlyHelp {
                Text(help)
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// The song's feel, which orders its walk-ups.
    private func feelMenu(_ source: WalkUpsSource) -> some View {
        Menu {
            Picker("Feel", selection: Binding(
                get: { source.feel },
                set: { source.setFeel($0) },
            )) {
                Text("Default (\(source.defaultFeel.title))").tag(BassGenre?.none)
                Divider()
                ForEach(BassGenre.allCases, id: \.self) { genre in
                    Text(genre.title).tag(BassGenre?.some(genre))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("Feel: " + (source.feel?.title ?? "Default (\(source.defaultFeel.title))"))
                .font(SchibstedGrotesk.semiBold.font(size: 13))
        }
        .menuStyle(.button)
        .buttonStyle(.segueSecondary)
        .controlSize(.small)
        .fixedSize()
        .disabled(source.readOnlyHelp != nil)
        .help(source.readOnlyHelp ?? "Reorders this song's walk-ups for its style")
        .accessibilityIdentifier(AccessibilityID.walkUpsFeel)
    }

    /// The song's scale for passing notes (R170), beside the feel.
    private func scaleMenu(_ source: WalkUpsSource) -> some View {
        let fallback = "Default (\(source.defaultScale.title))"
        return Menu {
            Picker("Scale", selection: Binding(
                get: { source.scale },
                set: { source.setScale($0) },
            )) {
                Text(fallback).tag(FillMode?.none)
                Divider()
                ForEach(source.scales, id: \.self) { mode in
                    Text(mode.title).tag(FillMode?.some(mode))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("Scale: " + (source.scale?.title ?? fallback))
                .font(SchibstedGrotesk.semiBold.font(size: 13))
        }
        .menuStyle(.button)
        .buttonStyle(.segueSecondary)
        .controlSize(.small)
        .fixedSize()
        .disabled(source.readOnlyHelp != nil || source.scales.isEmpty)
        .help(source.readOnlyHelp ?? (source.scales.isEmpty
                ? "Set the song's key to choose its scale"
                : "The scale this song's walk-ups and fills pass through"))
        .accessibilityIdentifier(AccessibilityID.walkUpsScale)
    }

    /// The changes grouped under their sections, in written order.
    private func list(_ source: WalkUpsSource) -> some View {
        let groups = Self.groups(source.changes)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if groups.isEmpty {
                    Text("No chord changes to walk between.")
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                }
                ForEach(groups, id: \.section) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text((source.sectionLabel(group.section) ?? "Lines").uppercased())
                            .font(SchibstedGrotesk.bold.font(size: 11))
                            .tracking(0.08 * 11)
                            .foregroundStyle(Theme.color.muted)
                            .padding(.leading, 8)
                            .padding(.bottom, 2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.changes, id: \.offset) { offset, change in
                            WalkUpsRow(
                                change: change,
                                section: source.sectionLabel(group.section),
                                picking: source.picking,
                            )
                            .accessibilityIdentifier(AccessibilityID.walkUpsRow(offset))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity)
    }

    /// "2 saved walk-ups no longer match this song", each with Remove, then Remove All.
    private func unmatched(_ source: WalkUpsSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                let count = source.unmatched.count
                Text(count == 1 ? "1 saved walk-up no longer matches this song"
                    : "\(count) saved walk-ups no longer match this song")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.ink)
                Spacer()
                Button("Remove All") { source.remove(source.unmatched.map(\.pick)) }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .disabled(source.readOnlyHelp != nil)
                    .accessibilityIdentifier(AccessibilityID.walkUpsRemoveAll)
            }
            ForEach(Array(source.unmatched.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.text)
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button("Remove") { source.remove([item.pick]) }
                        .buttonStyle(.segueSecondary)
                        .controlSize(.small)
                        .disabled(source.readOnlyHelp != nil)
                        .accessibilityLabel("Remove \(item.text)")
                        .accessibilityIdentifier(AccessibilityID.walkUpsRemove(index))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.color.surfaceAlt)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.walkUpsUnmatched)
    }

    struct Group {
        var section: Int
        var changes: [(offset: Int, change: ChordChange)]
    }

    /// Consecutive changes of one section form a group (a section played twice in written
    /// order is two groups); `offset` numbers rows across the whole list.
    static func groups(_ changes: [ChordChange]) -> [Group] {
        var result: [Group] = []
        for (offset, change) in changes.enumerated() {
            if result.last?.section == change.section {
                result[result.count - 1].changes.append((offset, change))
            } else {
                result.append(Group(section: change.section, changes: [(offset, change)]))
            }
        }
        return result
    }
}

/// One change: "G -> C", the walk-up shown (or "Nothing"), and whose it is; a click opens the
/// picker beside the row.
private struct WalkUpsRow: View {
    let change: ChordChange
    let section: String?
    let picking: WalkUpPicking
    @State private var isPresented = false
    @State private var isHovered = false
    @Environment(\.walkUpAudition) private var audition

    var body: some View {
        HStack(spacing: 4) {
            if let audition {
                // Plays the walk-up the chart shows (P8-6 10.2).
                Button {
                    guard let player = audition.player(),
                          let phrase = audition.phrase(change, Self.shown(change))
                    else { return }
                    player.play(phrase)
                    audition.played()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.color.muted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!audition.isEnabled)
                .help(audition.isEnabled ? "Play this walk-up" : SoundGate.offHelp)
                .accessibilityLabel("Play \(change.fromName) to \(change.toName)")
                .accessibilityIdentifier(AccessibilityID.walkUpsPlay)
            }
            rowButton
        }
    }

    private var rowButton: some View {
        Button {
            isPresented = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(change.fromName) \u{2192} \(change.toName)")
                    .font(SchibstedGrotesk.bold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                    .frame(width: 120, alignment: .leading)
                Text(Self.runText(change))
                    .font(SchibstedGrotesk.medium.font(size: 14))
                    .foregroundStyle(change.pick != nil ? Theme.color.ink : Theme.color.muted)
                Spacer(minLength: 8)
                Text(Self.status(change))
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered || isPresented ? Theme.color.surfaceAlt : Color.clear),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!picking.isEnabled)
        .onHover { isHovered = $0 }
        .help(picking.isEnabled ? "Shows other walk-ups" : "")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            WalkUpPopover(id: change.id, picking: picking) {
                isPresented = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(change, section: section))
        .accessibilityHint("Shows other walk-ups")
        .accessibilityAddTraits(.isButton)
    }

    /// The walk-up the chart shows for this change (the pick, else the suggestion), even
    /// with walk-ups off on charts; "Nothing" for a hold or none.
    static func shown(_ change: ChordChange) -> WalkUpCandidate? {
        guard let candidate = change.pickCandidate ?? change.candidates.first,
              candidate.kind != .hold
        else { return nil }
        return candidate
    }

    static func runText(_ change: ChordChange) -> String {
        guard let candidate = shown(change) else { return "Nothing" }
        let notes = zip(candidate.notes.map(\.chartName), candidate.chromatic)
            .map { $0 + ($1 ? "\u{00B0}" : "") }
        return notes.joined(separator: " ") + " \u{203A}"
    }

    static func status(_ change: ChordChange) -> String {
        if change.pick != nil {
            return "Your pick"
        }
        // A written stepwise line suggests "Nothing" first (R162 Q1).
        if !change.candidates.isEmpty {
            return "Suggested"
        }
        return change.suppressed?.reason ?? ""
    }

    /// "Verse 1, G to C, A B, your pick".
    static func spoken(_ change: ChordChange, section: String?) -> String {
        let notes = shown(change).map { $0.notes.map(\.chartName).joined(separator: " ") }
            ?? "nothing"
        return [
            section,
            "\(change.fromName) to \(change.toName)",
            notes,
            status(change).lowercased(),
        ]
        .compactMap { $0?.isEmpty == false ? $0 : nil }
        .joined(separator: ", ")
    }
}
