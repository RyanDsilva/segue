import ChordPro
import Editing
import Foundation
import LiveLayout
import Testing

/// The fitter over the whole fixture corpus on 13", 16" and 1080p stages: nothing clipped,
/// nothing overlapping, never below the minimum, and every song up to 40 lines fits at 22pt.
struct LiveLayoutCorpusTests {
    typealias Support = LiveLayoutSupport

    static let fixtures = EditingFixtures.names

    @Test(arguments: fixtures)
    func `every fixture plans soundly on every stage`(name: String) throws {
        let model = try Support.model(name)
        for (stage, size) in Support.stages {
            for minimum in [16.0, 22, 30, 48] {
                let (plan, request) = Support.plan(model, viewport: size, minLyricSize: minimum)
                let issues = LayoutAudit.violations(
                    of: plan, request: request, metrics: FixedAdvanceMetrics(),
                )
                #expect(issues.isEmpty, "\(name) \(stage) min \(minimum): \(issues.prefix(5))")
                #expect(plan.lyricSize >= minimum)
            }
        }
    }

    @Test(arguments: fixtures)
    func `songs up to forty lines fit every stage at the default minimum`(name: String) throws {
        let model = try Support.model(name)
        guard Support.sourceLyricLines(model) <= 40 else { return }
        for (stage, size) in Support.stages {
            let (plan, _) = Support.plan(model, viewport: size, metrics: Support.schibstedLike)
            #expect(plan.fit == .fits, "\(name) does not fit \(stage)")
            #expect(plan.lyricSize >= 22)
        }
    }

    @Test
    func `the very long fixture scrolls at the minimum`() throws {
        let model = try Support.model("live-very-long.cho")
        #expect(Support.sourceLyricLines(model) > 40)
        for (stage, size) in Support.stages {
            let (plan, request) = Support.plan(model, viewport: size)
            #expect(plan.fit == .scrollsAtMinimum, "\(stage)")
            #expect(plan.lyricSize == 22)
            #expect(LayoutAudit.violations(
                of: plan,
                request: request,
                metrics: FixedAdvanceMetrics(),
            )
            .isEmpty)
        }
    }

    @Test
    func `lyrics in both Hindi scripts lay out`() throws {
        for name in ["hindi-pyaar-ki-raah.cho", "hindi-dil-kabhie.cho", "live-devanagari.cho"] {
            let model = try Support.model(name)
            let (plan, request) = Support.plan(model)
            #expect(plan.fit == .fits, "\(name)")
            #expect(LayoutAudit.violations(
                of: plan,
                request: request,
                metrics: FixedAdvanceMetrics(),
            )
            .isEmpty)
            // Every lyric character survives layout, in order, line by line.
            var expected: [BlockPath: String] = [:]
            for case let .lyrics(line) in model.sections.flatMap(\.items) {
                expected[line.path] = line.lyrics.filter { !$0.isWhitespace }
            }
            // Per pass: a written-out repeat draws its chorus's lines again (R147).
            var passes: [[BlockPath: String]] = []
            for block in plan.blocks {
                var drawn: [BlockPath: String] = [:]
                for row in block.allRows where row.kind == .lyric {
                    guard let path = row.source else { continue }
                    drawn[path, default: ""] += row.text.map(\.text).joined()
                        .filter { !$0.isWhitespace }
                }
                passes.append(drawn)
            }
            #expect(passes.allSatisfy { drawn in
                drawn.allSatisfy { expected[$0.key] == $0.value }
            }, "\(name)")
            #expect(passes.contains { !$0.isEmpty })
        }
    }

    /// Best of 10, like `PerformanceTests`: load from parallel suites only ever adds time, so
    /// the fastest run is the closest estimate of what planning costs, while a real
    /// regression slows every run, the fastest included. (The mean of 10 failed at load 28.)
    @Test
    func `a long song plans quickly`() throws {
        let model = try Support.model("live-very-long.cho")
        let clock = ContinuousClock()
        _ = Support.plan(model)
        var best = Duration.seconds(10)
        for _ in 0 ..< 10 {
            best = min(best, clock.measure { _ = Support.plan(model) })
        }
        #if DEBUG
            let budget = Duration.milliseconds(40)
        #else
            let budget = Duration.milliseconds(8)
        #endif
        #expect(best < budget, "best of 10: \(best) per plan")
    }
}
