#if os(macOS)
    import AppKit
    import Library
    import Setlists
    import SwiftUI

    /// Medley rows in the set list (P9-3 6.1-6.3): the group card, keys on its header, and
    /// drops onto its member area.
    extension SetEntriesList {
        func medleyRow(
            offset: Int,
            place: Place,
            entry: SetlistEntry,
            medley: SetlistMedley,
            timing: SetlistTiming,
        ) -> some View {
            dragDrop(
                MedleyRow(
                    entry: entry,
                    medley: medley,
                    number: place.position ?? offset + 1,
                    part: place.part,
                    setlist: setlist,
                    model: model,
                    library: library,
                    timing: timing.items.indices.contains(offset) ? timing.items[offset] : nil,
                    isReadOnly: isReadOnly,
                    assistant: EntryAssistant(isLocked: true, lockHelp: Self.medleyLockHelp),
                    onSelect: select,
                    onDropMember: { items, index in
                        dropOnMedley(items, medley: entry.itemId, at: index)
                    },
                ),
                offset: offset,
                entry: entry,
                title: medley.displayTitle,
            )
        }

        static let medleyLockHelp = "Medleys stay in place on Rebuild"

        /// Library songs or a set row dropped on a medley's member area join it at `index`
        /// (nil = the end). A library song already in a medley is refused with the
        /// composer's "already 4b" message; one that is a slot elsewhere joins as a reprise.
        func dropOnMedley(_ items: [String], medley: SetlistItemID, at index: Int?) -> Bool {
            guard !isReadOnly else { return false }
            let songs = items.compactMap(SongDragPayload.decode)
            if !songs.isEmpty {
                let refused = songs.compactMap { song -> SongOccurrence? in
                    if case let .refused(occurrence) = setlist.canAdd(
                        song,
                        as: .member(of: medley),
                    ) {
                        return occurrence
                    }
                    return nil
                }
                if let first = refused.first {
                    model.errorMessage = "That song is already \(first.label) in this set."
                    NSSound.beep()
                    return false
                }
                Task { await model.addToMedley(songs, medley: medley, at: index, in: setlist.id) }
                return true
            }
            guard let moved = items.compactMap(SetDragPayload.decodeItem).first,
                  moved != medley
            else { return false }
            if let (entry, from) = setlist.member(moved) {
                // A member dropped within its own medley moves there.
                guard entry.itemId == medley, let index else { return false }
                let target = index > from ? index - 1 : index
                guard target != from else { return true }
                Task {
                    _ = await model.moveMember(moved, by: target - from, in: setlist.id)
                }
                return true
            }
            guard let slot = setlist.entry(moved), slot.songId != nil else {
                NSSound.beep()
                return false
            }
            Task { await model.moveIntoMedley(moved, medley: medley, at: index, in: setlist.id) }
            return true
        }

        /// ← / → collapse and expand the selected medley header; Return renames it; ⌫
        /// removes the selected member (or row).
        func medleyKey(_ press: KeyPress) -> KeyPress.Result {
            guard let focus = model.arrangeSelection.focus,
                  model.arrangeSelection.count == 1
            else { return .ignored }
            let header = setlist.entry(focus)?.isMedley == true
            switch press.key {
            case .leftArrow where header:
                model.setCollapsed(focus, true)
            case .rightArrow where header:
                model.setCollapsed(focus, false)
            case .return where header && !isReadOnly:
                model.renamingMedley = focus
            case .delete where !isReadOnly:
                if setlist.member(focus) != nil {
                    Task { await model.removeMember(focus, in: setlist.id) }
                } else if let index = setlist.entries.firstIndex(where: { $0.itemId == focus }) {
                    Task { await model.remove(in: setlist.id, atOffsets: IndexSet(integer: index)) }
                } else {
                    return .ignored
                }
            default:
                return .ignored
            }
            return .handled
        }
    }
#endif

#if os(macOS)
    extension SetEntriesList {
        /// "Make Medley from 3 Songs" on a selected row whose selection can become a medley.
        func makeMedleyItem(for item: SetlistItemID) -> MakeMedleyItem? {
            guard model.arrangeSelection.contains(item),
                  model.medleyCandidates(in: setlist.id) != nil
            else { return nil }
            return MakeMedleyItem(songs: model.medleyCandidateSongCount(in: setlist.id)) {
                Task { await model.makeMedley(in: setlist.id) }
            }
        }
    }
#endif
