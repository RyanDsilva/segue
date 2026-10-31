import Foundation

/// An audio output device as Settings > Audio lists it (P8-6 section 11). Its name stays on
/// this Mac: analytics records only that a non-default output was chosen.
public struct AudioOutputDevice: Sendable, Hashable, Identifiable {
    /// How the device is connected; only `.usb` changes anything (the Settings note).
    public enum Transport: Sendable, Hashable {
        case builtIn
        case usb
        case bluetooth
        case hdmi
        case other
    }

    /// The device's persistent UID (`kAudioDevicePropertyDeviceUID`), what Settings stores.
    public var uid: String
    public var name: String
    public var transport: Transport

    public var id: String {
        uid
    }

    public init(uid: String, name: String, transport: Transport) {
        self.uid = uid
        self.name = name
        self.transport = transport
    }
}

/// The Mac's audio outputs (P8-6 section 11): the port behind the Play through picker, with
/// a CoreAudio adapter (`CoreAudioDeviceDirectory`) and a fixed list in tests. Each device
/// carries its transport, so there is no separate `transport(of:)`.
@MainActor
public protocol AudioDeviceDirectory: AnyObject {
    /// Every device with at least one output stream, in the system's order.
    func outputs() -> [AudioOutputDevice]
    /// The system output (Sound settings' choice); nil if there is none.
    func defaultOutput() -> AudioOutputDevice?
    /// Called on the main actor when a device comes or goes or the system output changes.
    /// Setting it starts listening.
    var onChange: (@MainActor () -> Void)? { get set }
}

/// A directory with a fixed list (in-process tests, and a platform without CoreAudio).
@MainActor
public final class FixedAudioDeviceDirectory: AudioDeviceDirectory {
    public var devices: [AudioOutputDevice] {
        didSet { onChange?() }
    }

    public var defaultUID: String? {
        didSet { onChange?() }
    }

    public var onChange: (@MainActor () -> Void)?

    public init(_ devices: [AudioOutputDevice] = [], defaultUID: String? = nil) {
        self.devices = devices
        self.defaultUID = defaultUID ?? devices.first?.uid
    }

    public func outputs() -> [AudioOutputDevice] {
        devices
    }

    public func defaultOutput() -> AudioOutputDevice? {
        devices.first { $0.uid == defaultUID }
    }
}
