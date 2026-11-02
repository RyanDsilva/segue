import ChordPro
import Foundation
import Library
import Support
import Testing

/// Timing guards, run one at a time so they never compete with each other for CPU. The
/// limits are catastrophic-regression guards (several times the measured times on an M-series
/// Mac, below the times before the fix they protect), not benchmarks: a loaded machine must
/// not make them flake.
@Suite(.serialized)
struct PerformanceTests {
    @Test
    func `a 300-line song parses in under 50 ms`() {
        let verse = RomanizedHindiFixtures.songs[0]
        var source = ""
        var lineCount = 0
        while lineCount < 300 {
            source += verse
            lineCount += verse.split(separator: "\n", omittingEmptySubsequences: false).count - 1
        }
        let clock = ContinuousClock()
        var best = Duration.seconds(1)
        for _ in 0 ..< 5 {
            let elapsed = clock.measure { _ = ChordProParser.parse(source) }
            best = min(best, elapsed)
        }
        #expect(best < .milliseconds(50), "best of 5: \(best)")
    }

    /// 2000 songs: relaunch with an up-to-date index and a no-change refresh must not re-hash
    /// or re-index anything (mtime + size short-circuit, one index transaction per scan).
    /// 500 songs is the launch-time figure in docs/test-performance.md (P9-5 P4).
    @Test(arguments: [500, 2000])
    func `a large library reopens and refreshes without re-reading files`(
        songCount: Int,
    ) async throws {
        let lib = try TestLibrary()
        for number in 0 ..< songCount {
            let source = RomanizedHindiFixtures.songs[number % RomanizedHindiFixtures.songs.count]
                .replacingOccurrences(of: "{title: ", with: "{title: \(number) ")
            try lib.write(source, to: "songs/song-\(number).cho")
        }
        var store: LibraryStore?
        let firstOpen = try await Self.time { store = try await lib.openStore() }
        let opened = try #require(store)
        #expect(try await opened.allSongs().count == songCount)

        // Fastest of 3, as the parse guard above and LiveLayoutCorpusTests do: load (other
        // suites, other builds) only adds time, so the minimum tracks the real cost, while
        // the regression this guards (re-reading every file) is slow on every run.
        var refresh = Duration.seconds(60)
        for _ in 0 ..< 3 {
            let elapsed = try await Self.time {
                let summary = try await opened.refresh()
                #expect(summary == RefreshSummary())
            }
            refresh = min(refresh, elapsed)
        }
        var relaunch = Duration.seconds(60)
        for _ in 0 ..< 3 {
            let elapsed = try await Self.time { store = try await lib.openStore() }
            relaunch = min(relaunch, elapsed)
        }
        let relaunched = try #require(store)
        #expect(try await relaunched.refresh() == RefreshSummary())
        let rebuild = try await Self.time { try await relaunched.rebuildIndex() }

        print("""
        [perf] \(songCount) songs: first open (orphans + full index) \(firstOpen), \
        no-change refresh (best of 3) \(refresh), relaunch (best of 3) \(relaunch), \
        rebuild index \(rebuild)
        """)
        // Before the short-circuit (2026-10-17, debug build): refresh 4.5 s, relaunch 4.6 s.
        // After: about 0.25 s and 0.5 s (0.45 s and 1.2 s with the rest of the suite running;
        // a single run failed under heavy CPU load, hence the best of 3).
        #expect(refresh < .seconds(2), "no-change refresh: \(refresh)")
        #expect(relaunch < .milliseconds(2500), "relaunch: \(relaunch)")
    }

    private static func time(_ work: () async throws -> Void) async throws -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        try await work()
        return clock.now - start
    }
}
