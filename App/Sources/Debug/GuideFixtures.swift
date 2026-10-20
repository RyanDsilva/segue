#if DEBUG
    import Foundation

    /// The user guide's and the App Store paste shot's fixtures (WS6 5.2, WS5 8.4 shot 9),
    /// written by `-SegueGuideFixtures YES` into the screenshot folder inside the app's
    /// container (the sandbox reads nothing outside it):
    /// - `chordSitePaste`: a chord-site-style paste of the Welcome song "Kettle On, Lights
    ///   Low" (our own text), with no section headers, so the converter asks the model;
    /// - `recording`: Apple's model's real answer for that paste, recorded with
    ///   `segue-eval --providers fm --record` (apple-fm 26.6.2), replayed through
    ///   `-SegueScriptedAI` so the review sheet shows the AI marks deterministically;
    /// - `importFiles`: three small files for the batch import review.
    /// UITests/AppStore/GuideShots.swift keeps the same paste text: if the two drift, the
    /// replay key no longer matches and the captures fail on the missing AI mark.
    enum GuideFixtures {
        static var folder: URL {
            LaunchOptions.screenshotLibraryFolder.deletingLastPathComponent()
                .appending(path: "Guide", directoryHint: .isDirectory)
        }

        static var aiFolder: URL {
            folder.appending(path: "AI", directoryHint: .isDirectory)
        }

        static var importFolder: URL {
            folder.appending(path: "Import", directoryHint: .isDirectory)
        }

        static var importURLs: [URL] {
            importFiles.map { importFolder.appending(path: $0.name) }
        }

        static let chordSitePaste = """
        Kettle On, Lights Low Chords by Segue Originals
        Transpose  -1  +1   Autoscroll
        Capo 3

        G          Cadd9
        Kettle on, lights low,
        G              D/F#
        Rain on the window glass,
        Em7            Cadd9
        Nowhere we need to go,
        G       D       G
        Let the evening pass.

        G        Cadd9
        Two old chairs that creak,
        G          D/F#
        One old song we know,
        Em7              Cadd9
        Half of it hummed, not sung,
        G       D         G
        Kettle on, lights low.

        Cadd9         G
        Turn, turn, round the room,
        Cadd9            D
        Slow as the clock can go,
        Em7        Cadd9          G
        One more waltz for the afternoon,
        Am7      D          G
        Kettle on, lights low.

        G        Cadd9
        Cups gone cold again,
        G          D/F#
        Records spinning slow,
        Em7               Cadd9
        Stay till the morning, then,
        G       D         G
        Kettle on, lights low.

        Cadd9         G
        Turn, turn, round the room,
        Cadd9            D
        Slow as the clock can go,
        Em7        Cadd9          G
        One more waltz for the afternoon,
        Am7      D          G
        Kettle on, lights low.
        """

        static let recording = """
        {
          "calls" : [
            {
              "input" : "15b845c5ff626fe1",
              "output" : {
                "labels" : [
                  "intro",
                  "verse",
                  "verse",
                  "instrumental",
                  "verse",
                  "verse"
                ]
              },
              "task" : "sectionLabels"
            }
          ],
          "fixture" : "G01-guide-chord-site",
          "provider" : "fm",
          "schemaVersion" : 1,
          "source" : "apple-fm Version 26.6.2 (Build 25G83)"
        }
        """

        static let importFiles: [(name: String, text: String)] = [
            ("Kettle On, Lights Low.txt", chordSitePaste),
            ("Saltwater Telegraph.crd", """
            Saltwater Telegraph
            Segue Originals

            Am   F   C   G
            Am   F   E7  Am

            F    C   G   Am
            F    C   E7  Am
            """),
            ("Last Tram to Wexley.txt", """
            Last Tram to Wexley
            Segue Originals

            Verse
            G   D   Em   C
            G   D   C    D

            Chorus
            C   G   D   Em
            C   G   D   G
            """),
        ]

        /// Writes the fixtures (replacing any earlier copy).
        static func write() {
            let manager = FileManager.default
            try? manager.removeItem(at: folder)
            do {
                try manager.createDirectory(at: aiFolder, withIntermediateDirectories: true)
                try manager.createDirectory(at: importFolder, withIntermediateDirectories: true)
                try Data(recording.utf8)
                    .write(to: aiFolder.appending(path: "G01-guide-chord-site.json"))
                for file in importFiles {
                    try Data(file.text.utf8).write(to: importFolder.appending(path: file.name))
                }
            } catch {
                FileHandle.standardError.write(Data("GuideFixtures: \(error)\n".utf8))
            }
        }
    }
#endif
