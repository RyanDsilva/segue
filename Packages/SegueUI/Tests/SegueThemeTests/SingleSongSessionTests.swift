import AppKit
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Setlists
import Shows
import Support
import Testing

/// Rehearse or Live one song from the library (R150, P8-2 section 13) through the real app:
/// no checklist, nothing in `shows/`, no gig log entry, no plays, no completed-gig count.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct SingleSongSessionTests {
        private func showFiles(_ run: MetronomeRun) throws -> [String] {
            let folder = run.env.libraryURL.appending(path: "shows", directoryHint: .isDirectory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { $0.hasSuffix(LibraryRoot.showSuffix) }
        }

        @Test(arguments: [ShowKind.gig, .rehearsal])
        func `one song plays with no checklist and leaves no trace`(kind: ShowKind) async throws {
            let run = try await MetronomeRun(songs: [MapSong.source(), "{title: Two}\n[G]La\n"])
            // The checklist would show for a setlist run; a single song never shows it.
            run.app.liveSettings.settings.hiddenChecklistItems = []
            let session = try #require(run.app.session)
            let song = try #require(run.setlist.entries[0].songId)
            let gigsBefore = run.app.polish.review.completedGigs
            var ended = false

            #expect(await run.app.startSongSession(song, kind: kind, onEnd: { ended = true }))
            #expect(run.app.preShow == nil)
            let live = try #require(run.app.live)
            #expect(live.scope == .song)
            #expect(live.kind == kind)
            #expect(live.setlistName == "Harbour")
            #expect(live.state.record.items.map(\.title) == ["Harbour"])
            #expect(try showFiles(run).isEmpty)
            // The full song as written: no arrangement.
            #expect(live.currentArrangement == nil)
            live.setViewport(MapSong.viewport)
            #expect(live.mapPasses.count == 6)
            // Page Down at the bottom of the only song stays put (P8-1).
            for _ in 0 ..< 30 {
                live.dispatch(.pageForward)
            }
            #expect(live.state.current?.item.title == "Harbour")

            live.dispatch(.endShow)
            live.confirmEnd()
            _ = try await run.env.waitFor { run.app.live == nil ? true : nil }
            #expect(ended)
            #expect(try showFiles(run).isEmpty)
            await session.gigLog.reload()
            #expect(session.gigLog.entries.isEmpty)
            #expect(session.library.playStats[song] == nil)
            #expect(run.app.polish.review.completedGigs == gigsBefore)
            // No rehearsal timing samples either.
            let timings = run.env.libraryURL.appending(path: "timings", directoryHint: .isDirectory)
            #expect(!FileManager.default.fileExists(atPath: timings.path))
        }

        @Test
        func `the library menu items are enabled only with a focused song and no shown setlist`(
        ) async throws {
            let run = try await MetronomeRun(songs: [MapSong.source()])
            let app = run.app
            let session = try #require(app.session)
            let song = try #require(run.setlist.entries[0].songId)
            session.sidebarSelection = .library
            _ = try await run.env.waitFor { app.shownSetlist == nil ? true : nil }
            #expect(app.canStartSongSession(song))
            #expect(!app.canStartSongSession(nil))
            // A shown setlist enables Setlist > Rehearse and disables Rehearse Song: the two
            // ⌥⌘↩ items are never enabled together (R158 Q5).
            session.sidebarSelection = .setlist(run.setlist.id)
            _ = try await run.env.waitFor { app.shownSetlist != nil ? true : nil }
            #expect(!app.canStartSongSession(song))
            // Nothing starts while a run is on stage.
            #expect(await app.startSongSession(song, kind: .rehearsal))
            session.sidebarSelection = .library
            _ = try await run.env.waitFor { app.shownSetlist == nil ? true : nil }
            #expect(!app.canStartSongSession(song))
            #expect(!app.canStartSongSessionNow)
            #expect(await !app.startSongSession(song, kind: .gig))
            let live = try #require(app.live)
            live.dispatch(.endShow)
            live.confirmEnd()
            _ = try await run.env.waitFor { app.live == nil ? true : nil }
            #expect(app.canStartSongSession(song))
        }

        @Test
        func `a slot's arrangement starts through the same entry point (P8-3)`() async throws {
            let run = try await MetronomeRun(songs: [MapSong.source()])
            let song = try #require(run.setlist.entries[0].songId)
            let record = try #require(run.app.session?.library.song(id: song))
            let units = SongSections.units(of: record.document)
            let arrangement = SlotArrangement(
                passes: [units[1], units[3]].map {
                    ArrangementPass(anchor: $0.anchor, fingerprint: $0.fingerprint)
                },
                knownParts: KnownPart.all(units),
            )
            let slot = StageSlot(
                overrides: SetlistOverrides(transpose: 2),
                arrangement: arrangement,
            )
            #expect(await run.app.startSongSession(song, kind: .rehearsal, slot: slot))
            let live = try #require(run.app.live)
            live.setViewport(MapSong.viewport)
            #expect(live.currentArrangement == .applied)
            #expect(live.mapPasses.map(\.name.chipText) == ["Chorus 1/2", "Chorus 2/2"])
            live.dispatch(.endShow)
            live.confirmEnd()
            _ = try await run.env.waitFor { run.app.live == nil ? true : nil }
        }
    }
}
