import Foundation
import Testing
@testable import VendorServices

/// `VendorConfig` from the Info.plist keys: real values parse, anything missing or malformed
/// yields nil (Null adapters, "not part of this build").
struct VendorConfigTests {
    static var info: [String: Any] {
        [
            "SegueSentryDSN": "https://997bf383bbb7edd32a15c839fba202b8@o4512275137691648.ingest.us.sentry.io/4512275142475776",
            "SegueTelemetryDeckAppID": "6E38DC85-EE5E-4ECF-A8E0-E4FDFDE9B208",
            "SegueTelemetryDeckNamespace": "dev.ryandsilva",
            "CFBundleIdentifier": "dev.ryandsilva.segue.personal",
            "CFBundleShortVersionString": "0.5",
            "CFBundleVersion": "7",
        ]
    }

    @Test
    func `the shipped values parse`() throws {
        let config = try #require(VendorConfig(info: Self.info))
        #expect(config.sentryDSN.host == "o4512275137691648.ingest.us.sentry.io")
        #expect(config.sentryDSN.projectID == "4512275142475776")
        #expect(
            config.sentryDSN.envelopeURL.absoluteString
                == "https://o4512275137691648.ingest.us.sentry.io/api/4512275142475776/envelope/",
        )
        #expect(config.telemetryDeckAppID == "6E38DC85-EE5E-4ECF-A8E0-E4FDFDE9B208")
        #expect(
            config.telemetryDeckEndpoint.absoluteString
                == "https://nom.telemetrydeck.com/v2/namespace/dev.ryandsilva/",
        )
        #expect(config.sentryReleaseName == "dev.ryandsilva.segue.personal@0.5+7")
    }

    @Test(arguments: [
        ("SegueSentryDSN", ""),
        ("SegueSentryDSN", "$(SEGUE_SENTRY_DSN)"),
        ("SegueSentryDSN", "http://abc@o1.ingest.us.sentry.io/1"),
        ("SegueTelemetryDeckAppID", ""),
        ("SegueTelemetryDeckAppID", "not-a-uuid"),
        ("SegueTelemetryDeckNamespace", "bad namespace/../"),
        ("CFBundleVersion", ""),
    ])
    func `missing or malformed values yield no config`(key: String, value: String) {
        var info = Self.info
        info[key] = value
        #expect(VendorConfig(info: info) == nil)
    }

    @Test
    func `an empty namespace uses the bare v2 endpoint`() throws {
        var info = Self.info
        info["SegueTelemetryDeckNamespace"] = ""
        let config = try #require(VendorConfig(info: info))
        #expect(config.telemetryDeckNamespace == nil)
        #expect(config.telemetryDeckEndpoint.absoluteString == "https://nom.telemetrydeck.com/v2/")
    }

    @Test
    func `mode follows the environment`() {
        #expect(VendorEnvironment.debug.isTestMode)
        #expect(VendorEnvironment.testflight.isTestMode)
        #expect(!VendorEnvironment.personal.isTestMode)
        #expect(!VendorEnvironment.production.isTestMode)
    }
}
