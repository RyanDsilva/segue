import AppKit
import Diagrams
import Foundation
import Playback
@testable import SegueUI
import Services
import SwiftUI
import Testing

/// Settings > Audio (P8-6 sections 11, 15.2): the store over a real defaults suite, lenient
/// decoding, Reset All Settings, the sounds reaching the player, and the pane in light and
/// dark; with a fixed device directory, the Play through picker, the not-connected
/// fallback, the stop on a device change and the USB note (P8-6c).
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
    func `the Test chord's bass follows the Settings strings and tuning`() throws {
        let env = try TestEnvironment()
        let rig = SoundRig(env, services: RecordingAnalytics(env).hub)
        let five = Tuning.bassStandard(strings: 5)
        #expect(SoundSession.testPlacement(five).tuning == five)
        #expect(SoundSession.testPlacement(.bassStandard4).home == 3)
        let dropD = Tuning(name: "Drop D", strings: [26, 33, 38, 43])
        rig.session.testSound(tuning: dropD)
        // Drop D puts G on the low string's fifth fret: still G1.
        #expect(SoundSession.testPlacement(dropD).home == 5)
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

    static let speakers = AudioOutputDevice(
        uid: "BuiltInSpeakerDevice",
        name: "MacBook Pro Speakers",
        transport: .builtIn,
    )
    static let ampero = AudioOutputDevice(
        uid: "AppleUSBAudioEngine:Hotone:Ampero II Stomp:1",
        name: "Ampero II Stomp",
        transport: .usb,
    )
    static let airPods = AudioOutputDevice(uid: "AA-BB", name: "AirPods", transport: .bluetooth)

    @Test
    func `a chosen output is remembered, falls back while gone and stops what plays`() throws {
        let env = try TestEnvironment()
        let recorder = RecordingAnalytics(env)
        let devices = FixedAudioDeviceDirectory([Self.speakers, Self.ampero, Self.airPods])
        let rig = SoundRig(env, services: recorder.hub, devices: devices)
        let session = rig.session
        #expect(session.systemOutputTitle == "System output (MacBook Pro Speakers)")
        #expect(session.outputChoices.map(\.title)
            == ["AirPods", "Ampero II Stomp", "MacBook Pro Speakers"])
        #expect(session.host.routedOutputUID == nil)

        session.chooseOutput(Self.ampero.uid)
        #expect(recorder.features == ["audioOutput"])
        #expect(session.host.routedOutputUID == Self.ampero.uid)
        let stored = AudioSettingsStore(defaults: env.defaults).settings
        #expect(stored.outputUID == Self.ampero.uid)
        #expect(stored.outputName == "Ampero II Stomp")

        // Unplugged while a chord sounds: it stops and says so, and the system output takes
        // over; the choice is kept and shown as not connected.
        session.testSound()
        let player = try #require(session.player)
        #expect(player.isPlaying)
        devices.devices = [Self.speakers, Self.airPods]
        #expect(!player.isPlaying)
        #expect(player.status == "Stopped: the audio output changed")
        #expect(rig.outputs.last?.stops == 1)
        #expect(session.host.routedOutputUID == nil)
        #expect(session.activeOutput == Self.speakers)
        #expect(session.outputChoices.last?.title == "Ampero II Stomp (not connected)")
        #expect(session.settings.settings.outputUID == Self.ampero.uid)

        // Plugged back in: the next sound uses it; nothing resumes by itself.
        devices.devices = [Self.speakers, Self.ampero, Self.airPods]
        #expect(session.host.routedOutputUID == Self.ampero.uid)
        #expect(!player.isPlaying)
        #expect(!session.outputChoices.contains { $0.title.hasSuffix("(not connected)") })

        // Back to the system output; analytics records only non-default choices.
        session.chooseOutput(nil)
        #expect(session.host.routedOutputUID == nil)
        #expect(session.settings.settings.outputName == nil)
        #expect(recorder.features == ["audioOutput"])
    }

    @Test
    func `the USB note shows only when sound goes to a USB interface`() throws {
        let env = try TestEnvironment()
        let devices = FixedAudioDeviceDirectory([Self.speakers, Self.ampero, Self.airPods])
        let rig = SoundRig(env, devices: devices)
        #expect(rig.session.usbNote == nil)
        rig.session.chooseOutput(Self.airPods.uid)
        #expect(rig.session.usbNote == nil)
        rig.session.chooseOutput(Self.ampero.uid)
        #expect(rig.session.usbNote == "Ampero II Stomp is a USB audio interface. Sound goes "
            + "wherever it is connected, such as an amp or PA.")
        // The system output itself can be the interface.
        rig.session.chooseOutput(nil)
        devices.defaultUID = Self.ampero.uid
        #expect(rig.session.usbNote?.hasPrefix("Ampero II Stomp") == true)
        devices.devices = [Self.speakers]
        devices.defaultUID = Self.speakers.uid
        #expect(rig.session.usbNote == nil)
    }

    @Test
    func `the pane renders in light and dark`() throws {
        let env = try TestEnvironment()
        let rig = SoundRig(env, devices: FixedAudioDeviceDirectory([Self.speakers, Self.ampero]))
        rig.session.chooseOutput(Self.ampero.uid)
        for dark in [false, true] {
            let view = AudioSettingsView(sound: rig.session).frame(width: 560, height: 460)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 460)
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
