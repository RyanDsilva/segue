import AppKit
import Foundation
import Playback
@testable import SegueUI
import Services
import SwiftUI
import Testing

/// Settings > Audio (P8-6 sections 11, 15.2): the store over a real defaults suite, lenient
/// decoding, Reset All Settings, the sounds reaching the player, and the pane in light and
/// dark. The output picker is P8-6c's.
@MainActor
struct AudioSettingsStoreTests {
    @Test
    func `defaults, persisting and resetting`() throws {
        let env = try TestEnvironment()
        let store = AudioSettingsStore(defaults: env.defaults)
        #expect(store.settings == AudioSettings(
            chordSound: .piano,
            chordStyle: .strum,
            bassSound: .finger,
            volume: 0.7,
        ))
        store.update {
            $0.chordSound = .cleanGuitar
            $0.chordStyle = .block
            $0.bassSound = .pick
            $0.volume = 1.4
        }
        let reloaded = AudioSettingsStore(defaults: env.defaults)
        #expect(reloaded.settings.chordSound == .cleanGuitar)
        #expect(reloaded.settings.chordStyle == .block)
        #expect(reloaded.settings.bassSound == .pick)
        #expect(reloaded.settings.volume == 1)
        reloaded.resetToDefaults()
        #expect(AudioSettingsStore(defaults: env.defaults).settings == AudioSettings())
    }

    @Test
    func `an unreadable field keeps its default, the rest is kept`() throws {
        let env = try TestEnvironment()
        let json = #"{"chordSound": "harp", "chordStyle": "block", "volume": "loud"}"#
        env.defaults.set(Data(json.utf8), forKey: AudioSettingsStore.defaultsKey)
        let settings = AudioSettingsStore(defaults: env.defaults).settings
        #expect(settings.chordSound == .piano)
        #expect(settings.chordStyle == .block)
        #expect(settings.volume == 0.7)
    }

    @Test
    func `clean guitar is recorded once and the player prepares the chosen sounds`() throws {
        let env = try TestEnvironment()
        let recorder = RecordingAnalytics(env)
        let rig = SoundRig(env, services: recorder.hub)
        rig.session.settings.update { $0.chordSound = .cleanGuitar }
        rig.session.settings.update { $0.chordStyle = .block }
        rig.session.settings.update { $0.bassSound = .pick }
        #expect(recorder.features == ["chordSoundGuitar"])
        rig.session.testSound()
        #expect(rig.outputs.last?.calls.first == .prepare(.cleanGuitar, .pick))
        #expect(rig.notes(.bass) == [31])
    }

    @Test
    func `resetting all settings resets Settings > Audio`() async throws {
        let env = try TestEnvironment()
        let app = AppModel(dependencies: env.dependencies(
            location: env.location(),
            override: env.libraryURL,
            remember: false,
        ))
        await app.start()
        app.sound.settings.update { $0.volume = 0.2 }
        app.resetAllSettings()
        #expect(app.sound.settings.settings == AudioSettings())
        #expect(DataSettingsView.resetMessage.contains("Audio"))
    }

    @Test
    func `the pane renders in light and dark`() throws {
        let env = try TestEnvironment()
        let rig = SoundRig(env)
        for dark in [false, true] {
            let view = AudioSettingsView(sound: rig.session).frame(width: 560, height: 360)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 360)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = try #require(rep.cgImage)
            #expect(image.width >= 560)
            try DiagramSnapshotTests.writePNG(
                image,
                to: DiagramSnapshotTests.screenshotDirectory.deletingLastPathComponent()
                    .appending(path: "audio-settings/\(dark ? "dark" : "light").png"),
            )
        }
    }
}
