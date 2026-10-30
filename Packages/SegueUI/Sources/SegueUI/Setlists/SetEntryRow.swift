#if os(macOS)
    import AppKit
    import Library
    import SetAssistant
    import Setlists
    import SwiftUI

    /// One slot: `#  Title  Key  Capo  Length  Start`, the note under the title.
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
        @State private var isHovered = false
        @State private var isEditing = false

        var body: some View {
            let display = SetlistEntryDisplay(entry: entry, record: record)
            HStack(spacing: 8) {
                Text("\(position)")
                    .font(SchibstedGrotesk.medium.font(size: 14))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 32, alignment: .leading)
                titleColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                cell(display.key ?? "-", width: 56, weight: .semiBold, isOverridden: hasKeyOverride)
                    .accessibilityIdentifier(AccessibilityID.entryKey)
                cell(display.capoText, width: 64, isOverridden: entry.overrides.capo != nil)
                    .accessibilityIdentifier(AccessibilityID.entryCapo)
                cell(SetlistTiming.format(timing?.length), width: 56)
                    .accessibilityIdentifier(AccessibilityID.entryLength)
                cell(startText, width: 60, alignment: .trailing)
                    .accessibilityIdentifier(AccessibilityID.entryStart)
                EntryAssistantCells(assistant: assistant, title: title, isHovered: isHovered)
                removeButton
            }
            .padding(.leading, 32)
            .padding(.trailing, 12)
            .padding(.vertical, 11)
            .background(isSelected || isHovered || isEditing ? Theme.color.surfaceAlt
                : Theme.color.ground)
            .overlay(alignment: .leading) {
                Rectangle().fill(PartPalette.color(part)).frame(width: 4)
            }
            .overlay(alignment: .bottom) { Rule() }
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
                Button("Edit Key, Capo and Note…") { isEditing = true }
                    .disabled(isReadOnly)
                Button("Arrange Sections…") { onArrange?() }
                    .disabled(onArrange == nil)
                Button("Insert Break After") { onInsertBreak?() }
                    .disabled(onInsertBreak == nil)
                Button("Remove from Setlist", role: .destructive, action: onRemove)
                    .disabled(isReadOnly)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(repeatOf.map { "\(position). \(title), also at \($0)" }
                ?? "\(position). \(title)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(AccessibilityID.setlistEntry)
            .accessibilityAction(named: "Edit") { isEditing = true }
            .accessibilityAction(named: "Arrange Sections") { onArrange?() }
            .entryAssistantActions(assistant)
            .accessibilityActions {
                if let onMove {
                    if position > 1 {
                        Button("Move up") { onMove(-1) }
                    }
                    if !isLast {
                        Button("Move down") { onMove(1) }
                    }
                }
            }
        }

        private var title: String {
            record.map(SongSummary.title) ?? "Missing song"
        }

        private var hasKeyOverride: Bool {
            entry.overrides.transpose != nil || entry.overrides.capo != nil
        }

        private var startText: String {
            timing?.startText ?? ""
        }

        private var titleColumn: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SchibstedGrotesk.semiBold.font(size: 16))
                    .foregroundStyle(record == nil ? Theme.color.muted : Theme.color.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier(AccessibilityID.entryTitle)
                if record == nil {
                    Text("No longer in the library folder")
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                } else if let repeatOf {
                    Label("Also at #\(repeatOf)", systemImage: "exclamationmark.triangle.fill")
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .symbolRenderingMode(.multicolor)
                        .help("This song is in the set twice. Remove one of them.")
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
        ) -> some View {
            Text(text)
                .font(weight.font(size: 14))
                .foregroundStyle(weight == .semiBold ? Theme.color.ink : Theme.color.muted)
                .underline(isOverridden, pattern: .dot, color: Theme.color.muted)
                .lineLimit(1)
                .frame(width: width, alignment: alignment)
                .help(isOverridden ? "Set for this setlist only" : "")
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
            .help("Remove from setlist")
            .accessibilityLabel("Remove \(title)")
            .accessibilityIdentifier(AccessibilityID.entryRemove)
        }
    }
#endif
