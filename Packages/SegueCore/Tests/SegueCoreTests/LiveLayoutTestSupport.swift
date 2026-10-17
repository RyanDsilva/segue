import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// Fixtures, stage sizes and helpers for the live layout suites.
enum LiveLayoutSupport {
    /// Stage body (between header and footer) on each screen: the screen less the stage's
    /// 48pt side padding, a 100pt header, a 64pt footer and 24pt above and below the body.
    static func body(screenWidth: Double, screenHeight: Double) -> LayoutSize {
        LayoutSize(width: screenWidth - 96, height: screenHeight - 100 - 64 - 48)
    }

    static let macBook13 = body(screenWidth: 1470, screenHeight: 956)
    static let macBook16 = body(screenWidth: 1728, screenHeight: 1117)
    static let external = body(screenWidth: 1920, screenHeight: 1080)

    /// Fixed advances close to Schibsted Grotesk Regular (0.44 em on average).
    static let schibstedLike = FixedAdvanceMetrics(factor: 0.45)

    static let stages: [(name: String, size: LayoutSize)] = [
        ("13in", macBook13), ("16in", macBook16), ("1080p", external),
    ]

    static func model(_ name: String) throws -> RenderModel {
        try model(source: EditingFixtures.load(name))
    }

    static func model(source: String) -> RenderModel {
        RenderModel(document: ChordProParser.parse(source).0, options: DisplayOptions())
    }

    static func plan(
        _ model: RenderModel,
        viewport: LayoutSize = macBook13,
        minLyricSize: Double = 22,
        zoom: Double = 1,
        collapseRepeats: Bool = true,
        columns: Int? = nil,
        cues: [SongCue] = [],
        notes: [String] = [],
        metrics: any TextMeasuring = FixedAdvanceMetrics(),
    ) -> (LayoutPlan, LayoutRequest) {
        let request = LayoutRequest(
            model: model,
            viewport: viewport,
            minLyricSize: minLyricSize,
            zoom: zoom,
            collapseRepeats: collapseRepeats,
            columns: columns,
            cues: cues,
            notes: notes,
        )
        return (LayoutEngine.plan(request, metrics: metrics), request)
    }

    /// Lyric lines in the source (not counting `{chorus}` repeats).
    static func sourceLyricLines(_ model: RenderModel) -> Int {
        model.sections.flatMap(\.items).count { item in
            if case .lyrics = item {
                return true
            }
            return false
        }
    }

    /// A song of `count` lines in sections of `perSection` lines (`0` = one section).
    static func longSong(lines count: Int, perSection: Int = 4) -> String {
        var lines = ["{title: Generated}"]
        for index in 0 ..< count {
            if perSection > 0, index.isMultiple(of: perSection) {
                if index > 0 {
                    lines.append("{end_of_verse}")
                }
                lines.append("{start_of_verse: Verse \(index / perSection + 1)}")
            }
            lines.append("[G]Line \(index) of the [C]song [D]here")
        }
        if perSection > 0 {
            lines.append("{end_of_verse}")
        }
        return lines.joined(separator: "\n")
    }
}

extension LayoutPlan {
    var blocks: [LayoutBlock] {
        columns.flatMap(\.blocks)
    }

    func block(id: Int) -> LayoutBlock? {
        blocks.first { $0.id == id }
    }
}
