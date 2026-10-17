import AppKit
import ChordPro
import Editing
@testable import SegueUI
import SwiftUI
import Testing

/// The song preview (`SongSheetView`) in a narrow column: a wrapped lyric line only gets a
/// chord band on the rows that carry chords, so no empty chord line opens up between rows.
@MainActor
struct SongSheetWrapTests {
    private static let width: CGFloat = 260

    private func height(_ source: String) -> CGFloat {
        let model = RenderModel(document: ChordProParser.parse(source).0, options: DisplayOptions())
        let view = SongSheetView(sections: model.sections, style: .preview)
            .frame(width: Self.width)
        return NSHostingView(rootView: view).fittingSize.height
    }

    @Test
    func `a wrapped row without chords has no empty chord band`() {
        let words = "lanterns on the water drifting out to the bay tonight"
        // Same words; one chord at the start, or a chord on the last word too (which wraps
        // onto the second row and so needs a chord band there).
        let oneChord = height("[G]\(words)")
        let bothRows = height("[G]\(words.replacingOccurrences(of: "tonight", with: "[D]tonight"))")
        let plain = height(words)
        let chordBand = SongSheetStyle.preview.chordSize
        // Without chords on its second row the line is one chord band shorter.
        #expect(bothRows - oneChord > chordBand * 0.8, "\(oneChord) vs \(bothRows)")
        // And exactly one chord band taller than the line with no chords at all.
        #expect(abs(oneChord - plain - (bothRows - oneChord)) < 2, "\(plain) \(oneChord)")
    }
}
