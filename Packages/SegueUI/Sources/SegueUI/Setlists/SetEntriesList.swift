#if os(macOS)
    import AppKit
    import Library
    import Setlists
    import SwiftUI

    extension FocusedValues {
        /// True while the builder's set list has keyboard focus (Setlist > Move Up / Move
        /// Down act only then).
        @Entry var arrangeListFocused: Bool?
    }

    /// The set column's rows (direction C): #, title (and slot note), key after overrides,
    /// capo, length and start time, each with its part's colour on the leading edge; break
    /// rows are markers with the part's total. Drag a row onto another to move it before
    /// that row; drop library songs on a row (inserted before it) or on the zone below
    /// (appended). Songs already in the set are never added again. Click a row to select it
    /// and edit it (⌘-click and ⇧-click select several without editing); ⌥↑ / ⌥↓ move the
    /// selected rows, ↑ / ↓ move the selection.
    struct SetEntriesList: View {
        let setlist: Setlist
        let model: SetlistsViewModel
        let library: LibraryViewModel
        /// The row a drag hovers over (an insertion line is drawn above it).
        @State private var dropTarget: SetlistItemID?
        @AppStorage(ChangeoverSetting.defaultsKey) private var defaultChangeover = 0
        @FocusState private var listFocused: Bool

        var body: some View {
            let timing = SetlistTiming(
                setlist: setlist,
                songs: library.song(id:),
                defaultChangeover: defaultChangeover,
            )
            let repeated = setlist.repeatedEntries
            let positions = songPositions
            let parts = partIndexes(setlist.entries)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(setlist.entries.enumerated()),
                            id: \.element.itemId,
                        ) { offset, entry in
                            row(
                                offset: offset,
                                place: Place(position: positions[offset], part: parts[offset]),
                                entry: entry,
                                timing: timing,
                                firstPosition: repeated.contains(entry.itemId)
                                    ? entry.songId.flatMap(firstPosition(of:)) : nil,
                            )
                            .id(entry.itemId)
                        }
                        dropZone
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .focusedValue(\.arrangeListFocused, listFocused ? true : nil)
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    keyMove(press, proxy: proxy)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.setlistEntries)
        }

        private var order: [SetlistItemID] {
            setlist.entries.map(\.itemId)
        }

        /// ↑ / ↓ move the selection (⇧ extends it); ⌥ moves the selected rows, for when the
        /// menu item is not reached first.
        private func keyMove(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
            let delta = press.key == .upArrow ? -1 : 1
            if press.modifiers.contains(.option) {
                guard !isReadOnly else { return .ignored }
                Task { await model.moveSelection(in: setlist.id, by: delta) }
                return .handled
            }
            guard !order.isEmpty else { return .ignored }
            model.arrangeSelection.move(
                delta,
                in: order,
                extending: press.modifiers.contains(.shift),
            )
            if let focus = model.arrangeSelection.focus {
                proxy.scrollTo(focus)
            }
            return .handled
        }

        /// A click: plain selects the row (and the caller opens its editor); ⌘ toggles it
        /// and ⇧ extends to it. Returns whether it was a plain click.
        private func select(_ id: SetlistItemID) -> Bool {
            listFocused = true
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                model.arrangeSelection.toggle(id, in: order)
                return false
            }
            if flags.contains(.shift) {
                model.arrangeSelection.extend(to: id, in: order)
                return false
            }
            model.arrangeSelection.select(id)
            return true
        }

        /// Each entry's 1-based song number: break rows are not numbered, so the songs
        /// count 1 ... n across parts (nil for a break).
        private var songPositions: [Int?] {
            var count = 0
            return setlist.entries.map { entry in
                guard !entry.isBreak else { return nil }
                count += 1
                return count
            }
        }

        /// The song number of the first entry holding `song`.
        private func firstPosition(of song: SongID) -> Int? {
            guard let index = setlist.entries.firstIndex(where: { $0.songId == song }) else {
                return nil
            }
            return songPositions[index]
        }

        /// Where a row sits: its song number (nil for a break) and its part.
        private struct Place {
            var position: Int?
            var part: Int
        }

        @ViewBuilder
        private func row(
            offset: Int,
            place: Place,
            entry: SetlistEntry,
            timing: SetlistTiming,
            firstPosition: Int?,
        ) -> some View {
            if let info = entry.breakInfo {
                breakRow(offset: offset, part: place.part, entry: entry, info: info, timing: timing)
            } else {
                let record = entry.songId.flatMap(library.song(id:))
                dragDrop(
                    SetEntryRow(
                        position: place.position ?? offset + 1,
                        part: place.part,
                        isSelected: model.arrangeSelection.contains(entry.itemId),
                        onSelect: { select(entry.itemId) },
                        onInsertBreak: isReadOnly ? nil : {
                            model.arrangeSelection.select(entry.itemId)
                            Task { await model.insertBreak(in: setlist.id) }
                        },
                        entry: entry,
                        repeatOf: firstPosition,
                        record: record,
                        timing: timing.items.indices.contains(offset) ? timing.items[offset] : nil,
                        isReadOnly: isReadOnly,
                        onChange: { updated in
                            Task { await model.updateEntry(updated, in: setlist.id) }
                        },
                        onRemove: { remove(IndexSet(integer: offset)) },
                        onMove: isReadOnly ? nil : { delta in move(offset, by: delta) },
                        isLast: offset == setlist.entries.count - 1,
                    ),
                    offset: offset,
                    entry: entry,
                    title: record.map(SongSummary.title) ?? "Missing song",
                )
            }
        }

        private func breakRow(
            offset: Int,
            part: Int,
            entry: SetlistEntry,
            info: SetlistBreak,
            timing: SetlistTiming,
        ) -> some View {
            dragDrop(
                SetBreakRow(
                    entry: entry,
                    info: info,
                    part: part,
                    timing: timing.part(openedBy: entry.itemId),
                    changeoverNote: timing.changeoverNote,
                    setlist: setlist,
                    library: library,
                    isSelected: model.arrangeSelection.contains(entry.itemId),
                    isReadOnly: isReadOnly,
                    onSelect: { select(entry.itemId) },
                    onChange: { updated in
                        Task { await model.updateBreak(updated, in: setlist.id) }
                    },
                    onRemove: { remove(IndexSet(integer: offset)) },
                ),
                offset: offset,
                entry: entry,
                title: info.label,
            )
        }

        /// The insertion line, drag source and drop target every row shares.
        private func dragDrop(
            _ content: some View,
            offset: Int,
            entry: SetlistEntry,
            title: String,
        ) -> some View {
            content.overlay(alignment: .top) {
                if dropTarget == entry.itemId {
                    Rectangle()
                        .fill(Theme.color.ink)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
            }
            .draggable(SetDragPayload.item(entry.itemId)) {
                DragPreview(title: title)
            }
            .dropDestination(for: String.self) { items, _ in
                drop(items, before: offset)
            } isTargeted: { isTargeted in
                if isTargeted {
                    dropTarget = entry.itemId
                } else if dropTarget == entry.itemId {
                    dropTarget = nil
                }
            }
        }

        /// Library songs are inserted before row `offset`; a dragged row moves there.
        private func drop(_ items: [String], before offset: Int?) -> Bool {
            dropTarget = nil
            guard !isReadOnly else { return false }
            let dragged = items.compactMap(SongDragPayload.decode)
            if !dragged.isEmpty {
                // A song already in the set is never added again (its library row does not
                // drag; this guards drags from elsewhere).
                let songs = dragged.filter { !setlist.contains($0) }
                guard !songs.isEmpty else { return false }
                Task { await model.insert(songs, into: setlist.id, at: offset) }
                return true
            }
            guard let moved = items.compactMap(SetDragPayload.decodeItem).first,
                  let from = setlist.entries.firstIndex(where: { $0.itemId == moved })
            else { return false }
            let destination = offset ?? setlist.entries.count
            guard destination != from, destination != from + 1 else { return true }
            Task {
                await model.move(
                    in: setlist.id,
                    fromOffsets: IndexSet(integer: from),
                    toOffset: destination,
                )
            }
            return true
        }

        private var isReadOnly: Bool {
            setlist.readOnly != nil
        }

        /// "Drag songs here or press + in the library"; drops append.
        private var dropZone: some View {
            Text(setlist.entries.isEmpty
                ? "Tick songs in Pick, or drag them here"
                : "Drag more songs here")
                .font(SchibstedGrotesk.medium.font(size: 14))
                .foregroundStyle(Theme.color.muted)
                .frame(maxWidth: .infinity)
                .padding(12)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            Theme.color.lineStrong,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]),
                        )
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
                    drop(items, before: nil)
                }
                .accessibilityIdentifier(AccessibilityID.setlistDropZone)
        }

        /// "Move up" / "Move down" (accessibility actions): one place, no drag needed.
        private func move(_ offset: Int, by delta: Int) {
            let target = offset + delta
            guard setlist.entries.indices.contains(target) else { return }
            let destination = delta < 0 ? target : target + 1
            Task {
                await model.move(
                    in: setlist.id,
                    fromOffsets: IndexSet(integer: offset),
                    toOffset: destination,
                )
            }
        }

        private func remove(_ offsets: IndexSet) {
            guard !offsets.isEmpty, !isReadOnly else { return }
            Task { await model.remove(in: setlist.id, atOffsets: offsets) }
        }
    }

    /// One slot: `#  Title  Key  Capo  Length  Start`, the note under the title.
    private struct SetEntryRow: View {
        let position: Int
        /// The part the row is in (its leading-edge colour).
        let part: Int
        let isSelected: Bool
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
        let onRemove: () -> Void
        /// Moves the slot one place (-1 up, +1 down); nil when the setlist is read-only.
        var onMove: ((Int) -> Void)?
        var isLast = false
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
                SetEntryEditor(entry: entry, record: record, onChange: onChange)
            }
            .contextMenu {
                Button("Edit Key, Capo and Note…") { isEditing = true }
                    .disabled(isReadOnly)
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
                } else if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                        .accessibilityIdentifier(AccessibilityID.entryNote)
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
