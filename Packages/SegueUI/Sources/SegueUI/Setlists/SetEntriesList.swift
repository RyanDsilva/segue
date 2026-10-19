#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// The set column's rows (layout a): #, title (and slot note), key after overrides,
    /// capo, length and start time. Drag a row onto another to move it before that row;
    /// drop library songs on a row (inserted before it) or on the zone below (appended).
    /// Songs already in the set are never added again. Click a row to edit its overrides
    /// and note.
    struct SetEntriesList: View {
        let setlist: Setlist
        let model: SetlistsViewModel
        let library: LibraryViewModel
        /// The row a drag hovers over (an insertion line is drawn above it).
        @State private var dropTarget: SetlistItemID?

        var body: some View {
            let timing = SetlistTiming(setlist: setlist, songs: library.song(id:))
            let repeated = setlist.repeatedEntries
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(
                        Array(setlist.entries.enumerated()),
                        id: \.element.itemId,
                    ) { offset, entry in
                        row(
                            offset: offset,
                            entry: entry,
                            timing: timing,
                            firstPosition: repeated.contains(entry.itemId)
                                ? firstPosition(of: entry.songId) : nil,
                        )
                    }
                    dropZone
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.setlistEntries)
        }

        /// The 1-based position of the first entry holding `song`.
        private func firstPosition(of song: SongID) -> Int? {
            setlist.entries.firstIndex { $0.songId == song }.map { $0 + 1 }
        }

        private func row(
            offset: Int,
            entry: SetlistEntry,
            timing: SetlistTiming,
            firstPosition: Int?,
        ) -> some View {
            SetEntryRow(
                position: offset + 1,
                entry: entry,
                repeatOf: firstPosition,
                record: library.song(id: entry.songId),
                timing: timing.items.indices.contains(offset) ? timing.items[offset] : nil,
                isReadOnly: isReadOnly,
                onChange: { updated in
                    Task { await model.updateEntry(updated, in: setlist.id) }
                },
                onRemove: { remove(IndexSet(integer: offset)) },
                onMove: isReadOnly ? nil : { delta in move(offset, by: delta) },
                isLast: offset == setlist.entries.count - 1,
            )
            .overlay(alignment: .top) {
                if dropTarget == entry.itemId {
                    Rectangle()
                        .fill(Theme.color.ink)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
            }
            .draggable(SetDragPayload.item(entry.itemId)) {
                DragPreview(title: library.song(id: entry.songId).map(SongSummary.title)
                    ?? "Missing song")
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
                ? "Drag songs here or press + in the library"
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
            .background(isHovered || isEditing ? Theme.color.surfaceAlt : Theme.color.ground)
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                if !isReadOnly {
                    isEditing = true
                }
            }
            .popover(isPresented: $isEditing, arrowEdge: .leading) {
                SetEntryEditor(entry: entry, record: record, onChange: onChange)
            }
            .contextMenu {
                Button("Edit Key, Capo and Note…") { isEditing = true }
                    .disabled(isReadOnly)
                Button("Remove from Setlist", role: .destructive, action: onRemove)
                    .disabled(isReadOnly)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(repeatOf.map { "\(position). \(title), also at \($0)" }
                ?? "\(position). \(title)")
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
