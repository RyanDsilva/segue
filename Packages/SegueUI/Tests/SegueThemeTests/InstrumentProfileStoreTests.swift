import AppKit
import Diagrams
import Editing
import Foundation
import Library
@testable import SegueUI
import Services
import SwiftUI
import Testing

/// Settings > Instrument (P8-4 6.3-6.4, 11.3): the store over a real defaults suite, Reset
/// All Settings, and the pane drawn in light and dark.
@MainActor
struct InstrumentProfileStoreTests {
    @Test
    func `the profile loads, saves and resets`() throws {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        #expect(store.profile == InstrumentProfile())
        #expect(store.bassView == nil)

        store.update { $0.chordBeside = true }
        store.update { $0.setStrings(5) }
        #expect(store.profile.tuning == .bassStandard5)
        let reloaded = InstrumentProfileStore(defaults: env.defaults)
        #expect(reloaded.profile.chordBeside)
        #expect(reloaded.profile.strings == 5)
        #expect(reloaded.profile.tuning == .bassStandard5)

        reloaded.resetToDefaults()
        #expect(InstrumentProfileStore(defaults: env.defaults).profile == InstrumentProfile())
    }

    @Test
    func `switching strings resets the tuning unless it already fits`() throws {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.update { $0.tuning = .bassDropD }
        store.update { $0.setStrings(4) }
        #expect(store.profile.tuning == .bassDropD)
        store.update { $0.setStrings(5) }
        #expect(store.profile.tuning == .bassStandard5)
        // A write that breaks the invariant is normalized.
        store.update { $0.tuning = .bassStandard4 }
        #expect(store.profile.tuning == .bassStandard5)
    }

    @Test
    func `turning on I play bass turns bass notes on and records the profile once`() throws {
        let env = try TestEnvironment()
        let recorder = RecordingAnalytics(env)
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.services = recorder.hub
        store.update { $0.setPlaysBass(true) }
        #expect(store.profile.bassNotes)
        #expect(store.bassView?.notes == true)
        store.toggleBassNotes(from: .settings)
        #expect(!store.profile.bassNotes)
        #expect(store.profile.playsBass)
        store.update { $0.setPlaysBass(true) }
        #expect(recorder.features == ["bassProfile", "bassNotes"])
    }

    @Test
    func `resetting all settings resets the instrument profile`() async throws {
        let env = try TestEnvironment()
        let app = AppModel(dependencies: env.dependencies(
            location: env.location(),
            override: env.libraryURL,
            remember: false,
        ))
        await app.start()
        app.instrumentProfile.update { $0.setPlaysBass(true) }
        app.resetAllSettings()
        #expect(app.instrumentProfile.profile == InstrumentProfile())
        #expect(DataSettingsView.resetMessage.contains("Instrument"))
    }

    @Test
    func `the pane renders in light and dark`() throws {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        for (name, setup) in [
            ("off", { (_: InstrumentProfileStore) in }),
            ("bassist", { (store: InstrumentProfileStore) in
                store.update { $0.setPlaysBass(true) }
                store.update { $0.chordBeside = true }
            }),
            ("custom", { (store: InstrumentProfileStore) in
                store.update { $0.tuning = Tuning(bassLetters: "C F Bb Eb") ?? .bassStandard4 }
            }),
        ] as [(String, (InstrumentProfileStore) -> Void)] {
            store.resetToDefaults()
            setup(store)
            for dark in [false, true] {
                let view = InstrumentSettingsView(store: store).frame(width: 560, height: 560)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: 560, height: 560)
                host.layoutSubtreeIfNeeded()
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let image = try #require(rep.cgImage)
                #expect(image.width >= 560)
                try DiagramSnapshotTests.writePNG(
                    image,
                    to: DiagramSnapshotTests
                        .screenshotDirectory.deletingLastPathComponent()
                        .appending(
                            path: "instrument-settings/\(name)-\(dark ? "dark" : "light").png",
                        ),
                )
            }
        }
    }
}

/// Collects the `segue.feature` values an analytics hub records (a real hub writing to a
/// recording log, as `SectionNotesUITests` does).
@MainActor
struct RecordingAnalytics {
    let env: TestEnvironment
    let log: RecordingLog

    init(_ env: TestEnvironment) {
        self.env = env
        log = RecordingLog(url: env.scratch.appending(path: "services.jsonl"))
    }

    var hub: ServicesHub {
        ServicesHub(
            factory: RecordingServicesFactory(log: log),
            consent: ConsentState(analytics: .granted(.now), crashReports: .declined(.now)),
            throttle: AnalyticsThrottle(suiteName: env.suiteName, clock: env.clock),
        )
    }

    var features: [String] {
        log.entries().compactMap { entry in
            (entry["params"] as? [String: String])?["segue.feature"]
        }
    }
}
