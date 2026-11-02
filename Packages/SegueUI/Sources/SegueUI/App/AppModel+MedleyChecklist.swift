#if os(macOS)
    import Library
    import Setlists

    /// The pre-show checklist's missing songs, named by file (R188, R191).
    extension AppModel {
        /// Each missing song named by its slot and file name (saved in the setlist, else as
        /// this run saw it): "2: harbor-lights.cho is missing"; a medley member also by its
        /// medley (its saved title, else "Medley"): "Love medley, 4b: tum-hi-ho.cho is
        /// missing".
        static func missingSongs(
            _ slots: [SongSlotRef],
            labels: [String],
            in setlist: Setlist,
            library: LibraryViewModel,
        ) -> [String] {
            zip(slots, labels).compactMap { slot, label in
                guard let song = slot.songId else { return nil }
                let file = slot.fileName ?? library.knownFileNames[song] ?? "its song"
                guard let medleyId = slot.medleyId,
                      let medley = setlist.entry(medleyId)?.medley
                else { return "\(label): \(file) is missing" }
                return "\(medley.displayTitle), \(label): \(file) is missing"
            }
        }

        /// `missingSongs` for the checklist's missing (slot, label) pairs.
        static func missingSongs(
            _ missing: [(slot: SongSlotRef, label: String)],
            in setlist: Setlist,
            _ library: LibraryViewModel,
        ) -> [String] {
            missingSongs(
                missing.map(\.slot),
                labels: missing.map(\.label),
                in: setlist,
                library: library,
            )
        }
    }
#endif
