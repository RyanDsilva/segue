import Foundation
@testable import Ingest
import Testing

/// The romanized-Hindi flag of `Segue.AI.pasteFinished` (R98) over the golden paste
/// fixtures: it fires on every Hinglish fixture (`H*`) and on no English one (`E*`).
struct RomanizedHindiTests {
    @Test(arguments: PasteFixtures.names)
    func `the flag follows the fixture's language`(name: String) throws {
        let result = try PasteFixtures.ingest(name)
        #expect(RomanizedHindi.isDetected(in: result) == name.hasPrefix("H"))
    }
}
