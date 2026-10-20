#if os(macOS)
    import AppKit
    import ChordPro
    import Library
    import LiveLayout
    import Setlists
    import SwiftUI

    /// "Arrange Sections" (P3-16, R122, R123 design B): which parts of the song this slot
    /// plays for this gig, in which order and how many times, with a live miniature of the
    /// stage. Each change saves at once as one undo step; the `.cho` is never changed.
    /// Opened from the slot popover's Arrangement row, the slot context menu and Setlist >
    /// Arrange Sections....
    struct ArrangementEditorSheet: View {
        let slot: ArrangingSlot
        let model: SetlistsViewModel
        let library: LibraryViewModel
        @Environment(\.dismiss) private var dismiss
        @State private var focusedRow: Int?

        var body: some View {
            Group {
                if let setlist = model.setlist(slot.setlist),
                   let entry = setlist.entry(slot.item),
                   let songID = entry.songId,
                   let record = library.song(id: songID)
                {
                    let units = SongSections.units(of: record.document)
                    ArrangementEditorContent(
                        entry: entry,
                        record: record,
                        units: units,
                        draft: ArrangementDraft(arrangement: entry.arrangement, units: units),
                        isReadOnly: setlist.readOnly != nil,
                        focusedRow: $focusedRow,
                        save: { arrangement, name in
                            Task {
                                await model.setArrangement(
                                    arrangement,
                                    of: slot.item,
                                    in: slot.setlist,
                                    actionName: name,
                                )
                            }
                        },
                        done: { dismiss() },
                    )
                } else {
                    VStack(spacing: 14) {
                        Text("This song is no longer in the set or the library.")
                            .foregroundStyle(Theme.color.muted)
                        Button("Done") { dismiss() }
                            .buttonStyle(.seguePrimary)
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(32)
                }
            }
            .accessibilityIdentifier(AccessibilityID.arrangementSheet)
        }
    }

    private struct ArrangementEditorContent: View {
        let entry: SetlistEntry
        let record: SongRecord
        let units: [SongSectionUnit]
        let draft: ArrangementDraft
        let isReadOnly: Bool
        @Binding var focusedRow: Int?
        /// Saves an arrangement (nil = full song) under an undo name.
        let save: (SlotArrangement?, String) -> Void
        let done: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                header
                if !draft.missing.isEmpty {
                    missingBanner
                }
                Rule()
                HStack(spacing: 0) {
                    rowList
                        .frame(width: 470)
                    Rule(axis: .vertical)
                    ArrangementPreview(entry: entry, record: record, order: draft.order)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Rule()
                footer
            }
            .frame(width: 920, height: 640)
            .background(Theme.color.ground)
        }

        // MARK: Header

        private var header: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Arrange Sections")
                    .font(SchibstedGrotesk.extraBold.font(size: 17))
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("\(SongSummary.title(record)) · this gig only, the song is not changed")
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                Spacer()
                Text(draft.isCustom
                    ? "\(draft.playedCount) of \(draft.partCount) sections play"
                    : "Full song")
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }

        private var missingBanner: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.color.cueText)
                    .accessibilityHidden(true)
                Text("""
                Out of date: no longer in the song: \(draft.missingNames). \
                The stage shows the full song until you update.
                """)
                .font(SchibstedGrotesk.medium.font(size: 13))
                .foregroundStyle(Theme.color.cueText)
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Update") { save(draft.arrangement, "Update Arrangement") }
                    .buttonStyle(.segueSecondary)
                    .disabled(isReadOnly)
                    .help("Keep the choices that still match the song and drop the rest")
                    .accessibilityIdentifier(AccessibilityID.arrangementUpdate)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.color.cue.opacity(0.08))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.arrangementMissing)
        }

        // MARK: Rows

        private var rowList: some View {
            let listed = draft.rows.filter { !$0.isNew }
            let new = draft.rows.filter(\.isNew)
            return VStack(spacing: 0) {
                List(selection: $focusedRow) {
                    Section {
                        ForEach(listed) { row in
                            rowView(row).tag(row.id)
                        }
                        .onMove { source, destination in
                            edit("Move Section") { draft in
                                draft.move(fromOffsets: source, toOffset: destination)
                            }
                        }
                    }
                    if !new.isEmpty {
                        Section("New in the song") {
                            ForEach(new) { row in
                                rowView(row).tag(row.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .onKeyPress(keys: [.space, .upArrow, .downArrow, "+", "=", "-", "d"]) { press in
                    keyPress(press)
                }
                Text("Space plays or skips · ⌥↑ ⌥↓ move · − + play count · ⌘D play again later")
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }

        private func rowView(_ row: ArrangementDraft.Row) -> some View {
            ArrangementRowView(
                row: row,
                isFocused: focusedRow == row.id,
                isReadOnly: isReadOnly,
                canSkip: draft.canToggleOff(row.id),
                isFirst: row.id == 0,
                isLast: row.id == draft.rows.count - 1,
                toggle: {
                    edit(row.isPlayed ? "Skip Section" : "Play Section") { $0.toggle(row.id) }
                },
                setPlays: { plays in edit("Change Play Count") { $0.setPlays(row.id, plays) } },
                move: { delta in edit("Move Section") { $0.move(row.id, by: delta) } },
                playAgain: {
                    edit("Play Again Later") { draft in
                        draft.playAgainLater(row.id)
                        return true
                    }
                },
            )
        }

        private func keyPress(_ press: KeyPress) -> KeyPress.Result {
            guard let index = focusedRow, draft.rows.indices.contains(index), !isReadOnly else {
                return .ignored
            }
            let row = draft.rows[index]
            switch press.key {
            case .space:
                edit(row.isPlayed ? "Skip Section" : "Play Section") { $0.toggle(index) }
            case .downArrow, .upArrow:
                guard press.modifiers.contains(.option) else { return .ignored }
                let delta = press.key == .upArrow ? -1 : 1
                edit("Move Section") { $0.move(index, by: delta) }
                focusedRow = min(max(index + delta, 0), draft.rows.count - 1)
            case "+", "=":
                edit("Change Play Count") { $0.setPlays(index, max(row.plays, 0) + 1) }
            case "-":
                edit("Change Play Count") { $0.setPlays(index, row.plays - 1) }
            case "d":
                guard press.modifiers.contains(.command) else { return .ignored }
                edit("Play Again Later") { draft in
                    draft.playAgainLater(index)
                    return true
                }
            default:
                return .ignored
            }
            return .handled
        }

        /// Applies `change` to the current rows and saves the result when it changed.
        private func edit(_ name: String, _ change: (inout ArrangementDraft) -> Bool) {
            guard !isReadOnly else { return }
            var next = draft
            guard change(&next) else { return }
            save(next.arrangement, name)
        }

        // MARK: Footer

        private var footer: some View {
            HStack(spacing: 10) {
                Text("Length for this gig")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                LengthField(target: .slot(entry.itemId), length: draft.length) { seconds in
                    var next = draft
                    next.length = seconds
                    save(next.arrangement, "Set Slot Length")
                }
                .disabled(isReadOnly)
                .accessibilityIdentifier(AccessibilityID.arrangementLength)
                Text(songLengthHint)
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .help("The song's own length stays in the song; this slot has its own.")
                Spacer()
                Button("Reset to Full Song") { save(nil, "Reset to Full Song") }
                    .buttonStyle(.segueSecondary)
                    .disabled(!draft.isCustom || isReadOnly)
                    .accessibilityIdentifier(AccessibilityID.arrangementReset)
                Button("Done", action: done)
                    .buttonStyle(.seguePrimary)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AccessibilityID.arrangementDone)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }

        private var songLengthHint: String {
            let song = record.document.metadata.duration.flatMap { $0 > 0 ? $0 : nil }
            return "Song: " + (song.map { SetlistTiming.format($0) } ?? "no length")
        }
    }

    /// One part: checkbox, kind colour, name (ordinal when the title repeats), first line,
    /// and the play count.
    private struct ArrangementRowView: View {
        let row: ArrangementDraft.Row
        let isFocused: Bool
        let isReadOnly: Bool
        let canSkip: Bool
        let isFirst: Bool
        let isLast: Bool
        let toggle: () -> Void
        let setPlays: (Int) -> Void
        let move: (Int) -> Void
        let playAgain: () -> Void
        @State private var isHovered = false

        var body: some View {
            HStack(spacing: 9) {
                Toggle(isOn: Binding(get: { row.isPlayed }, set: { _ in toggle() })) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(isReadOnly || (row.isPlayed && !canSkip))
                .help(row.isPlayed && !canSkip ? "At least one section plays" : "")
                .accessibilityLabel(row.isPlayed ? "Playing" : "Skipped")
                .accessibilityIdentifier(AccessibilityID.arrangementPlay(row.id))
                RoundedRectangle(cornerRadius: 2)
                    .fill(kindColor)
                    .frame(width: 4, height: 18)
                    .opacity(row.isPlayed ? 1 : 0.35)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(row.unit.title)
                        .font(SchibstedGrotesk.semiBold.font(size: 14))
                        .foregroundStyle(row.isPlayed ? Theme.color.ink : Theme.color.muted)
                        .strikethrough(!row.isPlayed, color: Theme.color.muted)
                    if let ordinal = row.unit.ordinal {
                        Text(ordinal)
                            .font(SchibstedGrotesk.medium.font(size: 12))
                            .foregroundStyle(Theme.color.muted)
                    }
                    if row.isAgain {
                        Text("again")
                            .font(SchibstedGrotesk.medium.font(size: 12))
                            .foregroundStyle(Theme.color.muted)
                    }
                }
                .fixedSize()
                Text(row.unit.firstLine ?? "")
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(row.isPlayed ? 1 : 0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if row.plays > 1 || ((isFocused || isHovered) && row.isPlayed) {
                    stepper
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .contextMenu {
                Button(row.isPlayed ? "Skip" : "Play", action: toggle)
                    .disabled(isReadOnly || (row.isPlayed && !canSkip))
                Button("Play Again Later", action: playAgain)
                    .disabled(isReadOnly)
                Divider()
                Button("Move Up") { move(-1) }
                    .disabled(isReadOnly || isFirst)
                Button("Move Down") { move(1) }
                    .disabled(isReadOnly || isLast)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(spokenName)
            .accessibilityValue(spokenState)
            .accessibilityIdentifier(AccessibilityID.arrangementRow(row.id))
            .accessibilityActions {
                if !isReadOnly {
                    Button(row.isPlayed ? "Skip" : "Play", action: toggle)
                    if row.isPlayed {
                        Button("Play once more") { setPlays(row.plays + 1) }
                        if row.plays > 1 {
                            Button("Play once less") { setPlays(row.plays - 1) }
                        }
                    }
                    Button("Play Again Later", action: playAgain)
                    if !isFirst {
                        Button("Move up") { move(-1) }
                    }
                    if !isLast {
                        Button("Move down") { move(1) }
                    }
                }
            }
        }

        private var stepper: some View {
            HStack(spacing: 0) {
                Button { setPlays(row.plays - 1) } label: {
                    Image(systemName: "minus").frame(width: 18, height: 18)
                }
                .disabled(isReadOnly || row.plays <= 1)
                .accessibilityLabel("Play once less")
                .accessibilityIdentifier(AccessibilityID.arrangementCountDown(row.id))
                Text("x\(row.plays)")
                    .font(SchibstedGrotesk.bold.font(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.color.ink)
                    .frame(minWidth: 22)
                    .accessibilityIdentifier(AccessibilityID.arrangementCount(row.id))
                Button { setPlays(row.plays + 1) } label: {
                    Image(systemName: "plus").frame(width: 18, height: 18)
                }
                .disabled(isReadOnly || row.plays >= SlotArrangement.maxPlays)
                .accessibilityLabel("Play once more")
                .accessibilityIdentifier(AccessibilityID.arrangementCountUp(row.id))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.color.muted)
            .padding(.horizontal, 4)
            .frame(height: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        row.plays > 1 ? Theme.color.ink.opacity(0.55) : Theme.color.controlBorder,
                        lineWidth: 1,
                    )
            }
        }

        private var kindColor: Color {
            guard let kind = row.unit.kind else { return Theme.color.muted }
            return Color(nsColor: SectionBandStyle.dynamicColor(for: kind))
        }

        private var spokenName: String {
            row.isAgain ? "\(row.unit.name), again" : row.unit.name
        }

        private var spokenState: String {
            switch row.plays {
            case 0: "skipped"
            case 1: "playing"
            case 2: "playing twice"
            default: "playing \(row.plays) times"
            }
        }
    }

    /// The song as the stage will lay it out with this arrangement, scaled down: the real
    /// layout engine and stage faces at a 1024 x 640 stage.
    private struct ArrangementPreview: View {
        let entry: SetlistEntry
        let record: SongRecord
        let order: [PlayedSection]

        private static let stage = LayoutSize(width: 1024, height: 640)

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("On stage")
                    .font(SchibstedGrotesk.bold.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                GeometryReader { proxy in
                    let plan = plan
                    let scale = min(proxy.size.width / Self.stage.width, 1)
                    ScrollView(.vertical) {
                        StagePlanView(plan: plan)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(
                                width: plan.viewport.width * scale,
                                height: max(plan.contentHeight, 1) * scale,
                                alignment: .topLeading,
                            )
                            .padding(12)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10).fill(Theme.color.ground),
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.color.line)
                    }
                }
            }
            .padding(14)
            .background(Theme.color.surfaceAlt)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stage preview")
            .accessibilityValue(order.isEmpty ? "Nothing plays" : "\(order.count) sections")
            .accessibilityIdentifier(AccessibilityID.arrangementPreview)
        }

        private var plan: LayoutPlan {
            let prefs = record.sidecar.live
            let request = LayoutRequest(
                model: LiveSession.renderModel(record, overrides: entry.overrides),
                viewport: Self.stage,
                minLyricSize: 22,
                collapseRepeats: prefs.collapseRepeats,
                columns: prefs.columns,
                cues: record.sidecar.cues,
                arrangement: order.isEmpty ? nil : order,
            )
            return LayoutEngine.plan(request, metrics: StageTextMetrics())
        }
    }
#endif
