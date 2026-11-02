import Foundation
@testable import SeguePersonalModules
import Testing

/// The committed, lyric-redacted pages (spec 16.2), read from the test bundle.
enum FixturePages {
    static func text(_ name: String) throws -> String {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return try String(contentsOf: root.appending(path: "web/\(name)"), encoding: .utf8)
    }

    static let ugURL = web("https://tabs.ultimate-guitar.com/tab/x/song-chords-1")
    static let echordsURL = web("https://www.e-chords.com/chords/x/song")
    static let chordieURL = web("https://www.chordie.com/chord.pere/www.example.com/song.html")
    static let genericURL = web("https://chords.example.com/song")
}
