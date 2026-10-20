import Foundation
import Library
@testable import SegueUI
import Setlists
import Shows
import Support
import Testing

/// The Welcome library through the app (WS2b 4.2, 4.6), on a real temp library: seeding the
/// songs and the demo setlist, idempotency, "Remove Welcome Songs" keeping edited songs, and
/// the scope of Reset All Settings. Real stores, parser and files; nothing is mocked.
@MainActor
struct WelcomeSeedingTests {
    @Test
    func `seeding adds the four songs and the welcome set once`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let session = try #require(app.session)

        #expect(await app.seedWelcomeLibrary())
        #expect(session.library.catalog.map(SongSummary.title).sorted() == [
            "Ferry Lights Over Calder Bay", "Kettle On, Lights Low", "Kitaabon Wali Gali",
            "Soundcheck at Seven",
        ])
        let setlist = try #require(session.setlists.setlists.first { $0.name == "Welcome Set" })
        #expect(setlist.targetDuration == 1200)
        #expect(setlist.entries.count == 4)
        #expect(setlist.entries[1].overrides.transpose == -2)
        #expect(setlist.entries[2].note == "Brushes, start soft")
        #expect(setlist.entries[3].note == "Closer: big finish")
        let record = try #require(app.polish.onboarding.seed)
        #expect(record.setlistID == setlist.id.description)
        #expect(record.songIDs.count == 4)

        // Again: nothing new, the same setlist.
        #expect(await app.seedWelcomeLibrary())
        #expect(session.library.catalog.count == 4)
        #expect(session.setlists.setlists.count == 1)
        #expect(await app.addWelcomeSongsFromSettings()
            == "The Welcome songs are already in your library.")
    }

    /// R78 / P3-5: every seeded Welcome song has a length, so set timing works out of the
    /// box. Songs added for the WS5 screenshots need `{duration}` too.
    @Test
    func `seeded welcome songs carry their lengths`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let session = try #require(app.session)
        #expect(await app.seedWelcomeLibrary())
        var lengths: [String: TimeInterval] = [:]
        for song in session.library.catalog {
            let metadata = song.document.metadata
            lengths[metadata.title ?? ""] = metadata.duration
        }
        #expect(lengths == [
            "Ferry Lights Over Calder Bay": 280, "Kettle On, Lights Low": 185,
            "Kitaabon Wali Gali": 245, "Soundcheck at Seven": 200,
        ])
    }

    @Test
    func `remove welcome songs trashes the originals and keeps edited ones`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let session = try #require(app.session)
        #expect(await app.seedWelcomeLibrary())

        // The user edits one song in another editor.
        let edited = "songs/kettle-on-lights-low.cho"
        try env.write(env.read(edited) + "\n{comment: my capo note}\n", to: edited)
        await session.refreshFromDisk()

        let plan = try #require(await app.welcomeRemovalPlan())
        #expect(plan.songs.count == 3)
        #expect(plan.edited.map(SongSummary.title) == ["Kettle On, Lights Low"])
        #expect(plan.setlist?.name == "Welcome Set")
        #expect(plan.headline == "Move 3 Welcome songs and the Welcome Set setlist to the Trash?")
        #expect(plan.keptNote == "1 edited song is kept: Kettle On, Lights Low.")

        let status = await app.removeWelcomeSongs(plan)
        #expect(status.hasPrefix("Moved to the Trash."))
        #expect(session.library.catalog.map(SongSummary.title) == ["Kettle On, Lights Low"])
        #expect(session.setlists.setlists.isEmpty)
        #expect(env.exists(edited))
        #expect(!env.exists("songs/soundcheck-at-seven.cho"))
        #expect(!env.exists("setlists/welcome-set.setlist.json"))
        // To the Trash, never deleted.
        let trashed = try FileManager.default.contentsOfDirectory(atPath: env.trashURL.path)
        #expect(trashed.contains("soundcheck-at-seven.cho"))
        #expect(trashed.contains("welcome-set.setlist.json"))
    }

    @Test
    func `reset all settings resets only its own scope`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let polish = app.polish
        app.liveSettings.settings.minLyricSize = 30
        app.liveSettings.runsShortcutsForRehearsals = true
        polish.appearance.mode = .dark
        polish.preferences.selectedPane = "data"
        polish.onboarding.markCompleted()
        polish.whatsNew.markSeen("0.5")
        polish.review.recordCompletedGig()
        app.dependencies.consent.set(true, for: .analytics, source: nil)

        app.resetAllSettings()

        #expect(app.liveSettings.settings == LiveSettings())
        #expect(!app.liveSettings.runsShortcutsForRehearsals)
        #expect(polish.appearance.mode == .system)
        #expect(env.defaults.string(forKey: AppearanceStore.key) == nil)
        #expect(polish.preferences.selectedPane == nil)
        #expect(polish.preferences.tipsResetPending)
        // Kept.
        #expect(app.session != nil)
        #expect(polish.onboarding.isCompleted)
        #expect(polish.whatsNew.lastSeenVersion == "0.5")
        #expect(polish.review.completedGigs == 1)
        #expect(app.dependencies.consent.isDecided(.analytics))
    }
}
