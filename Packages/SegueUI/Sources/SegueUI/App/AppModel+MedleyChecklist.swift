#if os(macOS)
    import Library
    import Setlists

    /// The pre-show checklist's missing medley members (R188).
    extension AppModel {
        /// Missing medley members, named with their medley (its saved title, else "Medley"),
        /// their slot and the song's file name when this run saw it (R188): "Love medley,
        /// 4b: tum-hi-ho.cho is missing".
        static func missingMembers(
            _ slots: [SongSlotRef],
            labels: [String],
            in setlist: Setlist,
            library: LibraryViewModel,
        ) -> [String] {
            zip(slots, labels).compactMap { slot, label in
                guard let medleyId = slot.medleyId,
                      let medley = setlist.entry(medleyId)?.medley,
                      let song = slot.songId
                else { return nil }
                let file = library.knownFileNames[song] ?? "its song"
                return "\(medley.displayTitle), \(label): \(file) is missing"
            }
        }

        /// `missingMembers` for the checklist's missing (slot, label) pairs.
        static func missingMembers(
            _ missing: [(slot: SongSlotRef, label: String)],
            in setlist: Setlist,
            _ library: LibraryViewModel,
        ) -> [String] {
            missingMembers(
                missing.map(\.slot),
                labels: missing.map(\.label),
                in: setlist,
                library: library,
            )
        }
    }
#endif
