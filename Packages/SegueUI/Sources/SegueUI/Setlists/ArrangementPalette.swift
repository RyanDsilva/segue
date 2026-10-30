#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// The song's parts (P8-3 section 6.2): one button per label group in song order. Click
    /// inserts after the selected pass (the occurrence by the counting rule); right-click
    /// picks an occurrence; drag into the lane inserts at the drop point.
    struct ArrangementPalette: View {
        let draft: ArrangementDraft
        let selection: Int
        let isReadOnly: Bool
        @Binding var dragging: ArrangementDrag?
        let perform: (ArrangementDraft.Edit) -> Void

        var body: some View {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(draft.groups) { group in
                    PaletteButton(
                        group: group,
                        isReadOnly: isReadOnly,
                        add: { perform(.insertGroup(group.id, after: selection)) },
                        addOccurrence: { unit in
                            perform(.insert(unit: unit.index, at: selection + 1))
                        },
                    )
                    .onDrag {
                        let unit = draft.occurrence(of: group.id, after: selection) ?? group
                            .units[0]
                        dragging = .part(unit.index)
                        return NSItemProvider(object: ArrangementDrag.part(unit.index)
                            .payload as NSString)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct PaletteButton: View {
        let group: ArrangementDraft.Group
        let isReadOnly: Bool
        let add: () -> Void
        let addOccurrence: (SongSectionUnit) -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: add) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(kindColor)
                        .frame(width: 3, height: 14)
                    Text(group.title)
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .foregroundStyle(Theme.color.ink)
                    if group.isNew {
                        Text("New")
                            .font(SchibstedGrotesk.bold.font(size: 11))
                            .foregroundStyle(Theme.color.cueText)
                    }
                    if group.units.count > 1 {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.color.muted)
                            .opacity(isHovered ? 1 : 0)
                    }
                }
                .padding(EdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 10))
                .background(
                    isHovered ? Theme.color.surfaceAlt : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous),
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)
            .onHover { isHovered = $0 }
            .contextMenu {
                if group.units.count > 1, !isReadOnly {
                    occurrenceItems
                }
            }
            .help("Add \(group.title) after the selected pass (\(group.token.text) in the roadmap)")
            .accessibilityLabel("Add \(group.title)")
            .accessibilityHint("Adds a pass after the selected one")
            .accessibilityActions {
                if group.units.count > 1, !isReadOnly {
                    occurrenceItems
                }
            }
            .accessibilityIdentifier(AccessibilityID.arrangementPalette(group.id))
        }

        /// "Chorus 1st - Harbour lights, call me back".
        private var occurrenceItems: some View {
            ForEach(group.units) { unit in
                Button([unit.name, unit.firstLine].compactMap(\.self).joined(separator: " - ")) {
                    addOccurrence(unit)
                }
            }
        }

        private var kindColor: Color {
            Color(nsColor: SectionBandStyle.dynamicColor(for: group.units[0].kind ?? .custom("")))
        }
    }
#endif
