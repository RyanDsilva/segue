#if os(macOS)
    import Foundation
    import Library
    import Setlists
    import Support

    // WS2b 4.2: seeding the Welcome library (songs, then the demo setlist) and removing it.
    // Generic over any schema-1 manifest folder (WS5's screenshot songs reuse it).

    /// What one seed did.
    struct SeedOutcome: Equatable {
        /// The manifest's songs, in manifest order (created now or found from an earlier seed).
        var songIDs: [SongID]
        /// The demo setlist (created now or found), nil when the manifest has none.
        var setlistID: SetlistID?
        /// Songs written by this seed (0 on a repeat).
        var createdSongs: Int
    }

    /// What "Remove Welcome Songs…" would move to the Trash, and what it keeps.
    struct SeedRemovalPlan: Equatable {
        /// Seed songs whose `.cho` is still byte-identical to the bundled original.
        var songs: [SongRecord]
        /// Seed songs the user edited: kept, and listed in the confirmation.
        var edited: [SongRecord]
        /// The demo setlist, when it is still there.
        var setlist: Setlist?

        var isEmpty: Bool {
            songs.isEmpty && setlist == nil
        }

        /// "Move 4 Welcome songs and the Welcome Set setlist to the Trash?"
        var headline: String {
            let count = songs.count == 1 ? "1 Welcome song" : "\(songs.count) Welcome songs"
            switch (songs.isEmpty, setlist) {
            case let (false, setlist?):
                return "Move \(count) and the \(setlist.name) setlist to the Trash?"
            case let (true, setlist?):
                return "Move the \(setlist.name) setlist to the Trash?"
            case (_, nil):
                return "Move \(count) to the Trash?"
            }
        }

        /// "2 edited songs are kept: <titles>." or nil when none were edited.
        var keptNote: String? {
            guard !edited.isEmpty else { return nil }
            let titles = edited.map(SongSummary.title).joined(separator: ", ")
            let count = edited.count == 1
                ? "1 edited song is kept" : "\(edited.count) edited songs are kept"
            return "\(count): \(titles)."
        }
    }

    extension LibrarySession {
        /// Seeds the songs of the manifest folder, then its setlist (unless it already exists:
        /// `knownSetlistID` from an earlier seed, or a setlist with the manifest's name whose
        /// entries are all songs carrying the manifest's tag), then reloads. Idempotent.
        func seed(
            fromManifestFolder folder: URL,
            knownSetlistID: SetlistID? = nil,
        ) async throws -> SeedOutcome {
            let seeded = try await stores.library.seedSongs(fromManifestFolder: folder)
            let manifest = try SeedManifest.load(fromFolder: folder, fileSystem: stores.fileSystem)
            var setlistID: SetlistID?
            if let plan = manifest.setlist {
                let byFile = Dictionary(
                    seeded.map { ($0.file, $0.record.id) },
                    uniquingKeysWith: { first, _ in first },
                )
                setlistID = try await seedSetlist(
                    plan,
                    songsByFile: byFile,
                    tag: manifest.tag,
                    knownID: knownSetlistID,
                )
            }
            await library.reload()
            await setlists.reload()
            return SeedOutcome(
                songIDs: seeded.map(\.record.id),
                setlistID: setlistID,
                createdSongs: seeded.count(where: \.created),
            )
        }

        private func seedSetlist(
            _ plan: SeedManifest.SetlistPlan,
            songsByFile: [String: SongID],
            tag: String,
            knownID: SetlistID?,
        ) async throws -> SetlistID {
            let store = stores.setlists
            if let existing = try await existingSeedSetlist(plan, tag: tag, knownID: knownID) {
                return existing
            }
            let songIDs = plan.entries.compactMap { songsByFile[$0.song] }
            var setlist = try await store.create(name: plan.name)
            setlist = try await store.insertSongs(songIDs, into: setlist.id)
            // Matched by song, not position: a manifest song missing from the library, or
            // listed again (a song is in a setlist once), adds no entry.
            var seen: Set<SongID> = []
            for planned in plan.entries {
                guard let song = songsByFile[planned.song], seen.insert(song).inserted,
                      let entry = setlist.entries.first(where: { $0.songId == song })
                else { continue }
                var updated = entry
                updated.overrides = SetlistOverrides(
                    transpose: planned.overrides?.transpose,
                    capo: planned.overrides?.capo,
                )
                updated.note = planned.note
                if updated != entry {
                    setlist = try await store.updateEntry(updated, in: setlist.id)
                }
            }
            if let target = plan.targetDuration {
                setlist = try await store.updateDetails(
                    SetlistDetails(targetDuration: target),
                    of: setlist.id,
                )
            }
            return setlist.id
        }

        /// The demo setlist from an earlier seed, if it is still there.
        private func existingSeedSetlist(
            _ plan: SeedManifest.SetlistPlan,
            tag: String,
            knownID: SetlistID?,
        ) async throws -> SetlistID? {
            let store = stores.setlists
            if let knownID, await store.setlist(id: knownID) != nil {
                return knownID
            }
            let tagged = try await Set(stores.library.songs(taggedWith: tag).map(\.id))
            return await store.all().first { setlist in
                setlist.name == plan.name && !setlist.entries.isEmpty
                    && setlist.entries.allSatisfy { tagged.contains($0.songId) }
            }?.id
        }

        /// What removing the seed would trash and keep.
        func seedRemovalPlan(
            fromManifestFolder folder: URL,
            knownSetlistID: SetlistID?,
        ) async throws -> SeedRemovalPlan {
            let inventory = try await stores.library.seedInventory(fromManifestFolder: folder)
            let manifest = try SeedManifest.load(fromFolder: folder, fileSystem: stores.fileSystem)
            var setlist: Setlist?
            if let plan = manifest.setlist,
               let id = try await existingSeedSetlist(
                   plan,
                   tag: manifest.tag,
                   knownID: knownSetlistID,
               )
            {
                setlist = await stores.setlists.setlist(id: id)
            }
            return SeedRemovalPlan(
                songs: inventory.unmodified,
                edited: inventory.edited,
                setlist: setlist,
            )
        }

        /// Moves the plan's songs and setlist to the Trash (never deletes), then reloads.
        func removeSeed(_ plan: SeedRemovalPlan) async throws {
            for song in plan.songs {
                _ = try await stores.library.deleteSong(id: song.id)
            }
            if let setlist = plan.setlist {
                try await stores.setlists.delete(setlist.id)
            }
            await library.reload()
            await setlists.reload()
        }

        /// Whether a song carrying the seed's tag is in the open library.
        func hasSeedSongs(fromManifestFolder folder: URL) async -> Bool {
            guard let manifest = try? SeedManifest.load(
                fromFolder: folder,
                fileSystem: stores.fileSystem,
            ) else { return false }
            let tagged = try? await stores.library.songs(taggedWith: manifest.tag)
            return !(tagged ?? []).isEmpty
        }

        /// Whether the library has no songs at all (the Welcome checkbox defaults on, A13).
        var hasNoSongs: Bool {
            library.catalog.isEmpty
        }
    }
#endif
