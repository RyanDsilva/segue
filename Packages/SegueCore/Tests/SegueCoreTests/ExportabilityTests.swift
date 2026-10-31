import Diagrams
import Editing
import Library
import MusicTheory
import Testing

/// MIDI export later needs nothing new (P8-7 section 9.7): the timeline and the resolved
/// notes already carry every fact a type-1 file writes.
struct ExportabilityTests {
    @Test
    func `the timeline and resolved notes give every note and pass what MIDI needs`() throws {
        let fixture = PartFixture("{tempo: 96}\n{time: 4/4}\n" + PartFixture.song)
        let part = try fixture.part(from: (0, 2), to: (1, 0), bass: ["D", "G"], events: [
            PartEvent(chord: 0, at: 1440, len: 240, deg: 2),
            PartEvent(chord: 0, at: 1680, len: 240, deg: 4, velocity: 110, articulations: [.slide]),
            PartEvent(chord: 1, at: 0, len: 480, deg: 0),
        ])
        let notes = try fixture.notes(part)
        #expect(notes.count == 3)
        for note in notes {
            #expect(note.tick >= 0 && note.tick < fixture.timeline.totalTicks)
            #expect(note.playedLength > 0)
            #expect((0 ... 127).contains(note.midi))
            #expect(note.playedVelocity > 0)
        }
        // Tempo (FF 51) and meter (FF 58) maps, 480 PPQ.
        #expect(fixture.timeline.tempos.initial == 96)
        #expect(fixture.timeline.meters.initial == .common)
        #expect(Ticks.perQuarter == 480)
        // Section markers (FF 06): every pass has a start tick and a name.
        for pass in fixture.timeline.passes {
            #expect(pass.start <= pass.end)
            let name = SectionNotes.label(of: fixture.model.sections[pass.content])
            #expect(name?.isEmpty == false)
        }
        // A chord track: every chord has an onset, a length and a name.
        #expect(fixture.timeline.chords.allSatisfy { $0.length > 0 && !$0.token.isEmpty })
    }
}
