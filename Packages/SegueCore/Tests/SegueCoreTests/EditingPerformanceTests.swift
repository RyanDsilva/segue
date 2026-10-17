import ChordPro
import Editing
import Foundation
import Testing

/// Keystroke-path timing for the editor (phase 1 acceptance 9: < 16 ms per keystroke on a
/// 200-line song). Like `PerformanceTests`, the limit is a catastrophic-regression guard
/// for debug builds on a loaded machine, not a benchmark; the measured time is printed.
@Suite(.serialized)
struct EditingPerformanceTests {
    @Test
    func `a keystroke on a 200-line song re-snapshots and re-renders quickly`() throws {
        let verse = try EditingFixtures.load("basic-verse-chorus.cho")
        var source = ""
        while source.split(separator: "\n", omittingEmptySubsequences: false).count < 200 {
            source += verse
        }
        let snapshot = SourceSnapshot(text: source)
        let line = try #require(snapshot.lyricLinePaths.dropFirst(40).first)
        let clock = ContinuousClock()
        var best = Duration.seconds(1)
        for round in 0 ..< 5 {
            let elapsed = try clock.measure {
                // One typed character, then everything the editor recomputes for it.
                let change = try DocumentEditor.change(
                    for: .editLyrics(
                        line,
                        range: 0 ..< 0,
                        replacement: round.isMultiple(of: 2)
                            ? "a" : "b",
                    ),
                    in: snapshot,
                )
                let next = SourceSnapshot(text: snapshot.text.applying(change.edits))
                _ = next.highlights(in: 0 ..< min(4000, next.text.utf16.count))
                _ = next.diagnostics
                _ = RenderModel(document: next.document, options: DisplayOptions(transpose: 2))
            }
            best = min(best, elapsed)
        }
        print("200-line keystroke path, best of 5: \(best)")
        #expect(best < .milliseconds(160), "best of 5: \(best)")
    }
}
