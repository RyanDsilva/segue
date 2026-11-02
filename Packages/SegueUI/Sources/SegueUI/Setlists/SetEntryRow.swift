#if os(macOS)
    import AppKit
    import Library
    import SetAssistant
    import Setlists
    import SwiftUI

    /// One slot: `#  Title  Key  Capo  Time  Start`, the note under the title.
    struct SetEntryRow: View {
        let position: Int
        /// The part the row is in (its leading-edge colour).
        let part: Int
        /// Read in the row's own body, so a selection change re-renders it.
        let selection: () -> Bool

        private var isSelected: Bool {
            selection()
        }

        /// Returns whether the click was plain (opens the editor).
        let onSelect: () -> Bool
        /// Context menu "Insert Break After"; nil when read-only.
        let onInsertBreak: (() -> Void)?
        let entry: SetlistEntry
        /// For a setlist saved with a song twice (before the one-song-once rule): the
        /// position of the song's first entry, shown so the repeat can be removed.
        var repeatOf: Int?
        let record: SongRecord?
        let timing: ItemTiming?
        let isReadOnly: Bool
        let onChange: (SetlistEntry) -> Void
        /// Opens Arrange Sections (P3-16); nil when the song is missing.
        let onArrange: (() -> Void)?
        let onRemove: () -> Void
        /// Moves the slot one place (-1 up, +1 down); nil when the setlist is read-only.
        var onMove: ((Int) -> Void)?
        var isLast = false
        /// The set assistant's score and Rebuild lock (P3-7, R115).
        var assistant = EntryAssistant()
        /// A medley member's place (P9-3 6.2): its label ("4b"), medley and actions; nil for
        /// a plain slot.
        var member: MedleyMemberPlace?
        /// The quiet reprise mark (decision 8): "also 9" on a member, "reprise of 4a" on a
        /// slot; nil when the song is in the set once.
        var reprise: RepriseMark?
        /// "Make Medley from 3 Songs" when this row is part of a selection that can become a
        /// medley (P9-3 6.1); nil otherwise.
        var makeMedley: MakeMedleyItem?
        @State private var isHovered = false
        @State private var isEditing = false
        @Environment(\.exportPDF) private var exportPDF
        @Environment(\.pdfSetlist) private var pdfSetlist

        var body: some View {
            let display = SetlistEntryDisplay(entry: entry, record: record)
            HStack(spacing: 8) {
                Text(numberText)
                    .font(SchibstedGrotesk.medium.font(size: 14))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 32, alignment: .leading)
                titleColumn
                    .padding(.leading, member == nil ? 0 : MedleyMemberPlace.indent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                cell(display.key ?? "-", width: 56, weight: .semiBold, isOverridden: hasKeyOverride)
                    .accessibilityIdentifier(AccessibilityID.entryKey)
                cell(display.capoText, width: 64, isOverridden: entry.overrides.capo != nil)
                    .accessibilityIdentifier(AccessibilityID.entryCapo)
                cell(
                    timing?.timeText ?? SetlistTiming.unknownText,
                    width: 56,
                    help: timing?.slot?.help,
                )
                .accessibilityValue(timing?.slot?.spoken ?? "")
                .accessibilityIdentifier(AccessibilityID.entryTime)
                cell(startText, width: 60, alignment: .trailing)
                    .accessibilityIdentifier(AccessibilityID.entryStart)
                EntryAssistantCells(assistant: assistant, title: title, isHovered: isHovered)
                removeButton
            }
            .padding(.leading, member == nil ? 32 : 32 - MedleyMemberPlace.cardInset)
            .padding(.trailing, member == nil ? 12 : 12 - MedleyMemberPlace.cardInset)
            .padding(.vertical, member == nil ? 11 : 8)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if member == nil {
                    Rectangle().fill(PartPalette.color(part)).frame(width: 4)
                }
            }
            .overlay(alignment: .bottom) {
                if member == nil {
                    Rule()
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                if onSelect(), !isReadOnly {
                    isEditing = true
                }
            }
            .popover(isPresented: $isEditing, arrowEdge: .leading) {
                SetEntryEditor(
                    entry: entry,
                    record: record,
                    onChange: onChange,
                    onArrange: onArrange,
                )
            }
            .contextMenu {
                if let makeMedley {
                    Button(makeMedley.title, action: makeMedley.action)
                    Divider()
                }
                Button(uiString("Edit Key, Capo and Note…")) { isEditing = true }
                    .disabled(isReadOnly)
                Button(uiString("Arrange Sections…")) { onArrange?() }
                    .disabled(onArrange == nil)
                if let member {
                    MedleyMemberMenuItems(place: member, isReadOnly: isReadOnly)
                } else {
                    Button(uiString("Insert Break After")) { onInsertBreak?() }
                        .disabled(onInsertBreak == nil)
                }
                if let exportPDF, let setlistID = pdfSetlist {
                    Button(uiString("Export Slot as PDF\u{2026}")) {
                        exportPDF.open(.slot(setlistID, entry.itemId), false)
                    }
                    .disabled(!exportPDF.isEnabled || record == nil)
                    .accessibilityIdentifier(AccessibilityID.pdfExportSlot)
                }
                Button(uiString("Remove from Setlist"), role: .destructive, action: onRemove)
                    .disabled(isReadOnly)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(member == nil ? AccessibilityID.setlistEntry
                : AccessibilityID.medleyMember)
            .accessibilityAction(named: "Edit") { isEditing = true }
            .accessibilityAction(named: "Arrange Sections") { onArrange?() }
            .entryAssistantActions(assistant)
            .accessibilityActions {
                if let member, !isReadOnly {
                    MedleyMemberMenuItems(place: member, isReadOnly: isReadOnly, spoken: true)
                }
                if let onMove, member == nil {
                    if position > 1 {
                        Button(uiString("Move up")) { onMove(-1) }
                    }
                    if !isLast {
                        Button(uiString("Move down")) { onMove(1) }
                    }
                }
            }
        }

        private var title: String {
            record.map(SongSummary.title) ?? "Missing song"
        }

        /// "4" for a slot, "4b" for a medley member.
        private var numberText: String {
            member?.label ?? "\(position)"
        }

        /// A medley member sits on its card: no fill until selected or hovered.
        private var rowBackground: Color {
            if isSelected || isHovered || isEditing {
                return member == nil ? Theme.color.surfaceAlt : Theme.color.line
            }
            return member == nil ? Theme.color.ground : .clear
        }

        /// "4. Kesariya", "4b, Tum Hi Ho, key A, in Love medley", with the repeat or the
        /// reprise mark read too.
        private var accessibilityTitle: String {
            let reprise = reprise.map { ", \($0.spoken)" } ?? ""
            if let member {
                let key = SetlistEntryDisplay(entry: entry, record: record).key
                    .map { ", key \($0)" } ?? ""
                return "\(member.label), \(title)\(key), in \(member.medleyTitle)\(reprise)"
            }
            return repeatOf.map { "\(position). \(title), also at \($0)" }
                ?? "\(position). \(title)\(reprise)"
        }

        private var hasKeyOverride: Bool {
            entry.overrides.transpose != nil || entry.overrides.capo != nil
        }

        private var startText: String {
            timing?.startText ?? ""
        }

        private var titleColumn: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(SchibstedGrotesk.semiBold.font(size: 16))
                        .foregroundStyle(record == nil ? Theme.color.muted : Theme.color.ink)
                        .lineLimit(1)
                        .accessibilityIdentifier(AccessibilityID.entryTitle)
                    if let reprise {
                        Text(reprise.text)
                            .font(SchibstedGrotesk.medium.font(size: 12))
                            .foregroundStyle(Theme.color.muted)
                            .lineLimit(1)
                            .layoutPriority(1)
                            .help(reprise.help)
                            .accessibilityHidden(true)
                            .accessibilityIdentifier(AccessibilityID.medleyReprise)
                    }
                }
                if record == nil {
                    Text("No longer in the library folder", bundle: #bundle)
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                } else if let repeatOf {
                    Label(
                        uiString("Also at #\(repeatOf)"),
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .symbolRenderingMode(.multicolor)
                    .help(uiString("This song is in the set twice. Remove one of them."))
                    .accessibilityIdentifier(AccessibilityID.entryRepeat)
                } else {
                    SlotDetailLines(entry: entry, record: record, openArrangement: onArrange)
                }
            }
        }

        private func cell(
            _ text: String,
            width: CGFloat,
            weight: SchibstedGrotesk = .medium,
            alignment: Alignment = .leading,
            isOverridden: Bool = false,
            help: String? = nil,
        ) -> some View {
            Text(text)
                .font(weight.font(size: 14))
                .foregroundStyle(weight == .semiBold ? Theme.color.ink : Theme.color.muted)
                .underline(isOverridden, pattern: .dot, color: Theme.color.muted)
                .lineLimit(1)
                .frame(width: width, alignment: alignment)
                .help(help ?? (isOverridden ? uiString("Set for this setlist only") : ""))
        }

        private var removeButton: some View {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered && !isReadOnly ? 1 : 0)
            .disabled(isReadOnly)
            .help(uiString("Remove from setlist"))
            .accessibilityLabel(uiString("Remove \(title)"))
            .accessibilityIdentifier(AccessibilityID.entryRemove)
        }
    }
#endif
