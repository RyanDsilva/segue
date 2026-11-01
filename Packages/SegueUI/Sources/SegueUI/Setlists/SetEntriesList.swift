#if os(macOS)
    import AppKit
    import Library
    import SetAssistant
    import Setlists
    import SwiftUI

    extension FocusedValues {
        /// True while the builder's set list has keyboard focus (Setlist > Move Up / Move
        /// Down act only then).
        @Entry var arrangeListFocused: Bool?
    }

    /// The set column's rows (direction C): #, title (and slot note), key after overrides,
    /// capo, time and start time, each with its part's colour on the leading edge; break
    /// rows are markers with the part's total. Drag a row onto another to move it before
    /// that row; drop library songs on a row (inserted before it) or on the set composer
    /// below (appended). Songs already in the set are never added again. Click a row to
    /// select it and edit it (⌘-click and ⇧-click select several without editing); ⌥↑ / ⌥↓
    /// move the selected rows, ↑ / ↓ move the selection, ↓ on the last row goes to the
    /// composer (P8-5).
    struct SetEntriesList: View {
        let setlist: Setlist
        let model: SetlistsViewModel
        let library: LibraryViewModel
        /// The set assistant's scores per song slot (P3-7); empty before a build.
        var breakdowns: [SetlistItemID: ScoreBreakdown] = [:]
        @State private var shownBreakdown: SetlistItemID?
        /// The row a drag hovers over (an insertion line is drawn above it).
        @State private var dropTarget: SetlistItemID?
        @AppStorage(ChangeoverSetting.defaultsKey) private var defaultChangeover = 0
        @FocusState var listFocused: Bool

        var body: some View {
            let timing = SetlistTiming(
                setlist: setlist,
                library: library,
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
                            .overlay { composerHighlight(entry.itemId) }
                        }
                        composerRow(proxy: proxy)
                            .id(Self.composerID)
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .focusedValue(\.arrangeListFocused, listFocused ? true : nil)
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    keyMove(press, proxy: proxy)
                }
                .onKeyPress(.space) { toggleFocusedBreakdown($shownBreakdown) }
                .onKeyPress(keys: [.leftArrow, .rightArrow, .return, .delete]) { press in
                    medleyKey(press)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.setlistEntries)
        }

        /// The rows in order, an expanded medley's members after its header (P9-3 6.3).
        private var order: [SetlistItemID] {
            model.rowOrder(of: setlist)
        }

        /// ↑ / ↓ move the selection (⇧ extends it); ⌥ moves the selected rows, for when the
        /// menu item is not reached first.
        private func keyMove(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
            let delta = press.key == .upArrow ? -1 : 1
            if press.modifiers.contains(.option) {
                guard !isReadOnly else { return .ignored }
                // A member moves within its medley and never leaves it (a beep at its edge).
                if let member = model.selectedMember(in: setlist.id) {
                    Task {
                        if await !model.moveMember(member, by: delta, in: setlist.id) {
                            NSSound.beep()
                        }
                    }
                    return .handled
                }
                Task { await model.moveSelection(in: setlist.id, by: delta) }
                return .handled
            }
            guard !order.isEmpty else { return .ignored }
            if delta > 0, !press.modifiers.contains(.shift), !isReadOnly,
               model.arrangeSelection.focus == order.last
            {
                model.composer.requestFocus()
                proxy.scrollTo(Self.composerID)
                return .handled
            }
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
        func select(_ id: SetlistItemID) -> Bool {
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
        struct Place {
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
            } else if let medley = entry.medley {
                medleyRow(
                    offset: offset,
                    place: place,
                    entry: entry,
                    medley: medley,
                    timing: timing,
                )
            } else {
                let record = entry.songId.flatMap(library.song(id:))
                dragDrop(
                    SetEntryRow(
                        position: place.position ?? offset + 1,
                        part: place.part,
                        selection: { model.arrangeSelection.contains(entry.itemId) },
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
                        onArrange: record == nil ? nil : {
                            model.openArrangement(entry.itemId, in: setlist.id)
                        },
                        onRemove: { remove(IndexSet(integer: offset)) },
                        onMove: isReadOnly ? nil : { delta in move(offset, by: delta) },
                        isLast: offset == setlist.entries.count - 1,
                        assistant: assistantCells(for: entry, shown: $shownBreakdown),
                        reprise: entry.songId.flatMap { RepriseMark.forSlot($0, in: setlist) },
                        makeMedley: makeMedleyItem(for: entry.itemId),
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
                    selection: { model.arrangeSelection.contains(entry.itemId) },
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
        func dragDrop(
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
                // A song already a slot is never added again (its library row does not drag;
                // this guards drags from elsewhere); a medley member's comes in as its reprise.
                let songs = dragged.filter { setlist.canAdd($0, as: .slot).isAllowed }
                guard !songs.isEmpty else { return false }
                Task { await model.insert(songs, into: setlist.id, at: offset) }
                return true
            }
            guard let moved = items.compactMap(SetDragPayload.decodeItem).first
            else { return false }
            // A member dragged out of its medley becomes a slot right after it (P9-3 6.3).
            if setlist.member(moved) != nil {
                Task { await model.removeFromMedley(moved, in: setlist.id) }
                return true
            }
            guard let from = setlist.entries.firstIndex(where: { $0.itemId == moved })
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

        var isReadOnly: Bool {
            setlist.readOnly != nil
        }
    }

    // MARK: - The set composer row and moves

    extension SetEntriesList {
        private static let composerID = "segue.setlist.composer.row"

        /// The set composer (P8-5): the last row, and the drop zone that appends.
        private func composerRow(proxy: ScrollViewProxy) -> some View {
            SetComposerRow(
                setlist: setlist,
                model: model,
                library: library,
                composer: model.composer,
                hasScores: !breakdowns.isEmpty,
                onDrop: { items in drop(items, before: nil) },
                onReveal: { item in
                    model.arrangeSelection.select(item)
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(item, anchor: .center) }
                    flash(item)
                },
                onAdded: { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(Self.composerID, anchor: .bottom)
                    }
                },
                onLeave: {
                    listFocused = true
                    if let last = order.last {
                        model.arrangeSelection.select(last)
                        proxy.scrollTo(last)
                    }
                },
            )
        }

        /// The brief highlight on a row the composer's duplicate block points at.
        @ViewBuilder
        private func composerHighlight(_ item: SetlistItemID) -> some View {
            if model.composer.highlighted == item {
                Rectangle()
                    .fill(Theme.color.ink.opacity(0.08))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }

        private func flash(_ item: SetlistItemID) {
            withAnimation(.easeOut(duration: 0.15)) { model.composer.highlighted = item }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                if model.composer.highlighted == item {
                    withAnimation(.easeIn(duration: 0.3)) { model.composer.highlighted = nil }
                }
            }
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
#endif
