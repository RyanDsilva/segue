import Diagrams
import Editing
import Foundation
import Support
import Testing

/// Bass tunings and the instrument profile's lenient decode (P8-4 section 11.1).
struct TuningBassTests {
    @Test(arguments: [
        ("EADG", [28, 33, 38, 43] as [Int]?),
        ("BEADG", [23, 28, 33, 38, 43]),
        ("DADG", [26, 33, 38, 43]),
        ("EADGC", [28, 33, 38, 43, 48]),
        ("Eb Ab Db Gb", [27, 32, 37, 42]),
        ("B0 E1 A1 D2 G2", [23, 28, 33, 38, 43]),
        (" eadg ", [28, 33, 38, 43]),
        ("C F Bb Eb", [24, 29, 34, 39]),
        ("EAD", nil),
        ("XYZ", nil),
        ("BEADGC", nil),
        ("", nil),
        ("G2 D2 A1 E1", nil),
    ])
    func `bass letters parse low to high`(text: String, strings: [Int]?) {
        #expect(Tuning(bassLetters: text)?.strings == strings)
    }

    @Test
    func `presets come back as presets and custom tunings keep their spelling`() {
        #expect(Tuning(bassLetters: "B0 E1 A1 D2 G2") == .bassStandard5)
        #expect(Tuning(bassLetters: "eb ab db gb") == .bassHalfDown4)
        #expect(Tuning(bassLetters: "C F Bb Eb")?.name == "C F Bb Eb")
        #expect(Tuning(bassLetters: "CFAD")?.name == "CFAD")
        #expect(!Tuning.presets.contains(.bassStandard4))
    }

    @Test
    func `profile decodes leniently per field`() throws {
        let decoded = try SegueJSON.decode(
            InstrumentProfile.self,
            from: Data(#"{"playsBass": true, "strings": "five", "chordBeside": 3}"#.utf8),
        )
        #expect(decoded == InstrumentProfile(playsBass: true))
        let empty = try SegueJSON.decode(InstrumentProfile.self, from: Data("{}".utf8))
        #expect(empty == InstrumentProfile())
        #expect(empty.stageNeck)
    }

    @Test
    func `a tuning that disagrees with the string count falls back to the standard`() throws {
        let five = try #require(String(
            bytes: SegueJSON.encode(Tuning.bassStandard5),
            encoding: .utf8,
        ))
        let decoded = try SegueJSON.decode(
            InstrumentProfile.self,
            from: Data(#"{"strings": 4, "tuning": \#(five)}"#.utf8),
        )
        #expect(decoded.strings == 4)
        #expect(decoded.tuning == .bassStandard4)
        var profile = InstrumentProfile(strings: 5, tuning: .bassHighC5)
        profile.setStrings(5)
        #expect(profile.tuning == .bassHighC5)
        profile.setStrings(4)
        #expect(profile.tuning == .bassStandard4)
        #expect(InstrumentProfile(strings: 7).strings == 4)
    }

    @Test
    func `turning the bass profile on turns bass notes on once`() {
        var profile = InstrumentProfile()
        #expect(profile.bassView == nil)
        profile.setPlaysBass(true)
        #expect(profile.bassNotes)
        profile.bassNotes = false
        #expect(profile.bassView == nil)
        profile.setPlaysBass(false)
        #expect(!profile.bassNotes)
        profile.setPlaysBass(true)
        profile.setPlaysBass(false)
        #expect(profile.bassNotes)
    }

    @Test
    func `the view uses the profile tuning only for a bassist`() {
        let bassist = InstrumentProfile(
            playsBass: true,
            strings: 5,
            tuning: .bassStandard5,
            bassNotes: true,
        )
        #expect(bassist.bassView?.tuning == .bassStandard5)
        #expect(bassist.bassView?.neck == true)
        let anyone = InstrumentProfile(
            strings: 5,
            tuning: .bassStandard5,
            bassNotes: true,
            stageNeck: false,
        )
        #expect(anyone.bassView?.tuning == .bassStandard4)
        #expect(anyone.bassView?.neck == false)
    }
}
