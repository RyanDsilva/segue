import Library
import Testing

/// Resolving passes against the song (P8-2 section 5.3-5.4): Skip passes resolved but not
/// shown, `position`, new parts by `knownParts`, and the validator.
struct ArrangementResolverTests {
    @Test
    func `skips, reorders, repeats and modes resolve to the song's sections`() {
        let units = SlotArrangementTests.units()
        let arrangement = SlotArrangement(passes: [
            SlotArrangementTests.pass(units, "Intro", .chordsOnly),
            SlotArrangementTests.pass(units, "Verse 2"),
            SlotArrangementTests.pass(units, "Verse 1", .skip),
            SlotArrangementTests.pass(units, "Chorus 1st", .skip),
            SlotArrangementTests.pass(units, "Chorus 3rd"),
            SlotArrangementTests.pass(units, "Chorus 3rd"),
            SlotArrangementTests.pass(units, "After Chorus", .firstLine),
        ])
        guard case let .applied(order, newSections) = ArrangementResolver.resolve(
            arrangement,
            units: units,
        ) else {
            Issue.record("expected applied")
            return
        }
        // Skip passes are resolved but not shown; `position` indexes `passes`.
        #expect(order == [
            PlayedPass(index: 0, mode: .chordsOnly, position: 0),
            PlayedPass(index: 3, mode: .full, position: 1),
            PlayedPass(index: 6, mode: .full, position: 4),
            PlayedPass(index: 6, mode: .full, position: 5),
            PlayedPass(index: 7, mode: .firstLine, position: 6),
        ])
        // No `knownParts`: the parts the passes never name are new, not played, and not
        // out of date.
        #expect(newSections.map(\.name) == ["Chorus 2nd", "Bridge"])

        // With `knownParts`, a part removed from the passes is not new; only one the
        // arrangement never knew is.
        var known = arrangement
        known.knownParts = KnownPart.all(units).filter { $0.anchor != units[5].anchor }
        guard case let .applied(_, onlyBridge) = ArrangementResolver.resolve(known, units: units)
        else {
            Issue.record("expected applied")
            return
        }
        #expect(onlyBridge.map(\.name) == ["Bridge"])
        #expect(ArrangementResolver.fullSong(units) == units.map { PlayedPass(index: $0.index) })
    }

    @Test
    func `an unresolvable skip pass or a broken invariant reads out of date`() {
        let units = SlotArrangementTests.units()
        var skipped = SlotArrangement.fullSong(units)
        skipped.passes.append(ArrangementPass(
            anchor: .section(SectionRef(label: "Coda", occurrence: 1)),
            mode: .skip,
        ))
        #expect(ArrangementResolver.resolve(skipped, units: units).isOutOfDate)

        let allSkipped = SlotArrangement(passes: units.map {
            ArrangementPass(anchor: $0.anchor, fingerprint: $0.fingerprint, mode: .skip)
        })
        #expect(allSkipped.problems == [.noShownPass])
        #expect(SlotArrangement(passes: []).problems == [.noShownPass])
        #expect(ArrangementResolver.resolve(allSkipped, units: units).isOutOfDate)

        let tooMany = SlotArrangement(passes: Array(
            repeating: SlotArrangementTests.pass(units, "Verse 1"),
            count: SlotArrangement.maxPasses + 1,
        ))
        #expect(tooMany.problems == [.tooManyPasses])
        #expect(ArrangementResolver.resolve(tooMany, units: units).isOutOfDate)
        let atLimit = SlotArrangement(passes: Array(tooMany.passes.dropLast()))
        #expect(atLimit.problems.isEmpty)
    }
}
