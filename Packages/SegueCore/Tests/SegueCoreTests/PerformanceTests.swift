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
    @Test
    func `a 2000-song library reopens and refreshes without re-reading files`() async throws {
        let lib = try TestLibrary()
        let songCount = 2000
        for number in 0 ..< songCount {
            let source = RomanizedHindiFixtures.songs[number % RomanizedHindiFixtures.songs.count]
                .replacingOccurrences(of: "{title: ", with: "{title: \(number) ")
            try lib.write(source, to: "songs/song-\(number).cho")
        }
        var store: LibraryStore?
        let firstOpen = try await Self.time { store = try await lib.openStore() }
        let opened = try #require(store)
        #expect(try await opened.allSongs().count == songCount)

        let refresh = try await Self.time {
            let summary = try await opened.refresh()
            #expect(summary == RefreshSummary())
        }
        let relaunch = try await Self.time { store = try await lib.openStore() }
        let relaunched = try #require(store)
        #expect(try await relaunched.refresh() == RefreshSummary())
        let rebuild = try await Self.time { try await relaunched.rebuildIndex() }

        print("""
        [perf] \(songCount) songs: first open (orphans + full index) \(firstOpen), \
        no-change refresh \(refresh), relaunch \(relaunch), rebuild index \(rebuild)
        """)
        // Before the short-circuit (2026-10-17, debug build): refresh 4.5 s, relaunch 4.6 s.
        // After: about 0.25 s and 0.5 s (0.45 s and 1.2 s with the rest of the suite running).
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
