import AppKit
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Setlists
import Shows
import Support
import Testing

/// Live mode at the app layer: the real `AppModel`, show engine, layout engine and stores
/// on a temp library, with the manual clock driving auto-scroll and a recording Shortcut
/// runner.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct LiveModeTests {
        // MARK: Settings

        @Test
        func `live settings persist and the minimum lyric size is clamped`() throws {
            let env = try TestEnvironment()
            let store = LiveSettingsStore(defaults: env.defaults)
            #expect(store.settings == LiveSettings())
            #expect(!store.runsShortcutsForRehearsals)
            store.settings.minLyricSize = 30
            store.settings.startShortcut = "Stage On"
            store.settings.hiddenChecklistItems = [.brightness]
            store.runsShortcutsForRehearsals = true

            let reloaded = LiveSettingsStore(defaults: env.defaults)
            #expect(reloaded.settings.minLyricSize == 30)
            #expect(reloaded.settings.startShortcut == "Stage On")
            #expect(reloaded.settings.hiddenChecklistItems == [.brightness])
            #expect(reloaded.runsShortcutsForRehearsals)
            #expect(LiveSettingsStore.clampedMinLyricSize(4) == 16)
            #expect(LiveSettingsStore.clampedMinLyricSize(90) == 48)
            #expect(LiveSettingsStore.shortcutName("  ") == nil)
            #expect(LiveSettingsStore.shortcutName(" Gig ") == "Gig")
        }

        @Test
        func `the Shortcut URL is percent-encoded`() throws {
            let url = try #require(WorkspaceShortcutRunner.url(for: "Gig Mode On & Off"))
            #expect(url
                .absoluteString == "shortcuts://run-shortcut?name=Gig%20Mode%20On%20%26%20Off")
        }

        // MARK: Keys

        @Test(arguments: [
            (UInt16(124), "", NSEvent.ModifierFlags(), LiveCommand.next),
            (UInt16(49), " ", NSEvent.ModifierFlags(), LiveCommand.next),
            (UInt16(123), "", NSEvent.ModifierFlags(), LiveCommand.previous),
            (UInt16(121), "", NSEvent.ModifierFlags(), LiveCommand.scrollPageDown),
            (UInt16(40), "k", NSEvent.ModifierFlags.command, LiveCommand.openSearch),
            (UInt16(44), "/", NSEvent.ModifierFlags(), LiveCommand.openSearch),
            (UInt16(24), "=", NSEvent.ModifierFlags.command, LiveCommand.zoomIn),
            (UInt16(24), "+", NSEvent.ModifierFlags([.command, .shift]), LiveCommand.zoomIn),
            (UInt16(47), ".", NSEvent.ModifierFlags.command, LiveCommand.endShow),
            (UInt16(0), "a", NSEvent.ModifierFlags(), LiveCommand.toggleAutoScroll),
            (UInt16(30), "]", NSEvent.ModifierFlags(), LiveCommand.scrollFaster),
            (UInt16(8), "c", NSEvent.ModifierFlags(), LiveCommand.cycleColumns),
            (UInt16(31), "o", NSEvent.ModifierFlags(), LiveCommand.toggleCollapseRepeats),
        ])
        func `key events map to live commands through the default bindings`(
            keyCode: UInt16,
            characters: String,
            flags: NSEvent.ModifierFlags,
            command: LiveCommand,
        ) throws {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode,
            ))
            let stroke = try #require(LiveKeyInput.keyStroke(event))
            #expect(InputBindingTable.defaults.command(for: .key(stroke)) == command)
        }

        // MARK: A run on stage

        @Test
        func `a gig runs from start to the gig log with zoom memory and Shortcuts`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)

            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            live.setViewport(LayoutSize(width: 1390, height: 700))
            #expect(live.positionText == "1 of 3")
            #expect(live.plan?.fit == .fits)

            // Zoom song A: saved to its sidecar; song B is unaffected; A keeps it on return.
            live.dispatch(.zoomIn)
            #expect(live.currentPrefs?.zoom == 1.1)
            let alpha = fixture.songs[0].id
            var savedZoom: Double?
            for _ in 0 ..< 200 where savedZoom != 1.1 {
                savedZoom = try await fixture.library.reloadSong(id: alpha)?.sidecar.live.zoom
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(savedZoom == 1.1)
            // C cycles Auto -> 1 -> 2 -> 3 -> Auto; the plan follows at once.
            for expected in [1, 2, 3] {
                live.dispatch(.cycleColumns)
                #expect(live.currentPrefs?.columns == expected)
                #expect((live.plan?.columns.count ?? 0) <= expected)
                #expect(live.indicator == "Columns: \(expected)")
            }
            live.dispatch(.cycleColumns)
            #expect(live.currentPrefs?.columns == nil)
            live.dispatch(.cycleColumns)
            var savedColumns: Int?
            for _ in 0 ..< 200 where savedColumns != 1 {
                savedColumns = try await fixture.library.reloadSong(id: alpha)?.sidecar.live.columns
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(savedColumns == 1)
            live.dispatch(.next)
            _ = try await env.waitFor { live.positionText == "2 of 3" ? true : nil }
            #expect(live.currentPrefs?.zoom == 1)
            live.dispatch(.previous)
            _ = try await env.waitFor { live.positionText == "1 of 3" ? true : nil }
            #expect(live.currentPrefs?.zoom == 1.1)
            #expect(live.currentPrefs?.columns == 1)

            // End: confirmation first, then the gig log and the end Shortcut.
            live.dispatch(.endShow)
            #expect(live.overlay == .endConfirm)
            live.confirmEnd()
            _ = try await env.waitFor { app.live == nil ? true : nil }
            // The end Shortcut runs after the stage closes.
            _ = try await env.waitFor { (try? env.shortcutsRun().count) == 2 ? true : nil }
            #expect(try env.shortcutsRun() == ["Gig Mode On", "Gig Mode Off"])
            let log = await app.session?.stores.shows.gigLog() ?? []
            #expect(log.count == 1)
        }

        /// Cmd-Return in quick search asks for an optional note; Return adds the request with
        /// it, and a blank note is skipped.
        @Test
        func `a request from quick search carries its optional note`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            let session = try #require(app.session)
            let extra = try await session.library.createSong(
                source: LiveFixture.source(title: "Zulu Request", lines: 4, duration: nil),
            )
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }

            for note in ["  table 4 ", "   "] {
                live.dispatch(.openSearch)
                live.search.query = "zulu"
                _ = try await env.waitFor { live.search.results.first?.id == extra.id ? true : nil }
                live.searchAction(.addRequest, song: extra.id)
                // Not added yet: the overlay now asks for the note.
                #expect(live.overlay == .search)
                #expect(live.search.requesting?.id == extra.id)
                live.search.note = note
                live.commitRequest()
                #expect(live.overlay == nil)
                #expect(live.search.requesting == nil)
            }
            _ = try await env.waitFor { live.queuedRequests.count == 2 ? true : nil }
            #expect(live.queuedRequests.map(\.note) == ["table 4", nil])

            // Esc on the note goes back to the results without adding anything.
            live.dispatch(.openSearch)
            live.search.query = "zulu"
            _ = try await env.waitFor { live.search.results.isEmpty ? nil : true }
            live.searchAction(.addRequest, song: extra.id)
            live.search.cancelRequest()
            #expect(live.overlay == .search)
            #expect(live.search.requesting == nil)
            live.overlay = nil
            #expect(live.queuedRequests.count == 2)
        }

        /// Open question 17: when the setlist is deleted during the show, the review offers
        /// only Discard, says why, and a Save never recreates the file.
        @Test
        func `the reorder review cannot save to a setlist deleted during the show`(
        ) async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            live.perform(.move(fromOffsets: [2], toOffset: 1))
            _ = try await env.waitFor {
                live.state.record.items.map(\.title) == ["Alpha", "Charlie", "Bravo"] ? true : nil
            }
            let directory = env.libraryURL.appending(path: "setlists", directoryHint: .isDirectory)
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
            )
            #expect(files.count == 1)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }

            live.dispatch(.endShow)
            live.confirmEnd()
            _ = try await env.waitFor { app.pendingReorderReviews.isEmpty ? nil : true }
            let reason = try #require(app.reviewSaveBlockers[fixture.setlist.id])
            #expect(reason.contains("was deleted during the show"))
            await app.resolveReorderReview(save: true, including: [])
            #expect(app.pendingReorderReviews.isEmpty)
            #expect(app.reviewSaveBlockers.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }

        @Test
        func `auto-scroll reaches the bottom of a 3 minute song and holds while paused`(
        ) async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(
                app: app,
                titles: ["Long"],
                lines: 240,
                duration: "3:00",
            )
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .rehearsal))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            live.setViewport(LayoutSize(width: 1390, height: 700))
            let plan = try #require(live.plan)
            #expect(plan.needsScroll)
            #expect(plan.lyricSize >= 22)

            // Never moves before it is started.
            env.clock.advance(by: 30)
            #expect(live.scrollFraction(at: env.clock.now()) == 0)
            live.dispatch(.toggleAutoScroll)
            env.clock.advance(by: 90)
            let halfway = live.scrollFraction(at: env.clock.now())
            #expect(halfway > 0.3 && halfway < 0.7)
            live.dispatch(.toggleAutoScroll)
            env.clock.advance(by: 60)
            #expect(live.scrollFraction(at: env.clock.now()) == halfway)
            live.dispatch(.toggleAutoScroll)
            env.clock.advance(by: 120)
            #expect(live.scrollFraction(at: env.clock.now()) == 1)
        }
    }
}

/// Songs and a setlist created through the app's own stores.
@MainActor
struct LiveFixture {
    let songs: [SongRecord]
    let setlist: Setlist
    let library: LibraryStore

    init(app: AppModel, titles: [String], lines: Int = 8, duration: String? = nil) async throws {
        let session = try #require(app.session)
        var songs: [SongRecord] = []
        for title in titles {
            try await songs.append(session.library.createSong(
                source: Self.source(title: title, lines: lines, duration: duration),
            ))
        }
        let created = try #require(await session.setlists.create(name: "Fixture Set"))
        for song in songs {
            await session.setlists.add(song.id, to: created.id)
        }
        self.songs = songs
        setlist = try #require(session.setlists.selected)
        library = session.stores.library
    }

    static func source(title: String, lines: Int, duration: String?) -> String {
        var text = "{title: \(title)}\n{key: G}\n{tempo: 96}\n"
        if let duration {
            text += "{duration: \(duration)}\n"
        }
        for verse in 0 ..< max(1, lines / 4) {
            text += "{start_of_verse: Verse \(verse + 1)}\n"
            for line in 0 ..< 4 {
                let number = verse * 4 + line + 1
                text += "[G]Lanterns on the [D]water line \(number), [Em]boats come [C]in\n"
            }
            text += "{end_of_verse}\n\n"
        }
        return text
    }
}
