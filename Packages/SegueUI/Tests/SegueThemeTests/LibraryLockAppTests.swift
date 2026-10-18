import Foundation
@testable import SegueUI
import Support
import Testing

/// The cross-flavor library lock through the real `AppModel` (WS1 4.8g, B-2): a second
/// copy of Segue on an open library lands on the chooser with the in-use reason, and can
/// open it once the first copy has let go. Two `AppModel`s in one process stand in for the
/// Personal and App Store flavors: each session holds its own descriptor, which `flock`
/// treats exactly like a second process.
@MainActor
struct LibraryLockAppTests {
    @Test
    func `a second copy cannot open a library another copy has open`() async throws {
        let env = try TestEnvironment()
        var first: AppModel? = try await env.openApp()
        #expect(first?.session?.lock != nil)

        let second = env.app(override: env.libraryURL)
        await second.start()
        guard case .needsLibrary(.inUseByAnotherCopy) = second.state else {
            Issue.record("expected the in-use chooser, got \(second.state)")
            return
        }
        #expect(second.session == nil)

        // The first copy quits: its session and lock go with it.
        first = nil
        let third = try await env.openApp()
        #expect(third.session?.root == LibraryRoot(url: env.libraryURL))
    }
}
