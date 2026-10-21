import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Support
import Testing

/// Section note placement (P3-17, R144, R145): stable stage note IDs (sidecar schema 4 with a
/// deterministic migration), derived chart note IDs, per-instance placement including
/// `{chorus}` repeats, every-time chart notes as linked copies, notes appended after a
/// section's existing notes, and placed cues re-anchored by section fingerprint.
struct SectionNotePlacementTests {
    // MARK: Model

    @Test
    func `instances number written-out sections and repeats in one sequence`() throws {
        let chorus = try NoteFix.chorus(NoteFix.song)
        #expect(chorus.occurrences == 3)
        #expect(chorus.instances.map(\.occurrence) == [1, 2, 3])
        #expect(chorus.instances.map(\.isRepeat) == [false, false, true])
        #expect(chorus.instances[2].repeatOf == 2)
        #expect(chorus.writtenOut.map(\.occurrence) == [1, 2])
        #expect(chorus.defaultPlacement == .everyTime)
        // The band of the second chorus defaults to #2; a label that occurs once has none.
        let notes = NoteFix.notes(NoteFix.song)
        #expect(notes.placement(forSectionAt: chorus.headers[1]) == .instance(2))
        let verse = try #require(notes.groups.first { $0.title == "Verse" })
        #expect(notes.placement(forSectionAt: verse.headers[0]) == nil)
    }

    // MARK: Placement

    @Test
    func `a chart note added to one instance lands inside that section`() throws {
        let chorus = try NoteFix.chorus(NoteFix.song)
        let added = try NoteFix.apply(
            .add(
                group: chorus.id,
                text: "Second time softer",
                stageOnly: false,
                placement: .instance(2),
            ),
            to: NoteFix.song,
        )
        #expect(NoteFix.chorusBlock(2, in: added.text)
            == "{comment: Second time softer}\n[C]Hold it now\n")
        #expect(NoteFix.lyrics(added.text) == NoteFix.lyrics(NoteFix.song))
        let note = try NoteFix.result(added)
        #expect(note.placement == .instance(2) && note.text == "Second time softer")
        #expect(added.change.outcome
            == SectionNoteOutcome(action: .add, kind: .chart, placement: .instance))
    }

    @Test
    func `stage notes pin to an instance, a repeat or every time`() throws {
        let chorus = try NoteFix.chorus(NoteFix.song)
        var ids = [
            CueID(ULID(milliseconds: 1, randomness: Array(repeating: 1, count: 10))),
            CueID(ULID(milliseconds: 2, randomness: Array(repeating: 2, count: 10))),
        ]
        let repeatCue = try SectionNotes.change(
            .add(group: chorus.id, text: "Last time", stageOnly: true, placement: .instance(3)),
            in: SourceSnapshot(text: NoteFix.song),
            cues: [],
            newID: { ids.removeFirst() },
        )
        #expect(repeatCue.cues.contents == ["Chorus|3|Last time"])
        #expect(repeatCue.cues[0].fingerprint == "repeat")
        #expect(repeatCue.resultID == .stage(repeatCue.cues[0].id))
        #expect(repeatCue.outcome?.placement == .repeat)
        let every = try SectionNotes.change(
            .add(group: chorus.id, text: "Lights", stageOnly: true, placement: nil),
            in: SourceSnapshot(text: NoteFix.song),
            cues: repeatCue.cues,
            newID: { ids.removeFirst() },
        )
        #expect(every.cues.contents == ["Chorus|3|Last time", "Chorus|*|Lights"])
        #expect(every.cues[1].fingerprint == nil)
        // The sheet lists every time first, then by instance.
        let listed = try NoteFix.chorus(NoteFix.song, every.cues).notes
        #expect(listed.map(\.text) == ["Lights", "Last time"])
        #expect(listed.map(\.placement) == [.everyTime, .instance(3)])
    }

    @Test
    func `a chart note cannot be added to a repeat`() throws {
        let chorus = try NoteFix.chorus(NoteFix.song)
        #expect(throws: SectionNoteError.noAnchor) {
            try SectionNotes.change(
                .add(group: chorus.id, text: "Nope", stageOnly: false, placement: .instance(3)),
                in: SourceSnapshot(text: NoteFix.song),
                cues: [],
            )
        }
    }

    @Test
    func `moving a chart note between instances moves its line and keeps the lyrics`() throws {
        let chorus = try NoteFix.chorus(NoteFix.song)
        let added = try NoteFix.apply(
            .add(group: chorus.id, text: "Push", stageOnly: false, placement: .instance(1)),
            to: NoteFix.song,
        )
        let id = try #require(added.change.resultID)
        let moved = try NoteFix.apply(.place(id, .instance(2)), to: added.text)
        #expect(moved.change.actionName == "Move Note")
        #expect(!NoteFix.chorusBlock(1, in: moved.text).contains("Push"))
        #expect(NoteFix.chorusBlock(2, in: moved.text) == "{comment: Push}\n[C]Hold it now\n")
        #expect(NoteFix.lyrics(moved.text) == NoteFix.lyrics(NoteFix.song))
        let note = try NoteFix.result(moved)
        #expect(note.placement == .instance(2))

        // Onto the repeat: it becomes a stage note on #3 in the same step.
        let movedID = try #require(moved.change.resultID)
        let staged = try NoteFix.apply(.place(movedID, .instance(3)), to: moved.text)
        #expect(staged.text == NoteFix.song)
        #expect(staged.cues.contents == ["Chorus|3|Push"])
        #expect(staged.change.resultID == .stage(staged.cues[0].id))
        #expect(staged.change.outcome
            == SectionNoteOutcome(action: .move, kind: .stage, placement: .repeat))
    }

    @Test
    func `an every-time chart note is one copy per written-out instance read as one note`(
    ) throws {
        let chorus = try NoteFix.chorus(NoteFix.song)
        let added = try NoteFix.apply(
            .add(group: chorus.id, text: "Everyone sings", stageOnly: false, placement: nil),
            to: NoteFix.song,
        )
        #expect(NoteFix.chorusBlock(1, in: added.text)
            == "{comment: Everyone sings}\n[C]Hold the line\n")
        #expect(NoteFix.chorusBlock(2, in: added.text)
            == "{comment: Everyone sings}\n[C]Hold it now\n")
        let notes = try NoteFix.chorus(added.text).notes
        #expect(notes.count == 1)
        let linked = try #require(notes.first)
        #expect(linked.placement == .everyTime && linked.isLinked && linked.instances == [1, 2])
        #expect(added.change.resultID == linked.id)

        // Editing the row edits every copy and keeps it linked.
        let edited = try NoteFix.apply(.setText(linked.id, "All sing"), to: added.text)
        #expect(edited.text
            == added.text.replacingOccurrences(of: "Everyone sings", with: "All sing"))
        let relinked = try NoteFix.result(edited)
        #expect(relinked.isLinked && relinked.text == "All sing")

        // A copy edited elsewhere just becomes its own note.
        let diverged = edited.text.replacingOccurrences(
            of: "{comment: All sing}\n[C]Hold it now",
            with: "{comment: Only here}\n[C]Hold it now",
        )
        #expect(try NoteFix.chorus(diverged).notes.map(\.placement) == [.instance(1), .instance(2)])

        // Placing it on #2 keeps the #2 copy where it is and removes the others.
        let placed = try NoteFix.apply(.place(relinked.id, .instance(2)), to: edited.text)
        #expect(!NoteFix.chorusBlock(1, in: placed.text).contains("All sing"))
        #expect(NoteFix.chorusBlock(2, in: placed.text) == "{comment: All sing}\n[C]Hold it now\n")
        #expect(try NoteFix.result(placed).placement == .instance(2))

        // Deleting it removes every copy; stage only turns the copies into one every-time cue.
        #expect(try NoteFix.apply(.delete(relinked.id), to: edited.text).text == NoteFix.song)
        let staged = try NoteFix.apply(.setStageOnly(relinked.id, true), to: edited.text)
        #expect(staged.text == NoteFix.song)
        #expect(staged.cues.contents == ["Chorus|*|All sing"])
        // And back: a copy in each written-out chorus again.
        let back = try NoteFix.apply(
            .setStageOnly(.stage(staged.cues[0].id), false),
            to: staged.text,
            cues: staged.cues,
        )
        #expect(back.text == edited.text)
        #expect(back.cues.isEmpty)
    }

    @Test
    func `a stage note on a repeat becomes a chart note in the chorus it repeats`() throws {
        let cue = SongCue(section: "Chorus", occurrence: 3, text: "Big ending")
        let back = try NoteFix.apply(
            .setStageOnly(.stage(cue.id), false),
            to: NoteFix.song,
            cues: [cue],
        )
        #expect(NoteFix.chorusBlock(2, in: back.text) == "{comment: Big ending}\n[C]Hold it now\n")
        #expect(!NoteFix.chorusBlock(1, in: back.text).contains("Big ending"))
    }

    // MARK: Append order (R144)

    @Test
    func `a second note appends after the first and after a leading run only`() throws {
        let text = """
        {start_of_verse}
        {comment: First}

        {c: Second}
        [G]Line one
        {comment: Mid-section cue}
        [C]Line two
        {end_of_verse}

        """
        let verse = try #require(NoteFix.notes(text).groups.first)
        let added = try NoteFix.apply(
            .add(group: verse.id, text: "Third", stageOnly: false, placement: nil),
            to: text,
        )
        #expect(added.text == text.replacingOccurrences(
            of: "{c: Second}\n",
            with: "{c: Second}\n{comment: Third}\n",
        ))
        #expect(NoteFix.notes(added.text).all.map(\.text)
            == ["First", "Second", "Third", "Mid-section cue"])
        // A stage note turned into a chart note appends too.
        let cue = SongCue(section: "Verse", text: "Fourth")
        let charted = try NoteFix.apply(
            .setStageOnly(.stage(cue.id), false),
            to: added.text,
            cues: [cue],
        )
        #expect(charted.text.contains("{comment: Third}\n{comment: Fourth}\n[G]Line one"))
    }

    // MARK: Arrangements (R146)

    @Test
    func `note edits never change a fingerprint and older arrangements stay applied`() throws {
        func units(_ text: String) -> [SongSectionUnit] {
            SongSections.units(of: SourceSnapshot(text: text).document)
        }
        let chorus = try NoteFix.chorus(NoteFix.song)
        let noted = try NoteFix.apply(
            .add(group: chorus.id, text: "Lift", stageOnly: false, placement: nil),
            to: NoteFix.song,
        )
        #expect(units(noted.text).map(\.fingerprint) == units(NoteFix.song).map(\.fingerprint))
        // A placed cue stays put when a note lands at the top of its chorus.
        let cue = SongCue(
            section: "Chorus",
            occurrence: 2,
            text: "Watch Ravi",
            fingerprint: units(NoteFix.song)[2].fingerprint,
        )
        let note = try #require(NoteFix.notes(noted.text, [cue]).note(.stage(cue.id)))
        #expect(note.placement == .instance(2) && !note.needsPlacementCheck)

        // An arrangement saved before R146 carries comment-including fingerprints.
        let old = units(noted.text)
        #expect(old[0].legacyFingerprint != old[0].fingerprint)
        let saved = SlotArrangement(steps: old.map {
            ArrangementStep(anchor: $0.anchor, fingerprint: $0.legacyFingerprint)
        })
        guard case .applied = ArrangementResolver.resolve(saved, units: old) else {
            Issue.record("an older arrangement reads out of date")
            return
        }
    }

    // MARK: Interop

    @Test
    func `notes added by Segue are plain comment lines`() throws {
        let chorus = try NoteFix.chorus(NoteFix.song)
        var text = NoteFix.song
        let adds: [(String, NotePlacement)] = [
            ("A", .everyTime), ("B", .instance(2)), ("C", .instance(1)),
        ]
        for (words, placement) in adds {
            text = try NoteFix.apply(
                .add(group: chorus.id, text: words, stageOnly: false, placement: placement),
                to: text,
            ).text
        }
        let added = text.components(separatedBy: "\n")
            .filter { !$0.isEmpty && !NoteFix.song.contains($0) }
        #expect(added.count == 4)
        #expect(added.allSatisfy { $0.hasPrefix("{comment: ") && $0.hasSuffix("}") })
        #expect(!text.contains("#") && !text.contains("x_segue") && !text.contains("id="))
        #expect(NoteFix.lyrics(text) == NoteFix.lyrics(NoteFix.song))
    }
}
