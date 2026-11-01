import Foundation
import LiveLayout
import Testing

/// Scroll-speed derivation and the `AutoScroller` timeline, on injected instants.
struct AutoScrollTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }

    // MARK: - Speed

    @Test
    func `a duration scrolls the overflow over the duration minus the lead-in`() {
        let speed = ScrollSpeedModel.speed(ScrollSpeedInput(
            overflow: 850, playedTime: 180, tempo: 92, time: "4/4", lineCount: 30,
        ))
        #expect(speed.source == .timeline)
        #expect(speed.leadIn == ScrollSpeedModel.leadIn)
        #expect(abs(speed.pointsPerSecond - 850 / 170) < 1e-9)
    }

    @Test
    func `a short duration scrolls from the start`() {
        let speed = ScrollSpeedModel.speed(ScrollSpeedInput(
            overflow: 100, playedTime: 25, tempo: nil, time: nil, lineCount: 10,
        ))
        #expect(speed.leadIn == 0)
        #expect(abs(speed.pointsPerSecond - 4) < 1e-9)
    }

    @Test(arguments: [
        // 40 lines x 2 bars x 4 beats at 120 BPM = 160 s.
        ("4/4", 120.0, 160.0),
        // 3/4: 40 x 2 x 3 at 90 = 160 s.
        ("3/4", 90.0, 160.0),
        // 6/8 counts two dotted beats: 40 x 2 x 2 at 60 = 160 s.
        ("6/8", 60.0, 160.0),
        // No time signature: 4/4.
        ("", 120.0, 160.0),
    ])
    func `no duration estimates one from tempo and metre`(
        time: String,
        tempo: Double,
        seconds: Double,
    ) {
        let input = ScrollSpeedInput(
            overflow: 600, playedTime: nil, tempo: tempo, time: time, lineCount: 40,
        )
        #expect(ScrollSpeedModel.estimatedTime(input) == seconds)
        let speed = ScrollSpeedModel.speed(input)
        #expect(speed.source == .tempo)
        #expect(abs(speed.pointsPerSecond - 600 / (seconds - ScrollSpeedModel.leadIn)) < 1e-9)
    }

    @Test
    func `neither duration nor tempo uses the default speed`() {
        let speed = ScrollSpeedModel.speed(ScrollSpeedInput(
            overflow: 600, playedTime: nil, tempo: nil, time: "4/4", lineCount: 40,
        ))
        #expect(speed.source == .fallback)
        #expect(speed.pointsPerSecond == ScrollSpeedModel.defaultSpeed)
    }

    @Test
    func `the nudge factor multiplies every source`() {
        let inputs = [
            ScrollSpeedInput(overflow: 500, playedTime: 200, tempo: nil, time: nil, lineCount: 0),
            ScrollSpeedInput(overflow: 500, playedTime: nil, tempo: 100, time: nil, lineCount: 30),
            ScrollSpeedInput(overflow: 500, playedTime: nil, tempo: nil, time: nil, lineCount: 30),
        ]
        for var input in inputs {
            let base = ScrollSpeedModel.speed(input).pointsPerSecond
            input.factor = ScrollSpeedModel.nudgeStep * ScrollSpeedModel.nudgeStep
            #expect(abs(ScrollSpeedModel.speed(input).pointsPerSecond - base * 1.21) < 1e-9)
        }
    }

    // MARK: - Timeline

    func threeMinuteScroller(overflow: Double = 850) -> AutoScroller {
        let speed = ScrollSpeedModel.speed(ScrollSpeedInput(
            overflow: overflow, playedTime: 180, tempo: nil, time: nil, lineCount: 40,
        ))
        return AutoScroller(speed: speed, overflow: overflow)
    }

    @Test
    func `a three minute song reaches the bottom at about 180 seconds`() {
        var scroller = threeMinuteScroller()
        #expect(scroller.offset(at: at(60)) == 0, "never moves before start")
        scroller.start(at: at(0))
        #expect(scroller.offset(at: at(9.9)) == 0, "lead-in")
        #expect(abs(scroller.offset(at: at(95)) - 425) < 1e-6)
        #expect(scroller.offset(at: at(179)) < 850)
        #expect(scroller.phase(at: at(179)) == .running)
        #expect(scroller.offset(at: at(180)) == 850)
        #expect(scroller.phase(at: at(180)) == .finished)
        #expect(scroller.offset(at: at(400)) == 850)
        scroller.settle(at: at(200))
        #expect(scroller.phase == .finished)
    }

    @Test
    func `pause holds the position and resume continues without a second lead-in`() {
        var scroller = threeMinuteScroller()
        scroller.start(at: at(0))
        scroller.pause(at: at(60))
        let held = scroller.offset(at: at(60))
        #expect(held == 250)
        #expect(scroller.phase == .paused)
        #expect(scroller.offset(at: at(300)) == held)
        scroller.start(at: at(300))
        #expect(abs(scroller.offset(at: at(301)) - (held + 5)) < 1e-9)
        #expect(scroller.offset(at: at(300 + 130)) == 850)
    }

    @Test
    func `pausing during the lead-in keeps the rest of it`() {
        var scroller = threeMinuteScroller()
        scroller.start(at: at(0))
        scroller.pause(at: at(4))
        scroller.start(at: at(100))
        #expect(scroller.offset(at: at(105.9)) == 0)
        #expect(abs(scroller.offset(at: at(107)) - 5) < 1e-9)
    }

    @Test
    func `restart returns to the top idle with the lead-in`() {
        var scroller = threeMinuteScroller()
        scroller.start(at: at(0))
        scroller.restart(at: at(50))
        #expect(scroller.phase == .idle)
        #expect(scroller.offset(at: at(80)) == 0)
        scroller.start(at: at(100))
        #expect(scroller.offset(at: at(109)) == 0)
        #expect(abs(scroller.offset(at: at(111)) - 5) < 1e-9)
    }

    @Test
    func `seeking continues from the new offset and keeps running`() {
        var scroller = threeMinuteScroller()
        scroller.start(at: at(0))
        scroller.seek(to: 600, at: at(20))
        #expect(scroller.phase == .running)
        #expect(abs(scroller.offset(at: at(30)) - 650) < 1e-9)
        // A seek while idle moves the held offset only.
        var idle = threeMinuteScroller()
        idle.seek(to: 300, at: at(5))
        #expect(idle.phase == .idle)
        #expect(idle.offset(at: at(50)) == 300)
        // Starting away from the top has no lead-in.
        idle.start(at: at(50))
        #expect(abs(idle.offset(at: at(51)) - 305) < 1e-9)
        // Seeking up from the end pauses there.
        var done = threeMinuteScroller()
        done.start(at: at(0))
        done.seek(to: 100, at: at(500))
        #expect(done.phase == .paused)
        #expect(done.offset(at: at(600)) == 100)
    }

    @Test
    func `a held seek waits before moving on and the instant of an offset is predicted`() {
        var scroller = threeMinuteScroller()
        scroller.start(at: at(0))
        // Lead-in 10 s, then 5 pt/s: 100 pt is reached at 30 s.
        #expect(scroller.instant(reaching: 100) == at(30))
        #expect(scroller.instant(reaching: 0) == nil)
        #expect(scroller.instant(reaching: scroller.overflow + 1) == nil)
        // The loop's count-in: seek back and hold 2 s, then the same speed.
        scroller.seek(to: 40, at: at(50), holding: 2)
        #expect(scroller.offset(at: at(51)) == 40)
        #expect(abs(scroller.offset(at: at(54)) - 50) < 1e-9)
        #expect(scroller.instant(reaching: 60) == at(56))
        // Not running: a plain seek, and no instant.
        scroller.pause(at: at(60))
        scroller.seek(to: 10, at: at(61), holding: 2)
        #expect(scroller.phase == .paused)
        #expect(scroller.offset(at: at(70)) == 10)
        #expect(scroller.instant(reaching: 20) == nil)
    }

    @Test
    func `a nudge changes the speed from now on`() {
        var scroller = threeMinuteScroller()
        scroller.start(at: at(0))
        var faster = scroller.speed
        faster.pointsPerSecond *= 2
        scroller.setSpeed(faster, at: at(30))
        #expect(abs(scroller.offset(at: at(30)) - 100) < 1e-9)
        #expect(abs(scroller.offset(at: at(40)) - 200) < 1e-9)
    }

    @Test
    func `a new overflow keeps the same fraction`() {
        var scroller = threeMinuteScroller()
        scroller.start(at: at(0))
        scroller.pause(at: at(95))
        #expect(scroller.offset(at: at(95)) == 425)
        scroller.setOverflow(300, at: at(100))
        #expect(scroller.offset(at: at(100)) == 150)
        scroller.setOverflow(0, at: at(100))
        #expect(scroller.offset(at: at(100)) == 0)
    }

    @Test
    func `nothing to scroll finishes at once`() {
        var scroller = AutoScroller(
            speed: ScrollSpeed(pointsPerSecond: 12, leadIn: 10, source: .fallback),
            overflow: 0,
        )
        scroller.start(at: at(0))
        #expect(scroller.phase == .finished)
        #expect(scroller.offset(at: at(100)) == 0)
    }

    // MARK: - A medley's segments (P9-3 9.7)

    @Test
    func `each member scrolls its stretch over its own time`() {
        // Member 1: 0-300 over 70 s (80 s minus the lead-in); member 2: 300-900 over 60 s.
        let speed = ScrollSpeedModel.medley([
            MedleyScrollMember(fromOffset: 0, seconds: 80),
            MedleyScrollMember(fromOffset: 300, seconds: 60),
        ], overflow: 900)
        #expect(speed.source == .timeline)
        #expect(speed.leadIn == ScrollSpeedModel.leadIn)
        #expect(speed.segments.map(\.fromOffset) == [0, 300])
        #expect(abs(speed.segments[0].speed - 300 / 70) < 1e-9)
        #expect(abs(speed.segments[1].speed - 10) < 1e-9)
        var scroller = AutoScroller(speed: speed, overflow: 900)
        scroller.start(at: at(0))
        // The lead-in, then 70 s to the boundary, then 10 pt/s.
        #expect(abs(scroller.offset(at: at(45)) - 35 * 300 / 70) < 1e-6)
        #expect(abs(scroller.offset(at: at(80)) - 300) < 1e-6)
        #expect(abs(scroller.offset(at: at(90)) - 400) < 1e-6)
        #expect(scroller.phase(at: at(140)) == .finished)
    }

    @Test
    func `a member with no time moves at the average known speed`() {
        let speed = ScrollSpeedModel.medley([
            MedleyScrollMember(fromOffset: 0, seconds: 25),
            MedleyScrollMember(fromOffset: 100, seconds: nil),
            MedleyScrollMember(fromOffset: 400, seconds: 30),
        ], overflow: 700)
        // A 25 s opener has no lead-in: 100 pt in 25 s and 300 pt in 30 s, 400 / 55 average.
        #expect(speed.leadIn == 0)
        #expect(speed.segments.map(\.speed) == [4, 400.0 / 55, 10])
    }

    @Test
    func `no member known scrolls at the default speed, and the factor scales every segment`() {
        let unknown = ScrollSpeedModel.medley(
            [
                MedleyScrollMember(fromOffset: 0, seconds: nil),
                MedleyScrollMember(fromOffset: 200, seconds: nil),
            ],
            overflow: 500,
            factor: 2,
        )
        #expect(unknown.source == .fallback)
        #expect(unknown.segments.isEmpty)
        #expect(unknown.pointsPerSecond == ScrollSpeedModel.defaultSpeed * 2)
        let members = [
            MedleyScrollMember(fromOffset: 0, seconds: 20),
            MedleyScrollMember(fromOffset: 100, seconds: 10),
        ]
        let plain = ScrollSpeedModel.medley(members, overflow: 300)
        let nudged = ScrollSpeedModel.medley(members, overflow: 300, factor: 1.1)
        #expect(zip(plain.segments, nudged.segments)
            .allSatisfy { abs($1.speed - $0.speed * 1.1) < 1e-9 })
    }

    @Test
    func `instant reaching integrates over the segments`() {
        let speed = ScrollSpeed(
            pointsPerSecond: 5,
            leadIn: 0,
            source: .timeline,
            segments: [
                ScrollSegment(fromOffset: 0, speed: 5),
                ScrollSegment(fromOffset: 100, speed: 20),
                ScrollSegment(fromOffset: 300, speed: 10),
            ],
        )
        var scroller = AutoScroller(speed: speed, overflow: 500)
        scroller.start(at: at(0))
        // 20 s to 100, 10 s more to 300, 5 s more to 350.
        #expect(scroller.instant(reaching: 350) == at(35))
        #expect(scroller.instant(reaching: 50) == at(10))
        // From a seek inside the second segment.
        scroller.seek(to: 200, at: at(1))
        #expect(scroller.instant(reaching: 400) == at(1 + 5 + 10))
        #expect(abs(scroller.offset(at: at(8)) - 320) < 1e-9)
    }
}
