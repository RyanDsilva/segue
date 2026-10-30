// swiftlint:disable file_length
#if os(macOS)
    import AppKit
    import ChordPro
    import Library
    import LiveLayout
    import Setlists
    import SwiftUI

    /// "Arrange Sections" (P3-16, R122, R123 design B): which parts of the song this slot plays
    /// for this gig, in which order and how many times, with a live miniature of the stage. Each
    /// change saves at once as one undo step; the `.cho` is never changed. Opened from the slot
    /// popover's Arrangement row, the slot context menu and Setlist > Arrange Sections....
    struct ArrangementEditorSheet: View {
        let slot: ArrangingSlot
        let model: SetlistsViewModel
        let library: LibraryViewModel
        @Environment(\.dismiss) private var dismiss
        @State private var focusedRow: Int?

        var body: some View {
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
                    draft: draft(entry, units),
                    isReadOnly: setlist.readOnly != nil || draft(entry, units).usesShowModes,
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

        private func draft(_ entry: SetlistEntry, _ units: [SongSectionUnit]) -> LegacyRows {
            LegacyRows(arrangement: entry.arrangement, units: units)
        }
    }

    private struct ArrangementEditorContent: View {
        let entry: SetlistEntry
        let record: SongRecord
        let units: [SongSectionUnit]
        let draft: LegacyRows
        let isReadOnly: Bool
        @Binding var focusedRow: Int?
        /// Saves an arrangement (nil = full song) under an undo name.
        let save: (SlotArrangement?, String) -> Void
        let done: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                header
                if draft.usesShowModes {
                    ShowModesBanner()
                } else if !draft.missing.isEmpty {
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
                    // On the title, not the sheet: an identifier on a container would replace
                    // every control's own.
                    .accessibilityIdentifier(AccessibilityID.arrangementSheet)
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

        private func rowView(_ row: LegacyRows.Row) -> some View {
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
        private func edit(_ name: String, _ change: (inout LegacyRows) -> Bool) {
            guard !isReadOnly else { return }
            var next = draft
            guard change(&next) else { return }
            save(next.arrangement, name)
        }

        // MARK: Footer

        private var footer: some View {
            HStack(spacing: 10) {
                GuideHelpButton(.arrangeSections)
                Text("Length for this gig")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                LengthField(target: .slot(entry.itemId), length: draft.length) { seconds in
                    var next = draft
                    next.length = seconds
                    save(next.arrangement, "Set Slot Length")
                }
                .disabled(isReadOnly)
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

    /// One part: checkbox, kind colour, name (ordinal when the title repeats), first line, count.
    private struct ArrangementRowView: View {
        let row: LegacyRows.Row
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
                .disabled(isReadOnly || row.plays >= LegacyRows.maxPlays)
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
        let order: [PlayedPass]

        private static let stage = LayoutSize(width: 1024, height: 640)

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("On stage")
                    .font(SchibstedGrotesk.bold.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                GeometryReader { proxy in
                    let plan = plan
                    let scale = min(max(proxy.size.width - 24, 1) / Self.stage.width, 1)
                    ScrollView(.vertical) {
                        // The miniature sits in an overlay so the full-size plan never
                        // widens the panel; only its scaled box takes space.
                        Color.clear
                            .frame(
                                width: plan.viewport.width * scale,
                                height: max(plan.contentHeight, 1) * scale,
                            )
                            .overlay(alignment: .topLeading) {
                                StagePlanView(plan: plan)
                                    .scaleEffect(scale, anchor: .topLeading)
                                    .frame(
                                        width: plan.viewport.width * scale,
                                        height: max(plan.contentHeight, 1) * scale,
                                        alignment: .topLeading,
                                    )
                            }
                            .clipped()
                            .padding(12)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
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
            // One spoken label: static text exposes its words as the value.
            .accessibilityLabel(
                "Stage preview, " + (order.isEmpty ? "nothing plays" : "\(order.count) sections"),
            )
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(AccessibilityID.arrangementPreview)
        }

        private var plan: LayoutPlan {
            let prefs = record.sidecar.live
            let request = LayoutRequest(
                model: StageRequest.renderModel(record, overrides: entry.overrides),
                viewport: Self.stage,
                minLyricSize: 22,
                columns: prefs.columns,
                cues: record.sidecar.cues,
                passes: order.isEmpty ? nil : order,
            )
            return LayoutEngine.plan(request, metrics: StageTextMetrics())
        }
    }

    /// Interim (until P8-3 step 5 rebuilds the sheet): the row model of the P3-16 sheet.
    ///
    /// The Arrange Sections sheet's rows (P3-16, R122, R123), derived from a slot's saved
    /// arrangement and the song as it is now. Pure: every edit returns the arrangement to save,
    /// and the sheet re-derives its rows from the saved value (so undo shows at once).
    ///
    /// Interim adapter (P8-2 section 5) until P8-3 rebuilds the sheet on passes: loading folds
    /// consecutive Full passes of one part into a row with that play count and a Skip pass into
    /// a skipped row; saving expands rows back into passes and writes `knownParts`. An
    /// arrangement using any other show mode is not loaded into rows (`usesShowModes`), so the
    /// old editor can never drop a mode.
    private struct LegacyRows: Equatable {
        /// The most times a row can be played in a row.
        static let maxPlays = 9

        struct Row: Equatable, Identifiable {
            /// Position in `rows`.
            var id: Int
            var unit: SongSectionUnit
            /// 0 = skipped.
            var plays: Int
            /// A part added to the song since the arrangement was saved ("New in the song").
            var isNew: Bool
            /// A "Play Again Later" copy: unticking removes it.
            var isAgain: Bool

            var isPlayed: Bool {
                plays > 0
            }
        }

        private(set) var rows: [Row]
        /// Saved rows that no longer match the song (out of date).
        private(set) var missing: [ArrangementPass]
        /// The saved arrangement uses Chords only or First line passes, which this editor cannot
        /// show: the sheet is read-only.
        let usesShowModes: Bool
        var length: TimeInterval?
        /// Whether the slot has a saved arrangement (else the rows are the full song).
        let isCustom: Bool
        /// The song's parts as they are now (every one is known on save).
        private let units: [SongSectionUnit]

        init(arrangement: SlotArrangement?, units: [SongSectionUnit]) {
            isCustom = arrangement != nil
            self.units = units
            length = arrangement?.length
            usesShowModes = arrangement?.passes
                .contains { $0.mode == .chordsOnly || $0.mode == .firstLine } ?? false
            guard let arrangement else {
                rows = units.enumerated().map { offset, unit in
                    Row(id: offset, unit: unit, plays: 1, isNew: false, isAgain: false)
                }
                missing = []
                return
            }
            var rows: [Row] = []
            var missing: [ArrangementPass] = []
            var listed = Set<Int>()
            var previous: ArrangementPass?
            for pass in arrangement.passes {
                defer { previous = pass }
                guard let unit = ArrangementResolver.unit(for: pass, in: units) else {
                    missing.append(pass)
                    continue
                }
                // A Full pass right after a Full pass of the same part is one more play.
                if pass.isShown, let last = previous, last.isShown, last.anchor == pass.anchor,
                   let row = rows.last, row.unit.index == unit.index,
                   row.plays < Self.maxPlays
                {
                    rows[rows.count - 1].plays += 1
                    continue
                }
                let isAgain = listed.contains(unit.index)
                if isAgain, !pass.isShown {
                    continue
                }
                listed.insert(unit.index)
                rows.append(Row(
                    id: rows.count,
                    unit: unit,
                    plays: pass.isShown ? 1 : 0,
                    isNew: false,
                    isAgain: isAgain,
                ))
            }
            // A part the arrangement knew but plays nowhere is a skipped row; only a part it
            // never knew is new.
            let known = arrangement.effectiveKnownParts
            for unit in units where !listed.contains(unit.index) {
                let isNew = !known.contains { $0.anchor.matches(unit.anchor) }
                rows.append(Row(id: rows.count, unit: unit, plays: 0, isNew: isNew, isAgain: false))
            }
            self.rows = rows
            self.missing = missing
        }

        /// The arrangement these rows describe, every pass with the song's current fingerprint:
        /// a played row is `plays` Full passes, a skipped row one Skip pass; every part of the
        /// song is known.
        var arrangement: SlotArrangement {
            SlotArrangement(
                passes: rows.flatMap { row in
                    let pass = ArrangementPass(
                        anchor: row.unit.anchor,
                        fingerprint: row.unit.fingerprint,
                        mode: row.isPlayed ? .full : .skip,
                    )
                    return Array(repeating: pass, count: max(row.plays, 1))
                },
                knownParts: KnownPart.all(units),
                length: length,
            )
        }

        var playedCount: Int {
            rows.count { $0.isPlayed && !$0.isAgain }
        }

        /// The song's parts (a "Play Again Later" copy is not another part).
        var partCount: Int {
            rows.count { !$0.isAgain }
        }

        var hasNewRows: Bool {
            rows.contains(where: \.isNew)
        }

        /// The passes the stage shows.
        var order: [PlayedPass] {
            rows.filter(\.isPlayed).flatMap { row in
                Array(repeating: PlayedPass(index: row.unit.index), count: row.plays)
            }
        }

        /// Whether row `index` can be skipped: at least one row must play.
        func canToggleOff(_ index: Int) -> Bool {
            guard rows.indices.contains(index), rows[index].isPlayed else { return false }
            return rows[index].isAgain || rows.count(where: \.isPlayed) > 1
        }

        /// Plays or skips row `index`; unticking a "Play Again Later" copy removes it. Returns
        /// false (nothing changed) when it would leave nothing to play.
        @discardableResult
        mutating func toggle(_ index: Int) -> Bool {
            guard rows.indices.contains(index) else { return false }
            if rows[index].isPlayed {
                guard canToggleOff(index) else { return false }
                if rows[index].isAgain {
                    rows.remove(at: index)
                    renumber()
                    return true
                }
                rows[index].plays = 0
            } else {
                rows[index].plays = 1
            }
            rows[index].isNew = false
            return true
        }

        /// Sets row `index` to play `plays` times in a row (1 ... 9); a skipped row is ticked.
        @discardableResult
        mutating func setPlays(_ index: Int, _ plays: Int) -> Bool {
            guard rows.indices.contains(index) else { return false }
            let clamped = min(max(plays, 1), Self.maxPlays)
            guard clamped != rows[index].plays else { return false }
            rows[index].plays = clamped
            rows[index].isNew = false
            return true
        }

        /// Moves rows (drag, ⌥↑ / ⌥↓).
        @discardableResult
        mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) -> Bool {
            let before = rows.map(\.unit.index)
            rows.move(fromOffsets: source, toOffset: destination)
            for offset in rows.indices where rows[offset].isNew {
                rows[offset].isNew = false
            }
            renumber()
            return rows.map(\.unit.index) != before
        }

        /// Moves row `index` one place up (-1) or down (+1).
        @discardableResult
        mutating func move(_ index: Int, by delta: Int) -> Bool {
            let target = index + delta
            guard rows.indices.contains(index), rows.indices.contains(target) else { return false }
            return move(
                fromOffsets: IndexSet(integer: index),
                toOffset: delta < 0 ? target : target + 1,
            )
        }

        /// "Play Again Later" (R123): a played copy of row `index` right after it, to drag
        /// anywhere.
        mutating func playAgainLater(_ index: Int) {
            guard rows.indices.contains(index) else { return }
            var copy = rows[index]
            copy.plays = 1
            copy.isNew = false
            copy.isAgain = true
            rows.insert(copy, at: index + 1)
            rows[index].isNew = false
            renumber()
        }

        private mutating func renumber() {
            for offset in rows.indices {
                rows[offset].id = offset
            }
            // The first row of a part is never a copy (after a move a copy may come first).
            var seen = Set<Int>()
            for offset in rows.indices {
                rows[offset].isAgain = !seen.insert(rows[offset].unit.index).inserted
            }
        }
    }

    extension LegacyRows {
        var missingNames: String {
            missing.map(\.anchor.summaryName).joined(separator: ", ")
        }
    }
#endif
