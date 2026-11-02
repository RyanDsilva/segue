import Foundation
import Testing

@Suite("Fixture bundle")
struct FixtureBundleTests {
    @Test
    func `the committed fixtures folder ships with the test bundle`() throws {
        let url = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "web/README.md").path))
    }
}
