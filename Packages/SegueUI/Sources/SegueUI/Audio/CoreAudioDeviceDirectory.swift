#if os(macOS)
    import CoreAudio
    import Foundation

    /// The Mac's output devices from CoreAudio (P8-6 section 11), read through
    /// `CoreAudioDevices`. Listens to the device list and the system output once `onChange`
    /// is set. Read-only: it never changes the system's choice.
    @MainActor
    public final class CoreAudioDeviceDirectory: AudioDeviceDirectory {
        public var onChange: (@MainActor () -> Void)? {
            didSet { listen() }
        }

        private var listening = false

        public init() {}

        public func outputs() -> [AudioOutputDevice] {
            CoreAudioDevices.outputs()
        }

        public func defaultOutput() -> AudioOutputDevice? {
            CoreAudioDevices.defaultOutput()
        }

        private func listen() {
            guard onChange != nil, !listening else { return }
            listening = true
            for selector in [
                kAudioHardwarePropertyDevices,
                kAudioHardwarePropertyDefaultOutputDevice,
            ] {
                var address = CoreAudioDevices.address(selector)
                // Lives as long as the process (the app's one directory); never removed.
                AudioObjectAddPropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    .main,
                ) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.onChange?() }
                }
            }
        }
    }

    /// CoreAudio property reads, callable from any thread (the engine host resolves its
    /// device on its own queue): `kAudioHardwarePropertyDevices` filtered to devices with an
    /// output stream and not hidden, each with its UID, name and transport.
    enum CoreAudioDevices {
        static func outputs() -> [AudioOutputDevice] {
            deviceIDs().compactMap(device)
        }

        static func defaultOutput() -> AudioOutputDevice? {
            guard let id = uint32(
                AudioObjectID(kAudioObjectSystemObject),
                kAudioHardwarePropertyDefaultOutputDevice,
            ), id != kAudioObjectUnknown
            else { return nil }
            return device(id)
        }

        /// The output device with `uid` now, if it is connected
        /// (`kAudioHardwarePropertyTranslateUIDToDevice`).
        static func deviceID(forUID uid: String) -> AudioDeviceID? {
            var address = address(kAudioHardwarePropertyTranslateUIDToDevice)
            var id = AudioDeviceID(0)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var name = uid as CFString
            let status = withUnsafePointer(to: &name) { pointer in
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    UInt32(MemoryLayout<CFString>.size),
                    pointer,
                    &size,
                    &id,
                )
            }
            guard status == noErr, id != kAudioObjectUnknown, hasOutput(id) else { return nil }
            return id
        }

        static func address(
            _ selector: AudioObjectPropertySelector,
            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        ) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: scope,
                mElement: kAudioObjectPropertyElementMain,
            )
        }

        private static func deviceIDs() -> [AudioDeviceID] {
            var address = address(kAudioHardwarePropertyDevices)
            let system = AudioObjectID(kAudioObjectSystemObject)
            var size = UInt32(0)
            guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr
            else { return [] }
            var ids = [AudioDeviceID](
                repeating: 0,
                count: Int(size) / MemoryLayout<AudioDeviceID>.size,
            )
            guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr
            else { return [] }
            return ids
        }

        private static func device(_ id: AudioDeviceID) -> AudioOutputDevice? {
            guard hasOutput(id), uint32(id, kAudioDevicePropertyIsHidden) != 1,
                  let uid = string(id, kAudioDevicePropertyDeviceUID)
            else { return nil }
            return AudioOutputDevice(
                uid: uid,
                name: string(id, kAudioObjectPropertyName) ?? uid,
                transport: transport(uint32(id, kAudioDevicePropertyTransportType)),
            )
        }

        private static func hasOutput(_ id: AudioDeviceID) -> Bool {
            var address = address(
                kAudioDevicePropertyStreams,
                scope: kAudioObjectPropertyScopeOutput,
            )
            var size = UInt32(0)
            return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
        }

        private static func transport(_ value: UInt32?) -> AudioOutputDevice.Transport {
            switch value {
            case kAudioDeviceTransportTypeBluetooth,
                 kAudioDeviceTransportTypeBluetoothLE: .bluetooth
            case kAudioDeviceTransportTypeBuiltIn: .builtIn
            case kAudioDeviceTransportTypeDisplayPort,
                 kAudioDeviceTransportTypeHDMI: .hdmi
            case kAudioDeviceTransportTypeUSB: .usb
            default: .other
            }
        }

        private static func uint32(
            _ id: AudioObjectID,
            _ selector: AudioObjectPropertySelector,
        ) -> UInt32? {
            var address = address(selector)
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr
            else { return nil }
            return value
        }

        private static func string(
            _ id: AudioObjectID,
            _ selector: AudioObjectPropertySelector,
        ) -> String? {
            var address = address(selector)
            var value: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
                  let value
            else { return nil }
            return value.takeRetainedValue() as String
        }
    }
#endif
