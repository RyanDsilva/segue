import Foundation
import Library
import Printing
@testable import SegueUI
import Setlists
import Support
import Testing

/// P9-1 spec 7.3 / 14.4: a 20-song songbook, layout plus drawing, re-renders within the
/// budget. Run alone by `make test-perf` (the name ends in PerformanceTests).
@MainActor
@Suite(.serialized)
struct PDFRenderPerformanceTests {
    /// Spec 7.3: under 1 s on Apple Silicon.
    static let budget = Duration.seconds(1)

    static func songbook() -> PDFSnapshot {
        var records: [SongID: SongRecord] = [:]
        var entries: [SetlistEntry] = []
        for index in 0 ..< 20 {
            var source = "{title: Song \(index)}\n{artist: Band \(index)}\n{key: G}\n{tempo: 100}\n"
            for verse in 1 ... 4 {
                source += "{start_of_verse: Verse \(verse)}\n"
                source += (1 ... 4)
                    .map { "[G]Line \($0) of verse [C]\(verse) in [D]song [Em]\(index)" }
                    .joined(separator: "\n") + "\n{end_of_verse}\n"
                source += "{start_of_chorus}\n[C]Sing it [G]loud\n"
                    + "[D]Sing it [G]clear\n{end_of_chorus}\n"
            }
            let record = PDFTestSupport.record(source, index: UInt8(index))
            records[record.id] = record
            entries.append(SetlistEntry(itemId: PDFTestSupport.item(index), songId: record.id))
            if index == 9 {
                entries.append(SetlistEntry(
                    itemId: PDFTestSupport.item(99),
                    break: SetlistBreak(label: "Set 2"),
                ))
            }
        }
        return PDFTestSupport.snapshot(.setlist(
            Setlist(id: PDFTestSupport.setlistID(), name: "Long Set", entries: entries),
            records,
        ))
    }

    @Test
    func `a 20-song songbook re-renders within the budget`() async throws {
        let snapshot = Self.songbook()
        let options = PDFTestSupport.options()
        // Warm fonts and caches, then time a re-render as the sheet does on an option change.
        _ = try await PDFTestSupport.make(snapshot, options)
        let clock = ContinuousClock()
        var output: PDFExport.Output?
        let elapsed = try await clock.measure {
            output = try await PDFTestSupport.make(snapshot, options)
        }
        let pages = output?.pdf.pageCount ?? 0
        print("PDF songbook: 20 songs, \(pages) pages in \(elapsed)")
        #expect(pages > 20)
        #expect(elapsed < Self.budget, "20-song songbook took \(elapsed)")
    }
}
