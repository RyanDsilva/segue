#if DEBUG
    import Foundation
    import SegueUI

    /// The App Store screenshots' library additions (WS5 8.4.1, R128, R129): five original
    /// titles by "Segue Originals" with chords and section labels only (no lyrics), and the
    /// setlist "JamFest Opener". Debug only: never shipped, and `verify-appstore` /
    /// `verify-archive` fail if a title reaches a Release binary (scripts/lib/verify-common.sh).
    ///
    /// `-SegueScreenshotLibrary YES` writes them as a schema-1 seed manifest folder that the
    /// app seeds after the Welcome library. The folder repeats the four Welcome songs
    /// byte-for-byte under the Welcome tag, so the seeder reuses those songs and the setlist
    /// can reference them; only the five new songs are created.
    enum ScreenshotSongs {
        struct Song {
            let file: String
            let title: String
            let key: String
            let tempo: Int
            let tags: [String]
            let proficiency: String
            let body: String

            var source: String {
                """
                {title: \(title)}
                {artist: Segue Originals}
                {key: \(key)}
                {tempo: \(tempo)}

                \(body)
                """
            }
        }

        /// The seed folder, next to the screenshot library inside the app's container.
        static var seedFolder: URL {
            LaunchOptions.screenshotLibraryFolder.deletingLastPathComponent()
                .appending(path: "Seed", directoryHint: .isDirectory)
        }

        static let setlistName = "JamFest Opener"
        /// 29:48 of songs against 30:00: the running total sits a little under the target.
        static let targetDuration = 1800

        static let songs: [Song] = [
            Song(
                file: "lanterns-on-pier-nine.cho",
                title: "Lanterns on Pier Nine",
                key: "D",
                tempo: 92,
                tags: ["folk"],
                proficiency: "pro",
                body: """
                {start_of_intro: Intro}
                [D] [A/C#] [Bm] [G]
                {end_of_intro}

                {start_of_verse: Verse 1}
                [D] [A/C#] [Bm] [G]
                [D] [A] [G] [A]
                {end_of_verse}

                {start_of_chorus}
                [G] [D] [A] [Bm]
                [G] [D] [A] [D]
                {end_of_chorus}

                {start_of_bridge}
                [Em] [G] [D] [A]
                {end_of_bridge}
                """,
            ),
            Song(
                file: "chai-at-platform-four.cho",
                title: "Chai at Platform Four",
                key: "Em",
                tempo: 96,
                tags: ["upbeat"],
                proficiency: "ready",
                body: """
                {start_of_verse: Verse 1}
                [Em] [C] [G] [D]
                [Em] [C] [Am] [B7]
                {end_of_verse}

                {start_of_chorus}
                [C] [G] [D] [Em]
                [C] [G] [B7] [Em]
                {end_of_chorus}
                """,
            ),
            Song(
                file: "northbound-at-first-light.cho",
                title: "Northbound at First Light",
                key: "Bb",
                tempo: 76,
                tags: ["ballad"],
                proficiency: "ready",
                body: """
                {start_of_verse: Verse 1}
                [Bb] [F/A] [Gm] [Eb]
                [Bb] [F] [Eb] [F]
                {end_of_verse}

                {start_of_chorus}
                [Eb] [Bb] [F] [Gm]
                [Eb] [Bb] [F] [Bb]
                {end_of_chorus}

                {start_of_bridge}
                [Cm] [Eb] [Bb] [F]
                {end_of_bridge}
                """,
            ),
            Song(
                file: "saltwater-telegraph.cho",
                title: "Saltwater Telegraph",
                key: "Am",
                tempo: 100,
                tags: ["folk"],
                proficiency: "learning",
                body: """
                {start_of_verse: Verse 1}
                [Am] [F] [C] [G]
                [Am] [F] [E7] [Am]
                {end_of_verse}

                {start_of_chorus}
                [F] [C] [G] [Am]
                [F] [C] [E7] [Am]
                {end_of_chorus}
                """,
            ),
            Song(
                file: "last-tram-to-wexley.cho",
                title: "Last Tram to Wexley",
                key: "G",
                tempo: 132,
                tags: ["upbeat"],
                proficiency: "ready",
                body: """
                {start_of_verse: Verse 1}
                [G] [D] [Em] [C]
                [G] [D] [C] [D]
                {end_of_verse}

                {start_of_chorus}
                [C] [G] [D] [Em]
                [C] [G] [D] [G]
                {end_of_chorus}
                """,
            ),
        ]

        /// The set order (WS5 8.4.1): Ferry Lights in position 3 so the stage shot has an Up
        /// next song; Kitaabon Wali Gali is left out so a request for it is a real request.
        static let setlistFiles = [
            "last-tram-to-wexley.cho",
            "lanterns-on-pier-nine.cho",
            "ferry-lights-over-calder-bay.cho",
            "chai-at-platform-four.cho",
            "soundcheck-at-seven.cho",
            "saltwater-telegraph.cho",
            "kettle-on-lights-low.cho",
            "northbound-at-first-light.cho",
        ]

        /// The Welcome songs as the bundled manifest lists them (tags and proficiency are
        /// not rewritten: the seeder reuses the existing songs).
        static let welcomeFiles = [
            "soundcheck-at-seven.cho",
            "kitaabon-wali-gali.cho",
            "kettle-on-lights-low.cho",
            "ferry-lights-over-calder-bay.cho",
        ]

        /// Writes the seed folder (manifest, the five songs, copies of the Welcome songs)
        /// and returns it; nil when the bundled Welcome library is missing.
        @MainActor
        static func writeSeedFolder(
            welcomeFolder: URL? = PolishDependencies.bundledWelcomeFolder,
        ) -> URL? {
            guard let welcomeFolder else { return nil }
            let manager = FileManager.default
            let folder = seedFolder
            try? manager.removeItem(at: folder)
            do {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                for file in welcomeFiles {
                    try manager.copyItem(
                        at: welcomeFolder.appending(path: file),
                        to: folder.appending(path: file),
                    )
                }
                for song in songs {
                    try Data(song.source.utf8).write(to: folder.appending(path: song.file))
                }
                try manifest().write(to: folder.appending(path: "manifest.json"))
            } catch {
                return nil
            }
            return folder
        }

        static func manifest() throws -> Data {
            var entries: [[String: Any]] = welcomeFiles.map { ["file": $0, "tags": ["Welcome"]] }
            entries += songs.map { song in
                ["file": song.file, "tags": song.tags, "proficiency": song.proficiency]
            }
            let manifest: [String: Any] = [
                "schema": 1,
                "tag": "Welcome",
                "songs": entries,
                "setlist": [
                    "name": setlistName,
                    "targetDuration": targetDuration,
                    "entries": setlistFiles.map { ["song": $0] },
                ],
            ]
            return try JSONSerialization.data(
                withJSONObject: manifest,
                options: [.prettyPrinted, .sortedKeys],
            )
        }
    }
#endif
