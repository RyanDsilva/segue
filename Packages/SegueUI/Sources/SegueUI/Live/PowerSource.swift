#if os(macOS)
    import Foundation
    import IOKit.ps

    /// Whether the Mac runs on its charger, for the pre-show checklist's "Charger connected"
    /// row.
    public protocol PowerSourceReading: Sendable {
        /// True on AC power, false on battery, nil when it cannot be told (no battery
        /// information, e.g. a desktop Mac reports AC power and returns true).
        func isOnCharger() -> Bool?
    }

    /// Reads the providing power source from IOKit.
    public struct SystemPowerSource: PowerSourceReading {
        public init() {}

        public func isOnCharger() -> Bool? {
            guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
            else { return nil }
            return (type as String) == kIOPSACPowerValue
        }
    }
#endif
