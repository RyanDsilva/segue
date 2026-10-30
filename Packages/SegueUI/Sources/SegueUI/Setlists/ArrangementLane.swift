#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// What is being dragged in Arrange Sections: a pass in the lane or a part from the
    /// palette. The payload strings are "pass:<position>" and "part:<unit index>".
    enum ArrangementDrag: Equatable {
        case pass(Int)
        case part(Int)

        var payload: String {
            switch self {
            case let .pass(position): "pass:\(position)"
            case let .part(unit): "part:\(unit)"
            }
        }
    }

    /// The sequence lane (P8-3 section 6.3): one chip per pass, wrapping, with drag and drop
    /// and an insertion mark. One focusable element; the sheet maps its keys to edits.
    struct ArrangementLane: View {
        let draft: ArrangementDraft
        let selection: Int
        let isReadOnly: Bool
        @Binding var dragging: ArrangementDrag?
        let select: (Int) -> Void
        let perform: (ArrangementDraft.Edit) -> Void

        @State private var frames: [Int: CGRect] = [:]
        @State private var dropIndex: Int?

        nonisolated static let space = "arrangementLane"

        var body: some View {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(draft.chips) { chip in
                    ArrangementChip(
                        chip: chip,
                        isSelected: chip.id == selection,
                        isDragging: dragging == .pass(chip.id),
                        isReadOnly: isReadOnly,
                        canAppend: draft.chips.count < SlotArrangement.maxPasses,
                        count: draft.chips.count,
                        select: { select(chip.id) },
                        perform: perform,
                    )
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.space))
                    } action: { frames[chip.id] = $0 }
                    .onDrag {
                        dragging = .pass(chip.id)
                        return NSItemProvider(object: ArrangementDrag.pass(chip.id)
                            .payload as NSString)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(12)
            .coordinateSpace(.named(Self.space))
            .overlay(alignment: .topLeading) { insertionMark }
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Theme.color.lineStrong,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3]),
                    )
            }
            .onDrop(of: [.text], delegate: LaneDropDelegate(
                isEnabled: !isReadOnly,
                dragging: $dragging,
                dropIndex: $dropIndex,
                index: dropIndex(at:),
                drop: drop,
            ))
        }

        /// 3 pt wide, the chip's height, 6 pt left of the target chip (3 pt right of the last).
        @ViewBuilder private var insertionMark: some View {
            if let dropIndex, let rect = markRect(dropIndex) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.color.cue)
                    .frame(width: 3, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }

        private func markRect(_ index: Int) -> CGRect? {
            if let target = frames[index], index < draft.chips.count {
                return CGRect(x: target.minX - 6, y: target.minY, width: 3, height: target.height)
            }
            guard let last = frames[draft.chips.count - 1] else { return nil }
            return CGRect(x: last.maxX + 3, y: last.minY, width: 3, height: last.height)
        }

        /// The first chip whose bottom is below the pointer and that the pointer is above or
        /// left of the middle of; else the end.
        private func dropIndex(at point: CGPoint) -> Int {
            let location = point
            for index in draft.chips.indices {
                guard let rect = frames[index] else { continue }
                if location.y < rect.maxY, location.y < rect.minY || location.x < rect.midX {
                    return index
                }
            }
            return draft.chips.count
        }

        private func drop(_ item: ArrangementDrag, at index: Int, copying: Bool) {
            switch item {
            case let .part(unit):
                perform(.insert(unit: unit, at: index))
            case let .pass(from):
                perform(copying ? .copy(from, to: index) : .move(from: from, to: index))
            }
        }
    }

    /// The lane's drop target: tracks the drop index for the insertion mark; dropping outside
    /// the lane does nothing.
    private struct LaneDropDelegate: DropDelegate {
        let isEnabled: Bool
        @Binding var dragging: ArrangementDrag?
        @Binding var dropIndex: Int?
        let index: (CGPoint) -> Int
        let drop: (ArrangementDrag, Int, Bool) -> Void

        func validateDrop(info _: DropInfo) -> Bool {
            isEnabled && dragging != nil
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            guard isEnabled, dragging != nil else { return DropProposal(operation: .forbidden) }
            dropIndex = index(info.location)
            let copying = NSEvent.modifierFlags.contains(.option) || dragging.isPart
            return DropProposal(operation: copying ? .copy : .move)
        }

        func dropExited(info _: DropInfo) {
            dropIndex = nil
        }

        func performDrop(info: DropInfo) -> Bool {
            defer {
                dropIndex = nil
                dragging = nil
            }
            guard isEnabled, let item = dragging else { return false }
            drop(item, index(info.location), NSEvent.modifierFlags.contains(.option))
            return true
        }
    }

    private extension ArrangementDrag? {
        var isPart: Bool {
            if case .part = self {
                return true
            }
            return false
        }
    }

    /// One pass (P8-3 section 6.3): position, title, pass number, mode tag; hover + and ×.
    struct ArrangementChip: View {
        let chip: ArrangementDraft.Chip
        let isSelected: Bool
        let isDragging: Bool
        let isReadOnly: Bool
        let canAppend: Bool
        /// Passes in the lane.
        let count: Int
        let select: () -> Void
        let perform: (ArrangementDraft.Edit) -> Void
        @State private var isHovered = false

        private var isFirst: Bool {
            chip.id == 0
        }

        private var isLast: Bool {
            chip.id == count - 1
        }

        private var isSkipped: Bool {
            chip.mode == .skip
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(chip.id + 1)")
                    .font(SchibstedGrotesk.bold.font(size: 10))
                    .foregroundStyle(Theme.color.indicatorOff)
                Text(chip.title)
                    .font(SchibstedGrotesk.bold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                    .strikethrough(isSkipped, color: Theme.color.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(isSkipped ? " " : chip.number ?? " ")
                    .font(SchibstedGrotesk.semiBold.font(size: 11))
                    .foregroundStyle(Theme.color.muted)
                Spacer(minLength: 0)
                Text(Self.modeTag(chip.mode))
                    .font(SchibstedGrotesk.bold.font(size: 10))
                    .tracking(0.06 * 10)
                    .foregroundStyle(Theme.color.muted)
            }
            .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 9))
            .frame(width: 108, height: 74, alignment: .topLeading)
            .background(isSkipped ? Color.clear : Theme.color.surfaceAlt, in: shape)
            .overlay(alignment: .leading) { kindBar }
            .overlay {
                shape.strokeBorder(
                    Theme.color.controlBorder,
                    style: StrokeStyle(lineWidth: 1, dash: isSkipped ? [4, 3] : []),
                )
            }
            .opacity(isDragging ? 0.3 : isSkipped ? 0.55 : 1)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Theme.color.ink, lineWidth: 2)
                        .padding(-2)
                }
            }
            .contentShape(shape)
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.option), !isReadOnly {
                    perform(.toggleSkip(chip.id))
                } else {
                    select()
                }
            }
            .help([chip.unit.name, chip.unit.firstLine].compactMap(\.self).joined(separator: " - "))
            .contextMenu {
                if !isReadOnly {
                    menu
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(spokenName)
            .accessibilityValue(spokenValue)
            .accessibilityAction { select() }
            .accessibilityActions {
                if !isReadOnly {
                    menu
                }
            }
            .accessibilityIdentifier(AccessibilityID.arrangementChip(chip.id))
            // After the chip's own element, so the hover buttons stay their own controls.
            .overlay(alignment: .topTrailing) { hoverButtons }
            .onHover { isHovered = $0 }
        }

        private var kindBar: some View {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 2,
                topTrailingRadius: 2,
                style: .continuous,
            )
            .fill(Color(nsColor: SectionBandStyle.dynamicColor(for: chip.unit.kind ?? .custom(""))))
            .frame(width: 3)
            .padding(.vertical, 9)
            .accessibilityHidden(true)
        }

        @ViewBuilder private var hoverButtons: some View {
            if isHovered, !isReadOnly {
                HStack(spacing: 0) {
                    Button { perform(.duplicate(chip.id)) } label: {
                        Image(systemName: "plus").frame(width: 18, height: 18)
                    }
                    .help("Duplicate (⌘D)")
                    .disabled(!canAppend)
                    .accessibilityIdentifier(AccessibilityID.arrangementChipDuplicate(chip.id))
                    Button { perform(.remove(chip.id)) } label: {
                        Image(systemName: "xmark").frame(width: 18, height: 18)
                    }
                    .help("Remove (⌫)")
                    .accessibilityIdentifier(AccessibilityID.arrangementChipRemove(chip.id))
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.color.muted)
                .padding(.top, 3)
                .padding(.trailing, 3)
            }
        }

        /// The context menu and the VoiceOver actions (every edit without dragging).
        @ViewBuilder private var menu: some View {
            ForEach([PassMode.full, .chordsOnly, .firstLine], id: \.self) { mode in
                Toggle(Self.modeTitle(mode), isOn: Binding(
                    get: { chip.mode == mode },
                    set: { _ in perform(.setMode(chip.id, mode)) },
                ))
            }
            Button(isSkipped ? "Play" : "Skip") { perform(.toggleSkip(chip.id)) }
            Divider()
            Button("Duplicate") { perform(.duplicate(chip.id)) }
                .disabled(!canAppend)
            Button("Play Again at End") { perform(.playAgainAtEnd(chip.id)) }
                .disabled(!canAppend)
            Divider()
            Button("Move Earlier") { perform(.move(from: chip.id, to: chip.id - 1)) }
                .disabled(isFirst)
            Button("Move Later") { perform(.move(from: chip.id, to: chip.id + 2)) }
                .disabled(isLast)
            Button("Move to Start") { perform(.move(from: chip.id, to: 0)) }
                .disabled(isFirst)
            Button("Move to End") { perform(.move(from: chip.id, to: count)) }
                .disabled(isLast)
            Divider()
            Button("Remove") { perform(.remove(chip.id)) }
        }

        /// "Chorus, pass 2 of 3" or "Chorus 3rd".
        private var spokenName: String {
            if let number = chip.number {
                return "\(chip.title), pass \(number)"
            }
            return chip.title
        }

        /// "Chords only, 5 of 9" / "Skipped, 3 of 9" (the lane position).
        private var spokenValue: String {
            Self.modeTitle(chip.mode) + ", \(chip.id + 1) of \(count)"
        }

        static func modeTag(_ mode: PassMode) -> String {
            switch mode {
            case .full: "FULL"
            case .chordsOnly: "CHORDS"
            case .firstLine: "1ST LINE"
            case .skip: "SKIPPED"
            }
        }

        static func modeTitle(_ mode: PassMode) -> String {
            switch mode {
            case .full: "Full"
            case .chordsOnly: "Chords Only"
            case .firstLine: "First Line Only"
            case .skip: "Skipped"
            }
        }
    }
#endif
