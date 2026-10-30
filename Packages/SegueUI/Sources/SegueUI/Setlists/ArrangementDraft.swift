import Foundation
import Library

/// The Arrange Sections sheet's lane (P8-3, R149): a slot's passes as chips, the song's parts
/// as palette groups, and every edit. Pure: `apply` never mutates the receiver; it returns
/// the arrangement to save, the new selection and the undo name, or why it was refused. The
/// views only map gestures and keys to edits.
struct ArrangementDraft: Equatable {
    /// One pass in the lane.
    struct Chip: Equatable, Identifiable {
        /// Position in the lane.
        var id: Int
        var unit: SongSectionUnit
        var mode: PassMode
        /// The pass's name and number among the shown passes ("2 of 3"), the same numbering
        /// as the stage map and the gutter badges (`PassNaming`).
        var name: PassName?
        /// The part's occurrences differ in content, so the chip shows its ordinal.
        var showsOrdinal: Bool

        /// "Chorus", or "Chorus 3rd" when the ordinal shows.
        var title: String {
            showsOrdinal ? unit.name : unit.title
        }

        /// "2 of 3", or nil when the label plays once or the pass is skipped.
        var number: String? {
            name?.badgeText
        }
    }

    /// One palette button: the parts sharing a label (and roadmap token).
    struct Group: Equatable, Identifiable {
        /// Position in the palette.
        var id: Int
        var token: RoadmapToken
        /// The group's occurrences, in song order.
        var units: [SongSectionUnit]
        /// A part of the group was added to the song after the arrangement was saved.
        var isNew: Bool

        var title: String {
            token.title
        }
    }

    enum Edit: Equatable {
        /// Inserts part `unit` (index into the song's parts) at lane position `at`.
        case insert(unit: Int, at: Int)
        /// Inserts palette group `group` after lane position `after`, the occurrence by the
        /// counting rule (decision 10).
        case insertGroup(Int, after: Int)
        case duplicate(Int)
        /// ⌥-drag: a copy of pass `from` at drop index `to` (0 ... count).
        case copy(Int, to: Int)
        case playAgainAtEnd(Int)
        case remove(Int)
        /// Moves pass `from` to drop index `to` (0 ... count, before the pass there).
        case move(from: Int, to: Int)
        case setMode(Int, PassMode)
        case toggleSkip(Int)
        /// A roadmap commit.
        case replace([ArrangementPass])
        /// The out-of-date banner's Update: the lane as shown.
        case update
        case setLength(TimeInterval?)
    }

    enum Refusal: Equatable, Error {
        case lastPlayingPass
        case tooManyPasses
        case nothingChanged

        /// The help text for a refused control.
        var message: String? {
            switch self {
            case .lastPlayingPass: "At least one pass plays"
            case .tooManyPasses: "A slot can have up to \(SlotArrangement.maxPasses) passes"
            case .nothingChanged: nil
            }
        }
    }

    struct Result: Equatable {
        var arrangement: SlotArrangement
        var selection: Int
        var actionName: String
    }

    /// The passes that resolve against the song, in played order.
    private(set) var chips: [Chip]
    /// Saved passes that no longer name a part of the song (out of date).
    private(set) var missing: [ArrangementPass]
    /// Parts added to the song after the arrangement was saved ("New" in the palette).
    private(set) var newParts: [SongSectionUnit]
    /// The palette, in order of first appearance in the song.
    let groups: [Group]
    var length: TimeInterval?
    /// Whether the slot has a saved arrangement (else the lane is the full song).
    let isCustom: Bool
    /// The saved arrangement cannot be played as saved (missing parts or a broken
    /// invariant): the stage shows the full song.
    let isOutOfDate: Bool
    private let units: [SongSectionUnit]

    init(arrangement: SlotArrangement?, units: [SongSectionUnit]) {
        self.units = units
        isCustom = arrangement != nil
        length = arrangement?.length
        let saved = arrangement ?? .fullSong(units)
        isOutOfDate = arrangement.map {
            ArrangementResolver.resolve($0, units: units).isOutOfDate
        } ?? false
        var lane: [(pass: ArrangementPass, unit: SongSectionUnit)] = []
        var missing: [ArrangementPass] = []
        for pass in saved.passes {
            if let unit = ArrangementResolver.unit(for: pass, in: units) {
                lane.append((pass, unit))
            } else {
                missing.append(pass)
            }
        }
        self.missing = missing
        let known = saved.effectiveKnownParts
        newParts = arrangement == nil ? [] : units.filter { unit in
            !lane.contains { $0.unit.index == unit.index }
                && !known.contains { $0.anchor.matches(unit.anchor) }
        }
        let tokens = ArrangementRoadmap.tokens(units)
        let newIndices = Set(newParts.map(\.index))
        groups = tokens.enumerated().map { offset, token in
            let members = token.units.map { units[$0] }
            return Group(
                id: offset,
                token: token,
                units: members,
                isNew: members.contains { newIndices.contains($0.index) },
            )
        }
        chips = Self.chips(lane.map(\.pass), units: units, tokens: tokens)
    }

    /// The lane as passes, each with the song's current fingerprint.
    var passes: [ArrangementPass] {
        chips.map(Self.pass)
    }

    /// The lane as it would be saved: every part of the song known (R123).
    var arrangement: SlotArrangement {
        SlotArrangement(passes: passes, knownParts: KnownPart.all(units), length: length)
    }

    var playingCount: Int {
        chips.count { $0.mode != .skip }
    }

    var skippedCount: Int {
        chips.count { $0.mode == .skip }
    }

    /// The lane as a roadmap ("I:CH V1 C V2 C -B C O:1").
    var roadmap: String {
        ArrangementRoadmap.format(passes, units: units)
    }

    /// This song's tokens, for the roadmap's help line.
    var partList: String {
        groups.map(\.token.text).joined(separator: " ")
    }

    func parseRoadmap(_ text: String) -> Swift.Result<[ArrangementPass], RoadmapError> {
        ArrangementRoadmap.parse(text, units: units)
    }

    /// The draft with `passes` in the lane (a roadmap being typed, before it is saved).
    func with(passes: [ArrangementPass]) -> Self {
        var copy = self
        copy.chips = Self.chips(
            passes.filter { ArrangementResolver.unit(for: $0, in: units) != nil },
            units: units,
            tokens: groups.map(\.token),
        )
        return copy
    }

    /// The part a palette group adds after lane position `after` (decision 10): the
    /// occurrence after the nearest earlier chip of the group, capped at the last; the first
    /// when there is none.
    func occurrence(of group: Int, after: Int) -> SongSectionUnit? {
        guard groups.indices.contains(group) else { return nil }
        let members = groups[group].units
        let end = min(max(after + 1, 0), chips.count)
        let previous = chips[..<end].last { chip in
            members.contains { $0.index == chip.unit.index }
        }
        let occurrence = ArrangementRoadmap.occurrence(
            after: previous.flatMap { chip in
                members.firstIndex { $0.index == chip.unit.index }.map { $0 + 1 }
            },
            count: members.count,
        )
        return members[occurrence - 1]
    }

    // MARK: Edits

    /// Applies `edit` with the chip at `selection` selected. Refuses an edit that would leave
    /// nothing to play, exceed `SlotArrangement.maxPasses`, or change nothing.
    func apply(_ edit: Edit, selection: Int) -> Swift.Result<Result, Refusal> {
        let start = Change(passes: passes, length: length, selection: selection, name: "")
        guard let change = added(edit, start) ?? rearranged(edit, start) ?? restyled(edit, start)
        else { return .failure(.nothingChanged) }
        if change.passes.count > SlotArrangement.maxPasses, change.passes.count > chips.count {
            return .failure(.tooManyPasses)
        }
        guard change.passes.contains(where: \.isShown) else { return .failure(.lastPlayingPass) }
        return .success(Result(
            arrangement: SlotArrangement(
                passes: change.passes,
                knownParts: KnownPart.all(units),
                length: change.length,
            ),
            selection: max(change.selection, 0),
            actionName: change.name,
        ))
    }

    /// An edit's outcome before the invariants are checked.
    private struct Change {
        var passes: [ArrangementPass]
        var length: TimeInterval?
        var selection: Int
        var name: String

        /// `pass` inserted at `index` (clamped), selected.
        func inserting(_ pass: ArrangementPass, at index: Int, name: String) -> Self {
            var change = self
            change.selection = min(max(index, 0), passes.count)
            change.passes.insert(pass, at: change.selection)
            change.name = name
            return change
        }
    }

    /// Insert, duplicate, copy and play again at end; nil for other edits or a bad index.
    private func added(_ edit: Edit, _ start: Change) -> Change? {
        let passes = start.passes
        switch edit {
        case let .insert(unit, at):
            return units.first { $0.index == unit }
                .map { start.inserting(Self.pass($0), at: at, name: "Add Pass") }
        case let .insertGroup(group, after):
            return occurrence(of: group, after: after)
                .map { start.inserting(Self.pass($0), at: after + 1, name: "Add Pass") }
        case let .duplicate(index):
            guard passes.indices.contains(index) else { return nil }
            return start.inserting(passes[index], at: index + 1, name: "Duplicate Pass")
        case let .copy(index, to):
            guard passes.indices.contains(index) else { return nil }
            return start.inserting(passes[index], at: to, name: "Duplicate Pass")
        case let .playAgainAtEnd(index):
            guard passes.indices.contains(index) else { return nil }
            var copy = passes[index]
            copy.mode = copy.mode == .skip ? .full : copy.mode
            return start.inserting(copy, at: passes.count, name: "Play Again at End")
        default:
            return nil
        }
    }

    /// Remove and move; nil for other edits, a bad index or a move to the same place.
    private func rearranged(_ edit: Edit, _ start: Change) -> Change? {
        var change = start
        switch edit {
        case let .remove(index):
            guard change.passes.indices.contains(index) else { return nil }
            change.passes.remove(at: index)
            change.selection = min(index, change.passes.count - 1)
            change.name = "Remove Pass"
        case let .move(from, to):
            guard change.passes.indices.contains(from), (0 ... change.passes.count).contains(to)
            else { return nil }
            let destination = to > from ? to - 1 : to
            guard destination != from else { return nil }
            change.passes.insert(change.passes.remove(at: from), at: destination)
            change.selection = destination
            change.name = "Move Pass"
        default:
            return nil
        }
        return change
    }

    /// Modes, the roadmap, Update and the length; nil for other edits or no change.
    private func restyled(_ edit: Edit, _ start: Change) -> Change? {
        var change = start
        switch edit {
        case let .setMode(index, mode):
            guard change.passes.indices.contains(index), change.passes[index].mode != mode
            else { return nil }
            change.passes[index].mode = mode
            change.selection = index
            change.name = Self.modeActionName(mode)
        case let .toggleSkip(index):
            guard change.passes.indices.contains(index) else { return nil }
            let skipping = change.passes[index].mode != .skip
            change.passes[index].mode = skipping ? .skip : .full
            change.selection = index
            change.name = skipping ? "Skip Pass" : "Play Pass"
        case let .replace(replacement):
            guard replacement != change.passes else { return nil }
            change.passes = replacement
            change.selection = min(max(start.selection, 0), max(replacement.count - 1, 0))
            change.name = "Edit Roadmap"
        case .update:
            change.name = "Update Arrangement"
        case let .setLength(seconds):
            guard seconds != change.length else { return nil }
            change.length = seconds
            change.name = "Set Slot Length"
        default:
            return nil
        }
        return change
    }

    /// "Show Full", "Show Chords Only", "Show First Line", "Skip Pass".
    static func modeActionName(_ mode: PassMode) -> String {
        switch mode {
        case .full: "Show Full"
        case .chordsOnly: "Show Chords Only"
        case .firstLine: "Show First Line"
        case .skip: "Skip Pass"
        }
    }
}

// MARK: - Building chips

private extension ArrangementDraft {
    static func pass(_ unit: SongSectionUnit) -> ArrangementPass {
        ArrangementPass(anchor: unit.anchor, fingerprint: unit.fingerprint)
    }

    static func pass(_ chip: Chip) -> ArrangementPass {
        ArrangementPass(
            anchor: chip.unit.anchor,
            fingerprint: chip.unit.fingerprint,
            mode: chip.mode,
        )
    }

    static func chips(
        _ passes: [ArrangementPass],
        units: [SongSectionUnit],
        tokens: [RoadmapToken],
    ) -> [Chip] {
        let names = PassNaming.names(passes, units: units)
        let differing = differingGroups(units, tokens: tokens)
        return passes.enumerated().compactMap { position, pass in
            guard let unit = ArrangementResolver.unit(for: pass, in: units) else { return nil }
            return Chip(
                id: position,
                unit: unit,
                mode: pass.mode,
                name: names[position],
                showsOrdinal: differing.contains(unit.index),
            )
        }
    }

    /// The parts whose label group's occurrences differ in content (a `{chorus}` repeat
    /// counts as the chorus it writes out, R158 P8-3 Q4).
    static func differingGroups(
        _ units: [SongSectionUnit],
        tokens: [RoadmapToken],
    ) -> Set<Int> {
        var result = Set<Int>()
        for token in tokens where token.units.count > 1 {
            let contents = Set(token.units.map { content(of: $0, in: units) })
            if contents.count > 1 {
                result.formUnion(token.units.map { units[$0].index })
            }
        }
        return result
    }

    /// A part's fingerprint, a `{chorus}` repeat mapped to the chorus it repeats (the
    /// `SongSections.repeatTarget` rule, on parts).
    static func content(of offset: Int, in units: [SongSectionUnit]) -> String {
        let unit = units[offset]
        guard unit.isRepeat else { return unit.fingerprint }
        let key = unit.title.lowercased()
        let choruses = units[..<offset].reversed().filter { $0.kind == .chorus && !$0.isRepeat }
        let target = choruses.first { $0.title.lowercased() == key } ?? choruses.first
        return target?.fingerprint ?? unit.fingerprint
    }
}

// MARK: - Texts

extension ArrangementDraft {
    /// The slot row's mark: "Custom · I:CH V1 C V2 C B C O:1".
    static func markText(_ arrangement: SlotArrangement, units: [SongSectionUnit]) -> String {
        "Custom · " + Self(arrangement: arrangement, units: units).roadmap
    }

    /// "9 passes, 1 skipped" / "1 pass" (the popover row and VoiceOver).
    static func countsText(_ arrangement: SlotArrangement) -> String {
        let total = arrangement.passes.count
        let skipped = arrangement.passes.count { $0.mode == .skip }
        var text = total == 1 ? "1 pass" : "\(total) passes"
        if skipped > 0 {
            text += ", \(skipped) skipped"
        }
        return text
    }

    /// The slot popover's Sections row: "Full song…", "Custom: 9 passes, 1 skipped…" or
    /// "Out of date: full song…".
    static func popoverText(_ arrangement: SlotArrangement?, units: [SongSectionUnit]?) -> String {
        guard let arrangement else { return "Full song…" }
        guard let units else { return "Custom…" }
        if ArrangementResolver.resolve(arrangement, units: units).isOutOfDate {
            return "Out of date: full song…"
        }
        return "Custom: \(countsText(arrangement))…"
    }

    /// The footer: "8 passes play · 1 skipped".
    var footerCounts: String {
        var text = playingCount == 1 ? "1 pass plays" : "\(playingCount) passes play"
        if skippedCount > 0 {
            text += " · \(skippedCount) skipped"
        }
        return text
    }

    /// The missing passes by name: "Verse 3, After Bridge".
    var missingNames: String {
        missing.map(\.anchor.summaryName).joined(separator: ", ")
    }
}
