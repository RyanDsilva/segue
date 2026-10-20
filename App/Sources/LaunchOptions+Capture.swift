#if DEBUG
    import CoreGraphics
    import Foundation

    /// The screenshot capture layer (WS5 8.2, built by WS6 for the user guide, R127):
    /// - `-SegueScreenshotLibrary YES`: a clean, known library for captures: wipes
    ///   `screenshotLibraryFolder`, then seeds the Welcome songs and setlist there plus the
    ///   screenshot-only songs and "JamFest Opener" (`ScreenshotSongs`, WS5 8.4.1), with
    ///   onboarding done, tips hidden, consent declined and no What's New or review prompt
    ///   (the usual test-run defaults). Never touches the user's library bookmark.
    /// - `-SegueWindowFrame x,y,w,h`: the main window's frame in points, top-left origin at
    ///   the main screen's visible area, clear of the menu bar and Dock (and the stage's, with
    ///   `-SegueStageWindowed`).
    /// - `-SegueStageWindowed YES`: present the stage in a window at `-SegueWindowFrame`
    ///   instead of covering the screen.
    /// - `-SegueFixedClock <ISO8601>`: the app clock starts at this instant (dates in the gig
    ///   log and on cards stay the same between captures).
    /// - `-SegueScriptedAI <directory>`: AI calls replay the `ScriptedProvider` recordings in
    ///   `<directory>` (as Apple's model); a call with no recording keeps the converter's
    ///   result, as with AI off.
    /// - `-SegueClockRate <n>`: with `-SegueFixedClock`, the app clock runs `n` times faster
    ///   than real time (a captured gig's songs last minutes, not seconds).
    /// - `-SegueGuideFixtures YES`: writes `GuideFixtures` into the container and, unless
    ///   given explicitly, points `-SegueScriptedAI` at its recorded model answer and
    ///   `-SegueImportPanelPaths` at its import files (WS6 5.2).
    extension LaunchOptions {
        static let screenshotLibraryFlag = "-SegueScreenshotLibrary"
        static let windowFrameFlag = "-SegueWindowFrame"
        static let stageWindowedFlag = "-SegueStageWindowed"
        static let fixedClockFlag = "-SegueFixedClock"
        static let scriptedAIFlag = "-SegueScriptedAI"
        static let guideFixturesFlag = "-SegueGuideFixtures"
        static let clockRateFlag = "-SegueClockRate"

        /// Every flag takes one value: the last value given for each known flag.
        static func flagValues(_ arguments: [String]) -> [String: String] {
            var values: [String: String] = [:]
            var iterator = arguments.dropFirst().makeIterator()
            while let argument = iterator.next() {
                guard flags.contains(argument), let value = iterator.next() else { continue }
                values[argument] = value
            }
            return values
        }

        /// Reads the capture flags from the parsed `-Flag value` pairs.
        mutating func parseCapture(_ values: [String: String]) {
            screenshotLibrary = values[Self.screenshotLibraryFlag].map(Self.isTruthy) ?? false
            if screenshotLibrary {
                // The composite (WS5 8.2): the Welcome library in the container folder, with
                // onboarding done; the other parts are the test-run defaults.
                seedWelcome = true
                onboarding = onboarding ?? .done
            }
            windowFrame = values[Self.windowFrameFlag].flatMap(Self.rect)
            stageWindowed = values[Self.stageWindowedFlag].map(Self.isTruthy) ?? false
            fixedClock = values[Self.fixedClockFlag].flatMap { try? Date($0, strategy: .iso8601) }
            scriptedAI = Self.path(values[Self.scriptedAIFlag], directoryHint: .isDirectory)
            guideFixtures = values[Self.guideFixturesFlag].map(Self.isTruthy) ?? false
            clockRate = values[Self.clockRateFlag].flatMap(Double.init)
                .flatMap { $0 > 0 ? $0 : nil }
            if guideFixtures {
                scriptedAI = scriptedAI ?? GuideFixtures.aiFolder
                importPanelPaths = importPanelPaths ?? GuideFixtures.importURLs
            }
        }

        /// "x,y,w,h" in points; nil unless four numbers with a positive size.
        static func rect(_ text: String) -> CGRect? {
            let numbers = text.split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
            return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }

        /// Empties `screenshotLibraryFolder` (inside the app's own container) so every
        /// capture run starts from the same Welcome library.
        static func wipeScreenshotLibrary() {
            let folder = screenshotLibraryFolder
            let manager = FileManager.default
            let items = (try? manager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
            )) ?? []
            for item in items {
                try? manager.removeItem(at: item)
            }
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }
#endif
