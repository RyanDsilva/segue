import Foundation
import Services

/// The always-included system information of a bug report (WS3 spec 8.2 item 5). No serial
/// number, host name, user name or path: only versions, the model identifier, the CPU
/// architecture, the preferred language, library size buckets and the consent states.
enum SystemInfo {
    /// The library's size, reported only as buckets.
    struct LibraryCounts: Equatable {
        var songs = 0
        var setlists = 0
        var gigs = 0
    }

    static func make(
        flavor: AppFlavor,
        library: LibraryCounts,
        consent: ConsentState,
        logBytes: Int,
        bundle: Bundle = .main,
    ) -> FeedbackSystemInfo {
        let info = bundle.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let effective = consent.effective
        return FeedbackSystemInfo(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info["CFBundleVersion"] as? String ?? "unknown",
            flavor: flavor.rawValue,
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            modelIdentifier: modelIdentifier,
            architecture: architecture,
            preferredLanguage: Locale.preferredLanguages.first ?? "unknown",
            songs: SongBucket(library.songs),
            setlists: SmallBucket(library.setlists),
            gigs: SmallBucket(library.gigs),
            analyticsConsent: describe(effective.analytics),
            crashReportsConsent: describe(effective.crashReports),
            logBytes: logBytes,
        )
    }

    static func describe(_ decision: ConsentState.Decision) -> String {
        switch decision {
        case .granted: "on"
        case .declined: "off"
        case .undecided: "not asked yet"
        }
    }

    /// `hw.model`, e.g. `Mac15,3`.
    static var modelIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
    }

    static var architecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }
}
