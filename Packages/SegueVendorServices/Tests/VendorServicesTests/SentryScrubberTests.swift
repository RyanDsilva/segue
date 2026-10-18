import Foundation
import SentrySwift
import Testing
@testable import VendorServices

/// Spec 14.2-7: the scrubber removes or replaces every kind of user data a crash event can
/// carry, and drops everything once revoked.
struct SentryScrubberTests {
    private static let live = SentryScrubber.Context(
        revoked: false,
        libraryRoot: "/Volumes/Gigs/Segue Library",
    )

    private static func frame(_ file: String, package: String) -> Frame {
        let frame = Frame()
        frame.fileName = file
        frame.package = package
        frame.function = "LibraryStore.save()"
        frame.contextLine = "let title = \"Tum Hi Ho\""
        return frame
    }

    private static func event() -> Event {
        let event = Event(level: .fatal)
        event.serverName = "Ryans-MacBook-Pro.local"
        let user = User(userId: "INSTALL-1234")
        user.email = "ryan@example.com"
        user.ipAddress = "203.0.113.7"
        user.username = "ryan"
        user.name = "Ryan"
        user.data = ["plan": "pro"]
        event.user = user
        event.extra = ["lastSong": "Tum Hi Ho"]
        event.tags = ["folder": "/Users/ryan/Music/Segue/songs/tum-hi-ho.cho"]
        event.message = SentryMessage(formatted: "Couldn't open \"Tum Hi Ho.cho\" in /Users/ryan")
        event.context = [
            "device": ["name": "Ryan's MacBook Pro", "model": "Mac15,3", "arch": "arm64"],
            "app": ["app_identifier": "dev.ryandsilva.segue", "path": "/Users/ryan/Apps/Segue"],
        ]
        let exception = Exception(
            value: "File /Users/ryan/Music/Segue/songs/secret-title.cho could not be saved: "
                + String(repeating: "x", count: 400),
            type: "NSInvalidArgumentException",
        )
        exception.stacktrace = SentryStacktrace(
            frames: [frame(
                "/Users/ryan/src/segue/LibraryStore.swift",
                package: "/Users/ryan/Applications/Segue.app/Contents/MacOS/Segue",
            )],
            registers: [:],
        )
        event.exceptions = [exception]
        let debugImage = DebugMeta()
        debugImage.codeFile = "/Users/ryan/Applications/Segue.app/Contents/MacOS/Segue"
        event.debugMeta = [debugImage]
        let ours = Breadcrumb(level: .info, category: "segue")
        ours.message = "Segue.Show.started"
        let foreign = Breadcrumb(level: .info, category: "ui.click")
        foreign.message = "Clicked \"Tum Hi Ho\""
        event.breadcrumbs = [ours, foreign]
        return event
    }

    @Test
    func `an event keeps only the install id and loses every path, name and title`() throws {
        let scrubbed = try #require(SentryScrubber.event(Self.event(), context: Self.live))

        #expect(scrubbed.user?.userId == "INSTALL-1234")
        #expect(scrubbed.user?.email == nil)
        #expect(scrubbed.user?.ipAddress == nil)
        #expect(scrubbed.user?.username == nil)
        #expect(scrubbed.user?.name == nil)
        #expect(scrubbed.user?.data == nil)
        #expect(scrubbed.serverName == nil)
        #expect(scrubbed.extra == nil)
        #expect(scrubbed.request == nil)
        #expect(scrubbed.context?["device"]?["name"] == nil)
        #expect(scrubbed.context?["device"]?["model"] as? String == "Mac15,3")
        #expect(scrubbed.breadcrumbs?.map(\.category) == ["segue"])

        let exception = try #require(scrubbed.exceptions?.first)
        let value = try #require(exception.value)
        #expect(value.count <= 200)
        #expect(value.hasPrefix("File <library>/<file>"))
        let frame = try #require(exception.stacktrace?.frames.first)
        #expect(frame.fileName == "/Users/<user>/src/segue/LibraryStore.swift")
        #expect(frame.package == "/Users/<user>/Applications/Segue.app/Contents/MacOS/Segue")
        #expect(frame.contextLine == nil)
        #expect(scrubbed.debugMeta?.first?.codeFile?.hasPrefix("/Users/<user>/") == true)
        #expect(scrubbed.message?.formatted == "Couldn't open \"<song file>\" in /Users/<user>")
        #expect(scrubbed.tags?["folder"] == "<library>/<file>")
        #expect(scrubbed.context?["app"]?["path"] as? String == "/Users/<user>/Apps/Segue")

        // No trace of the user's name, titles or file names anywhere in the serialised event.
        let json = try JSONSerialization.data(withJSONObject: scrubbed.serialize())
        let text = try #require(String(bytes: json, encoding: .utf8))
        let secrets = [
            "Users\\/ryan", "ryan@", "\"ryan\"", "\"Ryan\"", "Ryan's", "Tum Hi Ho",
            "secret-title", "203.0.113.7", "MacBook", "lastSong", "plan",
        ]
        for secret in secrets {
            #expect(!text.contains(secret), "\(secret) in \(text)")
        }
    }

    @Test
    func `revoked drops every event and breadcrumb`() {
        let revoked = SentryScrubber.Context(revoked: true)
        #expect(SentryScrubber.event(Self.event(), context: revoked) == nil)
        let crumb = Breadcrumb(level: .info, category: "segue")
        #expect(SentryScrubber.breadcrumb(crumb, context: revoked) == nil)
        #expect(SentryScrubber.breadcrumb(crumb, context: Self.live) != nil)
        let foreign = Breadcrumb(level: .info, category: "navigation")
        #expect(SentryScrubber.breadcrumb(foreign, context: Self.live) == nil)
    }

    @Test(arguments: [
        ("/Users/ryan/Library/Caches/x", "/Users/<user>/Library/Caches/x"),
        ("open /Users/ryan/Music/My Songs/a b.cho failed", "open <library>/<file>"),
        ("/Volumes/Gigs/Segue Library/songs/x.cho", "<library>/<file>"),
        ("saved tum-hi-ho.segue.json", "saved <song file>"),
        ("saved 'Tum Hi Ho.cho' ok", "saved '<song file>' ok"),
        ("EXC_BAD_ACCESS at 0x10", "EXC_BAD_ACCESS at 0x10"),
    ])
    func `strings are scrubbed`(input: String, expected: String) {
        #expect(SentryScrubber.scrub(input, libraryRoot: Self.live.libraryRoot) == expected)
    }

    @Test
    func `thin MetricKit CPU and disk-write diagnostics are dropped, hangs are kept`() {
        func metricKit(_ type: String, frames: Int) -> Event {
            let event = Event(level: .warning)
            let exception = Exception(value: "\(type) totalCPUTime", type: type)
            exception.stacktrace = SentryStacktrace(
                frames: (0 ..< frames).map { _ in Frame() },
                registers: [:],
            )
            event.exceptions = [exception]
            return event
        }
        #expect(SentryScrubber
            .event(metricKit("MXCPUException", frames: 2), context: Self.live) == nil)
        #expect(SentryScrubber.event(
            metricKit("MXDiskWriteException", frames: 0),
            context: Self.live,
        ) == nil)
        #expect(SentryScrubber
            .event(metricKit("MXCPUException", frames: 3), context: Self.live) != nil)
        #expect(SentryScrubber
            .event(metricKit("MXHangDiagnostic", frames: 1), context: Self.live) != nil)
    }
}
