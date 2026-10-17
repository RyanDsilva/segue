import Foundation
import Support
import Testing

/// Scaffold smoke tests: prove the test target, fixtures bundle and Support basics work.
/// Real integration suites (library, setlists, parser corpus) are added alongside.
struct ScaffoldTests {
    @Test
    func `fixtures directory is bundled`() throws {
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        #expect(LiveFileSystem().directoryExists(at: fixtures))
    }

    @Test
    func `ULID round trips and is monotonic under a frozen clock`() {
        let generator = ULIDGenerator(clock: ManualClock(), seed: 42)
        let first = generator.next()
        let second = generator.next()
        #expect(first < second)
        #expect(first.description.count == 26)
        #expect(ULID(string: first.description) == first)
        #expect(first.timestamp == ManualClock().now())

        let replay = ULIDGenerator(clock: ManualClock(), seed: 42)
        #expect(replay.next() == first)
    }
}
