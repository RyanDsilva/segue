import AppKit
import Foundation
import Library
@testable import SegueUI
import Services
import Setlists
import Shows
import Support
import Testing

/// WS3 spec 14.2-6: no user content reaches a signal, a breadcrumb or the diagnostic log.
/// The real `AppModel`, stores, parser and show engine on a temp library seeded with the
/// SegueCore fixture songs, the Recording adapters with both consents granted, and the real
/// `DiagnosticLog`; then the app is driven through the view models (create, edit,
/// transpose, Nashville, apply to source, search with a spelling variant, a setlist, a
/// rehearsal) and every recorded byte is searched for the user's words.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct ServicesLeakTests {
        static let fixtureNames = [
            "basic-verse-chorus", "hindi-pyaar-ki-raah", "hindi-dil-kabhie", "unicode-lyrics",
            "editing-capo-defines",
        ]
        static let setlistName = "Ottoline Quartermaine Residency"
        static let newSong = """
        {title: Zanzibar Marmalade Evenings}
        {artist: Wilhelmina Featherstone}
        [G]Persimmon lanterns [C]drifting over [D]Kittiwake harbour

        """

        @Test
        func `no fixture title, lyric, file name or path reaches services`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let fixtures = try Self.seed(env)
            let recording = RecordingLog(url: env.scratch.appending(path: "services.jsonl"))
            let logs = env.scratch.appending(path: "Logs", directoryHint: .isDirectory)
            let log = DiagnosticLog(directory: logs, clock: env.clock, mirrorToOSLog: false)
            let hub = ServicesHub(
                factory: RecordingServicesFactory(log: recording),
                consent: ConsentState(analytics: .granted(.now), crashReports: .granted(.now)),
                throttle: AnalyticsThrottle(suiteName: env.suiteName, clock: env.clock),
            )
            var dependencies = env.dependencies(
                location: env.location(),
                override: env.libraryURL,
                remember: false,
            )
            dependencies.services = hub
            dependencies.diagnosticLog = log
            let app = AppModel(dependencies: dependencies)
            await app.start()
            try await Self.drive(app, env: env)
            await log.flush()

            let entries = recording.entries()
            let signals = entries.filter { $0["kind"] as? String == "signal" }
                .compactMap { $0["name"] as? String }
            for expected in [
                "Segue.Library.snapshot", "Segue.Song.created", "Segue.Editor.opened",
                "Segue.Feature.used", "Segue.Editor.chordPalette", "Segue.Search.performed",
                "Segue.Setlist.created", "Segue.Show.started", "Segue.Show.ended",
                "Segue.Milestone.reached",
            ] {
                #expect(signals.contains(expected), "no \(expected) in \(signals)")
            }
            let search = entries.first { $0["name"] as? String == "Segue.Search.performed" }
            let tier = (search?["params"] as? [String: String])?["segue.matchTier"]
            #expect(["spellingVariant", "looseVariant"].contains(tier), "\(tier ?? "nil")")
            #expect(entries.contains { $0["kind"] as? String == "breadcrumb" })

            let recorded = try Self.words(String(contentsOf: recording.url, encoding: .utf8))
            let diagnosticText = try Self.logText(logs)
            #expect(diagnosticText.contains("library opened"))
            let diagnostics = Self.words(diagnosticText)
            let secrets = Self.secrets(fixtures: fixtures, root: env.libraryURL)
            #expect(secrets.count > 40, "too few fixture words to be a real check")
            for secret in secrets {
                #expect(!recorded.contains(secret), "“\(secret)” reached the services log")
                #expect(!diagnostics.contains(secret), "“\(secret)” reached the diagnostic log")
            }
        }

        /// Spec 4.2 step 2: the prompt waits while a show starts or is on stage, and comes
        /// back once the stage is gone.
        @Test
        func `the consent prompt waits while a show is on stage`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            var dependencies = env.dependencies(
                location: env.location(),
                override: env.libraryURL,
                remember: false,
            )
            dependencies.consent = ConsentStore(defaults: nil, hub: .inert(), isAvailable: true)
            let app = AppModel(dependencies: dependencies)
            #expect(!app.showsConsentPrompt, "shown before the library state settled")
            await app.start()
            #expect(app.showsConsentPrompt)

            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .rehearsal))
            let live = try #require(app.live)
            #expect(!app.showsConsentPrompt, "shown over the stage")
            live.dispatch(.endShow)
            live.confirmEnd()
            _ = try await env.waitFor { app.live == nil ? true : nil }
            #expect(app.showsConsentPrompt)

            dependencies.consent.draft = ConsentStore.Draft(analytics: false, crashReports: false)
            dependencies.consent.commitDraft(source: .prompt)
            #expect(!app.showsConsentPrompt)
        }

        /// Create, edit, transpose, Nashville, apply to source, the palette, a search with a
        /// spelling variant, a setlist and a rehearsal of it, all through the view models.
        static func drive(_ app: AppModel, env: TestEnvironment) async throws {
            let session = try #require(app.session)
            let library = session.library
            // Song: create, edit, transpose, Nashville, apply to source, palette.
            let created = try await library.createSong(source: Self.newSong)
            library.openEditor(on: created)
            let editor = try #require(library.editor)
            editor.stepTranspose(by: 2)
            editor.setNashville(true)
            editor.setNashville(false)
            editor.applyTranspositionToSource()
            editor.armedChord = "G"

            // Search with a romanized-Hindi spelling variant of a fixture title.
            library.query = "pyar ki rah"
            _ = try await env.waitFor { library.results.isEmpty ? nil : true }
            try await Task.sleep(for: SearchRecorder.settle + .milliseconds(300))

            // A setlist and a rehearsal of it.
            let setlist = try #require(await session.setlists.create(name: Self.setlistName))
            for song in library.catalog.prefix(3) {
                await session.setlists.add(song.id, to: setlist.id)
            }
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            let current = try #require(session.setlists.setlist(setlist.id))
            #expect(await app.startShow(current, kind: .rehearsal))
            let live = try #require(app.live)
            live.dispatch(.next)
            live.dispatch(.endShow)
            live.confirmEnd()
            _ = try await env.waitFor { app.live == nil ? true : nil }
        }

        // MARK: Fixtures

        /// Copies the SegueCore fixture songs into the temp library; returns their texts
        /// with their file names.
        static func seed(_ env: TestEnvironment) throws -> [(name: String, text: String)] {
            let source = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .appending(path: "../../../SegueCore/Tests/Fixtures", directoryHint: .isDirectory)
                .standardizedFileURL
            let songs = env.libraryURL.appending(path: "songs", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: songs, withIntermediateDirectories: true)
            return try fixtureNames.map { name in
                let text = try String(
                    contentsOf: source.appending(path: "\(name).cho"),
                    encoding: .utf8,
                )
                try Data(text.utf8).write(to: songs.appending(path: "\(name).cho"))
                return (name, text)
            }
        }

        /// Every word of four letters or more the user wrote: fixture lyrics, titles and
        /// artists, the new song, the setlist name, the fixture file names and the library
        /// path's own folder names. Directive names and chords are not user content.
        static func secrets(fixtures: [(name: String, text: String)], root: URL) -> Set<String> {
            var texts = fixtures.map(\.text) + [newSong, setlistName]
            texts += fixtures.map(\.name)
            texts += root.pathComponents.filter { $0.hasPrefix("SegueUITests") }
            var words: Set<String> = []
            for text in texts {
                for line in text.split(whereSeparator: \.isNewline) {
                    var content = String(line)
                    if content.hasPrefix("{") {
                        // Keep only a directive's value ({title: X} -> X).
                        guard let colon = content.firstIndex(of: ":") else { continue }
                        content = String(content[content.index(after: colon)...])
                    }
                    content = content.replacing(/\[[^\]]*\]/, with: " ")
                    for word in content.split(whereSeparator: { !$0.isLetter }) {
                        let lower = word.lowercased()
                        if lower.count >= 4, !vocabulary.contains(lower) {
                            words.insert(lower)
                        }
                    }
                }
            }
            return words
        }

        /// Words the closed vocabulary itself may contain (signal names, keys, values).
        static let vocabulary: Set = [
            "segue", "song", "songs", "show", "library", "editor", "stage", "verse", "chorus",
            "bridge", "true", "false", "none", "used", "opened", "started", "ended", "created",
        ]

        /// The lowercased words (letter runs) of `text`; a secret leaks only as a whole word,
        /// so vocabulary such as `welcomeSongsLeft` never matches a lyric fragment.
        static func words(_ text: String) -> Set<String> {
            Set(text.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() })
        }

        static func logText(_ folder: URL) throws -> String {
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            return try names.map { name in
                try String(contentsOf: folder.appending(path: name), encoding: .utf8)
            }.joined(separator: "\n")
        }
    }
}
