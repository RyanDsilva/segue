import Foundation
import Library
import Setlists
import Support
import Testing

/// `SetlistTiming` (phase 2, unit D): start times, total and estimate count for the
/// builder's "library to set" layout.
struct SetlistTimingTests {
    private let songs = (0 ..< 4).map { index in
        SongID(ULID(milliseconds: 1, randomness: Array(repeating: UInt8(index), count: 10)))
    }

    private func entries(_ songIndexes: [Int]) -> [SetlistEntry] {
        songIndexes.enumerated().map { offset, index in
            SetlistEntry(
                itemId: SetlistItemID(ULID(
                    milliseconds: 2,
                    randomness: Array(repeating: UInt8(offset), count: 10),
                )),
                songId: songs[index],
            )
        }
    }

    @Test
    func `start times accumulate known lengths`() {
        let lengths = [
            songs[0]: SongLength(seconds: 220, source: .directive),
            songs[1]: SongLength(seconds: 192, source: .learned),
        ]
        let list = entries([0, 1, 0])
        let timing = SetlistTiming(entries: list, lengths: lengths, target: 2700)
        #expect(timing.items.map(\.start) == [0, 220, 412])
        #expect(timing.items.map(\.startIsApproximate) == [false, false, false])
        #expect(timing.items.map(\.itemId) == list.map(\.itemId))
        #expect(timing.items.map(\.length?.source) == [.directive, .learned, .directive])
        #expect(timing.total == 632)
        #expect(timing.unknownCount == 0)
        #expect(!timing.isApproximate)
        #expect(timing.totalText == "10:32")
        #expect(timing.target == 2700)
        #expect(timing.progress == 632.0 / 2700)
    }

    @Test
    func `unknown lengths are never made up`() {
        let lengths = [songs[0]: SongLength(seconds: 100, source: .directive)]
        let timing = SetlistTiming(entries: entries([2, 0, 3, 0]), lengths: lengths, target: nil)
        #expect(timing.items.map(\.start) == [0, 0, 100, 100])
        #expect(timing.items.map(\.startIsApproximate) == [false, true, true, true])
        #expect(timing.items[0].length == nil)
        #expect(SetlistTiming.format(timing.items[0].length) == "--:--")
        #expect(SetlistTiming.format(timing.items[1].length) == "1:40")
        #expect(timing.total == 200)
        #expect(timing.unknownCount == 2)
        #expect(timing.totalText == "≥3:20 + 2 unknown")
        #expect(timing.progress == nil)
        // A lower bound of zero says nothing: the second row reads --:--, not "≥0:00".
        #expect(timing.items.map(\.startText) == ["0:00", "--:--", "≥1:40", "≥1:40"])
    }

    @Test
    func `starts after an unknown length are lower bounds`() {
        let lengths = [
            songs[0]: SongLength(seconds: 830, source: .directive),
            songs[2]: SongLength(seconds: 200, source: .directive),
        ]
        let timing = SetlistTiming(entries: entries([0, 1, 2, 3]), lengths: lengths, target: nil)
        #expect(timing.items.map(\.startText) == ["0:00", "13:50", "≥13:50", "≥17:10"])
        #expect(timing.totalText == "≥17:10 + 2 unknown")
    }

    @Test
    func `a set of unknown lengths says so instead of a zero total`() {
        let timing = SetlistTiming(entries: entries([1, 3]), lengths: [:], target: 2700)
        #expect(timing.items.map(\.startText) == ["0:00", "--:--"])
        #expect(timing.totalText == "2 unknown")
        #expect(timing.progress == 0)
    }

    @Test
    func `zero or negative lengths count as unknown`() {
        let lengths = [songs[0]: SongLength(seconds: 0, source: .directive)]
        let timing = SetlistTiming(entries: entries([0]), lengths: lengths, target: 0)
        #expect(timing.total == 0)
        #expect(timing.unknownCount == 1)
        #expect(timing.progress == nil)
    }

    @Test
    func `changeover is added between songs, never after the last`() {
        let lengths = Dictionary(uniqueKeysWithValues: songs.map {
            ($0, SongLength(seconds: 100, source: .directive))
        })
        let timing = SetlistTiming(
            entries: entries([0, 1, 2]),
            lengths: lengths,
            target: 600,
            changeover: 10,
        )
        #expect(timing.items.map(\.start) == [0, 110, 220])
        #expect(timing.total == 320)
        #expect(timing.progress == 320.0 / 600)
    }

    @Test
    func `an empty setlist is zero long`() {
        let timing = SetlistTiming(entries: [], lengths: [:], target: 2700)
        #expect(timing.items.isEmpty)
        #expect(timing.total == 0)
        #expect(timing.progress == 0)
        #expect(timing.totalText == "0:00")
    }

    @Test(arguments: [
        (0.0, "0:00"), (59.4, "0:59"), (59.6, "1:00"), (220, "3:40"), (3725, "1:02:05"),
    ])
    func `format shows hours only when needed`(seconds: TimeInterval, text: String) {
        #expect(SetlistTiming.format(seconds) == text)
    }
}
