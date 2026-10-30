import Foundation
import Library

/// The Arrange Sections sheet's rows (P3-16, R122, R123), derived from a slot's saved
/// arrangement and the song as it is now. Pure: every edit returns the arrangement to save,
/// and the sheet re-derives its rows from the saved value (so undo shows at once).
///
/// Interim adapter (P8-2 section 5) until P8-3 rebuilds the sheet on passes: loading folds
/// consecutive Full passes of one part into a row with that play count and a Skip pass into
/// a skipped row; saving expands rows back into passes and writes `knownParts`. An
/// arrangement using any other show mode is not loaded into rows (`usesShowModes`), so the
/// old editor can never drop a mode.
struct ArrangementDraft: Equatable {
    /// The most times a row can be played in a row.
    static let maxPlays = 9

    struct Row: Equatable, Identifiable {
        /// Position in `rows`.
        var id: Int
        var unit: SongSectionUnit
        /// 0 = skipped.
        var plays: Int
        /// A part added to the song since the arrangement was saved ("New in the song").
        var isNew: Bool
        /// A "Play Again Later" copy: unticking removes it.
        var isAgain: Bool

        var isPlayed: Bool {
            plays > 0
        }
    }

    private(set) var rows: [Row]
    /// Saved rows that no longer match the song (out of date).
    private(set) var missing: [ArrangementPass]
    /// The saved arrangement uses Chords only or First line passes, which this editor cannot
    /// show: the sheet is read-only.
    let usesShowModes: Bool
    var length: TimeInterval?
    /// Whether the slot has a saved arrangement (else the rows are the full song).
    let isCustom: Bool
    /// The song's parts as they are now (every one is known on save).
    private let units: [SongSectionUnit]

    init(arrangement: SlotArrangement?, units: [SongSectionUnit]) {
        isCustom = arrangement != nil
        self.units = units
        length = arrangement?.length
        usesShowModes = arrangement.usesShowModes
        guard let arrangement else {
            rows = units.enumerated().map { offset, unit in
                Row(id: offset, unit: unit, plays: 1, isNew: false, isAgain: false)
            }
            missing = []
            return
        }
        var rows: [Row] = []
        var missing: [ArrangementPass] = []
        var listed = Set<Int>()
        var previous: ArrangementPass?
        for pass in arrangement.passes {
            defer { previous = pass }
            guard let unit = ArrangementResolver.unit(for: pass, in: units) else {
                missing.append(pass)
                continue
            }
            // A Full pass right after a Full pass of the same part is one more play.
            if pass.isShown, let last = previous, last.isShown, last.anchor == pass.anchor,
               let row = rows.last, row.unit.index == unit.index,
               row.plays < Self.maxPlays
            {
                rows[rows.count - 1].plays += 1
                continue
            }
            let isAgain = listed.contains(unit.index)
            if isAgain, !pass.isShown {
                continue
            }
            listed.insert(unit.index)
            rows.append(Row(
                id: rows.count,
                unit: unit,
                plays: pass.isShown ? 1 : 0,
                isNew: false,
                isAgain: isAgain,
            ))
        }
        // A part the arrangement knew but plays nowhere is a skipped row; only a part it
        // never knew is new.
        let known = arrangement.effectiveKnownParts
        for unit in units where !listed.contains(unit.index) {
            let isNew = !known.contains { $0.anchor.matches(unit.anchor) }
            rows.append(Row(id: rows.count, unit: unit, plays: 0, isNew: isNew, isAgain: false))
        }
        self.rows = rows
        self.missing = missing
    }

    /// The arrangement these rows describe, every pass with the song's current fingerprint:
    /// a played row is `plays` Full passes, a skipped row one Skip pass; every part of the
    /// song is known.
    var arrangement: SlotArrangement {
        SlotArrangement(
            passes: rows.flatMap { row in
                let pass = ArrangementPass(
                    anchor: row.unit.anchor,
                    fingerprint: row.unit.fingerprint,
                    mode: row.isPlayed ? .full : .skip,
                )
                return Array(repeating: pass, count: max(row.plays, 1))
            },
            knownParts: KnownPart.all(units),
            length: length,
        )
    }

    var playedCount: Int {
        rows.count { $0.isPlayed && !$0.isAgain }
    }

    /// The song's parts (a "Play Again Later" copy is not another part).
    var partCount: Int {
        rows.count { !$0.isAgain }
    }

    var hasNewRows: Bool {
        rows.contains(where: \.isNew)
    }

    /// The passes the stage shows.
    var order: [PlayedPass] {
        rows.filter(\.isPlayed).flatMap { row in
            Array(repeating: PlayedPass(index: row.unit.index), count: row.plays)
        }
    }

    /// Whether row `index` can be skipped: at least one row must play.
    func canToggleOff(_ index: Int) -> Bool {
        guard rows.indices.contains(index), rows[index].isPlayed else { return false }
        return rows[index].isAgain || rows.count(where: \.isPlayed) > 1
    }

    /// Plays or skips row `index`; unticking a "Play Again Later" copy removes it. Returns
    /// false (nothing changed) when it would leave nothing to play.
    @discardableResult
    mutating func toggle(_ index: Int) -> Bool {
        guard rows.indices.contains(index) else { return false }
        if rows[index].isPlayed {
            guard canToggleOff(index) else { return false }
            if rows[index].isAgain {
                rows.remove(at: index)
                renumber()
                return true
            }
            rows[index].plays = 0
        } else {
            rows[index].plays = 1
        }
        rows[index].isNew = false
        return true
    }

    /// Sets row `index` to play `plays` times in a row (1 ... 9); a skipped row is ticked.
    @discardableResult
    mutating func setPlays(_ index: Int, _ plays: Int) -> Bool {
        guard rows.indices.contains(index) else { return false }
        let clamped = min(max(plays, 1), Self.maxPlays)
        guard clamped != rows[index].plays else { return false }
        rows[index].plays = clamped
        rows[index].isNew = false
        return true
    }

    /// Moves rows (drag, ⌥↑ / ⌥↓).
    @discardableResult
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) -> Bool {
        let before = rows.map(\.unit.index)
        rows.move(fromOffsets: source, toOffset: destination)
        for offset in rows.indices where rows[offset].isNew {
            rows[offset].isNew = false
        }
        renumber()
        return rows.map(\.unit.index) != before
    }

    /// Moves row `index` one place up (-1) or down (+1).
    @discardableResult
    mutating func move(_ index: Int, by delta: Int) -> Bool {
        let target = index + delta
        guard rows.indices.contains(index), rows.indices.contains(target) else { return false }
        return move(
            fromOffsets: IndexSet(integer: index),
            toOffset: delta < 0 ? target : target + 1,
        )
    }

    /// "Play Again Later" (R123): a played copy of row `index` right after it, to drag
    /// anywhere.
    mutating func playAgainLater(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        var copy = rows[index]
        copy.plays = 1
        copy.isNew = false
        copy.isAgain = true
        rows.insert(copy, at: index + 1)
        rows[index].isNew = false
        renumber()
    }

    private mutating func renumber() {
        for offset in rows.indices {
            rows[offset].id = offset
        }
        // The first row of a part is never a copy (after a move a copy may come first).
        var seen = Set<Int>()
        for offset in rows.indices {
            rows[offset].isAgain = !seen.insert(rows[offset].unit.index).inserted
        }
    }
}

extension ArrangementDraft {
    /// The slot row's mark: "Custom · 8 of 10 sections · Chorus 3rd x2".
    static func markText(_ arrangement: SlotArrangement, units: [SongSectionUnit]) -> String {
        let draft = Self(arrangement: arrangement, units: units)
        var text = "Custom · \(draft.playedCount) of \(draft.partCount) sections"
        if let repeated = draft.rows.first(where: { $0.plays > 1 }) {
            text += " · \(repeated.unit.name) x\(repeated.plays)"
        }
        return text
    }

    /// The missing rows by name: "Verse 3, After Bridge".
    var missingNames: String {
        missing.map(\.anchor.summaryName).joined(separator: ", ")
    }
}

extension SlotArrangement? {
    /// Interim (P8-2): whether a saved arrangement has Chords only or First line passes,
    /// which the old editor cannot show (its sheet is then read-only).
    var usesShowModes: Bool {
        self?.passes.contains { $0.mode == .chordsOnly || $0.mode == .firstLine } ?? false
    }
}
