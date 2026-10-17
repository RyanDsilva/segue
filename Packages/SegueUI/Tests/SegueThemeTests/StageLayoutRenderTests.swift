import AppKit
import CoreText
import Editing
import Library
import LiveLayout
@testable import SegueUI
import SwiftUI
import Testing

/// `StageTextMetrics` against real Core Text and SwiftUI, the phase 2 acceptance check
/// (every fixture up to 40 lines fits a 13" stage at 22pt), plan speed, and screenshots of
/// rendered plans in `.build/screenshots/layout/`.
@MainActor
struct StageLayoutRenderTests {
    typealias Support = StageLayoutSupport
    let metrics = StageTextMetrics()

    @Test(arguments: [
        (TextRole.lyric, "SchibstedGrotesk-Regular"),
        (.chord, "SchibstedGrotesk-Bold"),
        (.sectionLabel, "SchibstedGrotesk-Bold"),
        (.comment, "SchibstedGrotesk-Medium"),
        (.note, "SchibstedGrotesk-Medium"),
        (.cue, "SchibstedGrotesk-Bold"),
        (.collapsedRepeat, "SchibstedGrotesk-Regular"),
    ])
    func `each role measures in its bundled face`(role: TextRole, face: String) {
        let font = StageTextMetrics.ctFont(role, size: 22)
        #expect(CTFontCopyPostScriptName(font) as String == face)
        #expect(CTFontGetSize(font) == 22)
    }

    @Test
    func `verbatim lines measure in the system monospaced face`() {
        let font = StageTextMetrics.ctFont(.verbatim, size: 20)
        #expect(CTFontGetSymbolicTraits(font).contains(.traitMonoSpace))
        #expect(abs(metrics.width(of: "e|---3---|", role: .verbatim, size: 20)
                - metrics.width(of: "WWWWWWWWWW", role: .verbatim, size: 20)) < 0.01)
    }

    @Test
    func `extents come from the font`() {
        let lyric = metrics.extents(of: .lyric)
        #expect(abs(lyric.ascent - 0.977) < 0.01)
        #expect(abs(lyric.descent - 0.258) < 0.01)
        #expect(lyric.inkTop > 0.69 && lyric.inkTop < lyric.ascent)
    }

    @Test
    func `widths scale linearly with the size`() {
        let text = "Pyaar ki raah mein, hum tum saath hain"
        let small = metrics.width(of: text, role: .lyric, size: 10)
        let large = metrics.width(of: text, role: .lyric, size: 37.5)
        #expect(abs(large - small * 3.75) < 0.01)
    }

    /// Every run of every planned fixture: the plan's width equals Core Text's width of the
    /// run on its own (trailing whitespace excluded), to within kerning at the run's edges.
    @Test
    func `planned run widths match Core Text`() throws {
        var worst = 0.0
        for name in Support.fixtureNames {
            let model = try Support.model(name)
            let request = LayoutRequest(
                model: model,
                viewport: Support.stages[0].size,
                minLyricSize: 22,
            )
            let plan = LayoutEngine.plan(request, metrics: metrics)
            for run in plan.columns.flatMap(\.blocks).flatMap(runs) {
                let font = StageTextMetrics.ctFont(run.role, size: run.size)
                let line = CTLineCreateWithAttributedString(NSAttributedString(
                    string: run.text,
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font],
                ))
                let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                    - CTLineGetTrailingWhitespaceWidth(line)
                let error = abs(width - run.width)
                worst = max(worst, error)
                #expect(
                    error < 0.75,
                    "\(name): \"\(run.text)\" planned \(run.width) drawn \(width)",
                )
            }
        }
        print("StageLayout: worst width difference \(worst)pt")
    }

    /// SwiftUI draws with the same faces: a `Text` in `StageTypography.font` is as wide as
    /// `StageTextMetrics` measured it.
    @Test(arguments: [
        (TextRole.lyric, "Lanterns on the water, drifting out to the bay"),
        (.chord, "D/F#"),
        (.chord, "Cmaj7"),
        (.sectionLabel, "Chorus x2"),
        (.comment, "Intro: D A Bm G"),
        (.note, "Start soft, capo 2"),
        (.cue, "Watch Ravi for the stop"),
        (.verbatim, "e|-----3---2---0----|"),
        (.lyric, "Crème brûlée on a rainy día"),
        (.lyric, "प्यार की राह में"),
    ])
    func `a SwiftUI Text matches the measured width`(role: TextRole, text: String) {
        let size = 26.0
        let hosting = NSHostingView(rootView: Text(text)
            .font(StageTypography.font(role, size: size))
            .fixedSize())
        let drawn = hosting.fittingSize.width
        let measured = metrics.width(of: text, role: role, size: size)
        // SwiftUI rounds its frame up to the pixel.
        #expect(abs(drawn - measured) <= 1, "\(text): SwiftUI \(drawn), measured \(measured)")
    }

    @Test
    func `every fixture up to forty lines fits a 13 inch stage at 22pt`() throws {
        var checked = 0
        for name in Support.fixtureNames {
            let model = try Support.model(name)
            guard Support.lyricLines(model) <= 40 else { continue }
            checked += 1
            for (stage, size) in Support.stages {
                let request = LayoutRequest(model: model, viewport: size, minLyricSize: 22)
                let plan = LayoutEngine.plan(request, metrics: metrics)
                #expect(plan.fit == .fits, "\(name) scrolls on \(stage)")
                #expect(plan.lyricSize >= 22)
                let issues = LayoutAudit.violations(of: plan, request: request, metrics: metrics)
                #expect(issues.isEmpty, "\(name) \(stage): \(issues.prefix(5))")
            }
        }
        #expect(checked >= 25)
    }

    /// Review finding 12: Devanagari matras reach well above Latin capitals. Each lyric
    /// row makes room for its own ink, so on every stage no lyric glyph (measured with Core
    /// Text glyph paths, fallback font included, as drawn) reaches into the chord band
    /// above it, and the audit (which now checks each run's own ink) agrees.
    @Test
    func `devanagari lyrics never reach into the chord band`() throws {
        let model = try Support.model("live-devanagari.cho")
        for (stage, size) in Support.stages {
            for zoom in [1.0, 1.4] {
                let request = LayoutRequest(
                    model: model, viewport: size, minLyricSize: 22, zoom: zoom,
                )
                let plan = LayoutEngine.plan(request, metrics: metrics)
                let issues = LayoutAudit.violations(of: plan, request: request, metrics: metrics)
                #expect(issues.isEmpty, "\(stage) zoom \(zoom): \(issues.prefix(3))")
                var checked = 0
                for row in plan.columns.flatMap(\.blocks).flatMap(\.allRows) {
                    guard let chordBaseline = row.chordBaseline, !row.chords.isEmpty else {
                        continue
                    }
                    let chordBottom = row.chords.map { chord in
                        chordBaseline - Self.glyphBounds(chord).minY
                    }.max() ?? chordBaseline
                    for run in row.text {
                        let inkTop = row.textBaseline - Self.glyphBounds(run).maxY
                        #expect(
                            inkTop >= chordBottom - 0.01,
                            "\(stage): \"\(run.text)\" ink at \(inkTop) above \(chordBottom)",
                        )
                        let inkBottom = row.textBaseline - Self.glyphBounds(run).minY
                        #expect(inkBottom <= row.height + 0.01, "\(stage): \"\(run.text)\" clipped")
                        checked += 1
                    }
                }
                #expect(checked >= 6)
            }
        }
    }

    /// The glyph-path bounds of a placed run, as drawn (y up from the baseline).
    private static func glyphBounds(_ run: PlacedText) -> CGRect {
        let font = StageTextMetrics.ctFont(run.role, size: run.size)
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        guard let string = CFAttributedStringCreate(nil, run.text as CFString, attributes) else {
            return .null
        }
        let line = CTLineCreateWithAttributedString(string)
        return CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    }

    @Test
    func `long and very long songs scroll at the minimum without clipping`() throws {
        for name in ["live-forty-lines.cho", "live-very-long.cho"] {
            let model = try Support.model(name)
            for minimum in [30.0, 48] {
                let request = LayoutRequest(
                    model: model,
                    viewport: Support.stages[0].size,
                    minLyricSize: minimum,
                )
                let plan = LayoutEngine.plan(request, metrics: metrics)
                #expect(plan.fit == .scrollsAtMinimum, "\(name) at \(minimum)")
                #expect(plan.lyricSize == minimum)
                let issues = LayoutAudit.violations(of: plan, request: request, metrics: metrics)
                #expect(issues.isEmpty, "\(name): \(issues.prefix(5))")
            }
        }
    }

    /// Cold: a song whose lines Core Text has never measured (chord widths are cached
    /// across songs, as on stage). Warm: the same song re-planned for a new viewport or zoom.
    @Test
    func `a long song plans within budget`() throws {
        let source = try String(
            contentsOf: Support.fixtures.appending(path: "live-very-long.cho"), encoding: .utf8,
        )
        let clock = ContinuousClock()
        _ = try LayoutEngine.plan(
            LayoutRequest(
                model: Support.model("basic-verse-chorus.cho"),
                viewport: Support.stages[0].size,
                minLyricSize: 22,
            ),
            metrics: metrics,
        )
        var cold = Duration.zero
        var warm = Duration.zero
        for step in 0 ..< 10 {
            // Distinct lyrics per run, so no line measurement is cached.
            let variant = source.replacingOccurrences(of: "\n[", with: "\n\(step) [")
            let model = Support.model(source: variant)
            cold += clock.measure {
                _ = LayoutEngine.plan(
                    LayoutRequest(model: model, viewport: Support.stages[0].size, minLyricSize: 22),
                    metrics: metrics,
                )
            }
            warm += clock.measure {
                _ = LayoutEngine.plan(
                    LayoutRequest(model: model, viewport: Support.stages[1].size, minLyricSize: 22),
                    metrics: metrics,
                )
            }
        }
        #if DEBUG
            let budget = Duration.milliseconds(80)
        #else
            let budget = Duration.milliseconds(8)
        #endif
        print("StageLayout: long song plan cold \(cold / 10), warm \(warm / 10)")
        #expect(cold / 10 < budget, "cold \(cold / 10) per plan")
        #expect(warm / 10 < budget, "warm \(warm / 10) per plan")
    }

    @Test
    func `screenshots of rendered plans`() throws {
        let cues = [SongCue(section: "Chorus", occurrence: 1, text: "Watch Ravi for the stop")]
        let shots: [Shot] = [
            Shot("basic-verse-chorus.cho", "basic-13in", cues: cues, notes: ["Start soft"]),
            Shot("basic-verse-chorus.cho", "basic-expanded-16in", stage: 1, collapse: false),
            Shot("live-forty-lines.cho", "forty-lines-13in"),
            Shot("live-forty-lines.cho", "forty-lines-1080p", stage: 2),
            Shot("live-devanagari.cho", "devanagari-13in", metrics: true),
            Shot("hindi-dil-kabhie.cho", "dil-kabhie-16in", stage: 1),
            Shot("live-very-long.cho", "very-long-scroll-13in"),
            Shot("unicode-lyrics.cho", "unicode-zoomed-13in", zoom: 1.4, metrics: true),
        ]
        for shot in shots {
            let request = try LayoutRequest(
                model: Support.model(shot.fixture),
                viewport: Support.stages[shot.stage].size,
                minLyricSize: 22,
                zoom: shot.zoom,
                collapseRepeats: shot.collapse,
                cues: shot.cues,
                notes: shot.notes,
            )
            let plan = LayoutEngine.plan(request, metrics: metrics)
            try Support.writeScreenshot(plan, name: shot.name, showMetrics: shot.metrics)
            let summary = "\(plan.lyricSize)pt \(plan.columns.count) col \(plan.fit)"
            print("StageLayout: \(shot.name) \(summary)")
        }
    }

    private func runs(_ block: LayoutBlock) -> [PlacedText] {
        var runs = block.allRows.flatMap { $0.chords + $0.text }
        runs += block.labelLines.map(\.text) + block.cues.flatMap(\.lines).map(\.text)
        if case let .collapsed(line, _) = block.content {
            runs.append(line)
        }
        return runs
    }
}

/// One screenshot: a fixture on a stage, with request variations.
struct Shot {
    var fixture: String
    var name: String
    var stage = 0
    var zoom = 1.0
    var collapse = true
    var cues: [SongCue] = []
    var notes: [String] = []
    /// Underline each run at its measured width.
    var metrics = false

    init(
        _ fixture: String,
        _ name: String,
        stage: Int = 0,
        zoom: Double = 1,
        collapse: Bool = true,
        cues: [SongCue] = [],
        notes: [String] = [],
        metrics: Bool = false,
    ) {
        self.fixture = fixture
        self.name = name
        self.stage = stage
        self.zoom = zoom
        self.collapse = collapse
        self.cues = cues
        self.notes = notes
        self.metrics = metrics
    }
}
