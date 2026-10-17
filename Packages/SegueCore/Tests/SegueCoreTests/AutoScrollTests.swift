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
            overflow: 850, duration: 180, tempo: 92, time: "4/4", lineCount: 30,
        ))
        #expect(speed.source == .duration)
        #expect(speed.leadIn == ScrollSpeedModel.leadIn)
        #expect(abs(speed.pointsPerSecond - 850 / 170) < 1e-9)
    }

    @Test
    func `a short duration scrolls from the start`() {
        let speed = ScrollSpeedModel.speed(ScrollSpeedInput(
            overflow: 100, duration: 25, tempo: nil, time: nil, lineCount: 10,
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
            overflow: 600, duration: nil, tempo: tempo, time: time, lineCount: 40,
        )
        #expect(ScrollSpeedModel.estimatedDuration(input) == seconds)
        let speed = ScrollSpeedModel.speed(input)
        #expect(speed.source == .tempo)
        #expect(abs(speed.pointsPerSecond - 600 / (seconds - ScrollSpeedModel.leadIn)) < 1e-9)
    }

    @Test
    func `neither duration nor tempo uses the default speed`() {
        let speed = ScrollSpeedModel.speed(ScrollSpeedInput(
            overflow: 600, duration: nil, tempo: nil, time: "4/4", lineCount: 40,
        ))
        #expect(speed.source == .fallback)
        #expect(speed.pointsPerSecond == ScrollSpeedModel.defaultSpeed)
    }

    @Test
    func `the nudge factor multiplies every source`() {
        let inputs = [
            ScrollSpeedInput(overflow: 500, duration: 200, tempo: nil, time: nil, lineCount: 0),
            ScrollSpeedInput(overflow: 500, duration: nil, tempo: 100, time: nil, lineCount: 30),
            ScrollSpeedInput(overflow: 500, duration: nil, tempo: nil, time: nil, lineCount: 30),
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
            overflow: overflow, duration: 180, tempo: nil, time: nil, lineCount: 40,
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
}
