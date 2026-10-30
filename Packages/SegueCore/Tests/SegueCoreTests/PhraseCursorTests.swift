import Foundation
import Playback
import Testing

/// The lookahead cursor on a scripted clock (P8-6 sections 6.4, 15.1).
struct PhraseCursorTests {
    static let start = Date(timeIntervalSince1970: 1000)

    static func phrase(_ onsets: [Double], length: Double, note: UInt8 = 60) -> Phrase {
        Phrase(
            events: onsets.map {
                NoteEvent(voice: .chord, note: note, velocity: 80, onset: $0, duration: 0.1)
            },
            length: length,
        )
    }

    /// Steps the clock by 0.1 s from the start to `until`, collecting (note, absolute time).
    static func run(
        _ cursor: inout PhraseCursor,
        until: Double,
        lookahead: Double = 0.3,
        swapAt: (Double, Phrase)? = nil,
    ) -> [(UInt8, Double)] {
        var handed: [(UInt8, Double)] = []
        var time = 0.0
        while time <= until + 1e-9 {
            if let (at, phrase) = swapAt, abs(at - time) < 1e-9 {
                cursor.swap(to: phrase)
            }
            let now = start.addingTimeInterval(time)
            for (event, delay) in cursor.due(at: now, lookahead: lookahead) {
                handed.append((event.note, ((time + delay) * 1000).rounded() / 1000))
            }
            time += 0.1
        }
        return handed
    }

    @Test
    func `each event is handed out once, in order, ahead of its time`() {
        var cursor = PhraseCursor(
            phrase: Self.phrase([0, 0.5, 1.2], length: 2),
            start: Self.start,
            loop: false,
        )
        let first = cursor.due(at: Self.start, lookahead: 0.3)
        #expect(first.map(\.delay) == [0])
        let handed = Self.run(&cursor, until: 3)
        #expect(handed.map(\.1) == [0.5, 1.2])
        #expect(cursor.isFinished(at: Self.start.addingTimeInterval(2)))
    }

    @Test
    func `a loop wraps across passes`() {
        var cursor = PhraseCursor(
            phrase: Self.phrase([0, 0.5], length: 1),
            start: Self.start,
            loop: true,
        )
        let handed = Self.run(&cursor, until: 2.2)
        #expect(handed.map(\.1) == [0, 0.5, 1, 1.5, 2, 2.5])
    }

    @Test
    func `a swap takes over exactly at the next wrap`() {
        var cursor = PhraseCursor(
            phrase: Self.phrase([0, 0.5], length: 1),
            start: Self.start,
            loop: true,
        )
        let other = Self.phrase([0, 0.25, 0.75], length: 1, note: 62)
        let handed = Self.run(&cursor, until: 2.2, swapAt: (0.4, other))
        #expect(handed.map { "\($0.0)@\($0.1)" } == [
            "60@0.0", "60@0.5", "62@1.0", "62@1.25", "62@1.75", "62@2.0", "62@2.25",
        ])
    }

    @Test
    func `nothing is due after a phrase without a loop ends`() {
        var cursor = PhraseCursor(
            phrase: Self.phrase([0], length: 0.5),
            start: Self.start,
            loop: false,
        )
        _ = cursor.due(at: Self.start, lookahead: 0.3)
        #expect(cursor.due(at: Self.start.addingTimeInterval(5), lookahead: 0.3).isEmpty)
    }

    @Test
    func `the position follows the pass sounding now`() {
        var cursor = PhraseCursor(
            phrase: Self.phrase([0], length: 1),
            start: Self.start,
            loop: true,
        )
        _ = cursor.due(at: Self.start.addingTimeInterval(0.8), lookahead: 0.3)
        // The cursor has begun pass 2 (it wraps at 1.0, inside the lookahead).
        #expect(cursor.pass == 2)
        #expect(abs(cursor.position(at: Self.start.addingTimeInterval(0.8)) - 0.8) < 1e-6)
    }
}
