import ChordPro
import Foundation
import Library

/// The editor sheet's working copy of a smart filter (direction A, Ryan's pick): a name and
/// one row per condition, each row a field, an operator and a value. Converts to and from
/// `SmartFilterConditions`; a row whose value is empty (no tags picked, an open range)
/// adds no condition.
struct SmartFilterDraft: Equatable {
    /// A condition kind the sheet offers; each kind appears at most once.
    enum Kind: String, CaseIterable, Identifiable {
        case allTags
        case anyTags
        case noneTags
        case proficiency
        case keys
        case tempo
        case length
        case neverPlayed

        var id: Self {
            self
        }

        /// The field popup's title.
        var field: Field {
            switch self {
            case .allTags, .anyTags, .noneTags: .tags
            case .proficiency: .proficiency
            case .keys: .key
            case .tempo: .tempo
            case .length: .length
            case .neverPlayed: .plays
            }
        }

        /// The operator popup's title.
        var operatorTitle: String {
            switch self {
            case .allTags: "has all of"
            case .anyTags: "has any of"
            case .noneTags: "has none of"
            case .proficiency: "is"
            case .keys: "is any of"
            case .length, .tempo: "between"
            case .neverPlayed: "never played"
            }
        }
    }

    /// The field popup: what a row is about.
    enum Field: String, CaseIterable, Identifiable {
        case tags = "Tags"
        case proficiency = "Proficiency"
        case key = "Key"
        case tempo = "Tempo"
        case length = "Length"
        case plays = "Plays"

        var id: Self {
            self
        }

        /// The kinds (operators) this field offers.
        var kinds: [Kind] {
            Kind.allCases.filter { $0.field == self }
        }
    }

    /// One condition row.
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var kind: Kind
        var tags: [String] = []
        var proficiencies: Set<Proficiency> = []
        var keys: [String] = []
        /// Tempo in BPM or length as typed (`mm:ss`); blank = open.
        var lower = ""
        var upper = ""
    }

    var name: String
    var rows: [Row]

    /// A draft of `conditions` (a new filter starts with one empty Tags row).
    init(name: String, conditions: SmartFilterConditions) {
        self.name = name
        var rows: [Row] = []
        if !conditions.allTags.isEmpty {
            rows.append(Row(kind: .allTags, tags: conditions.allTags))
        }
        if !conditions.anyTags.isEmpty {
            rows.append(Row(kind: .anyTags, tags: conditions.anyTags))
        }
        if !conditions.noneTags.isEmpty {
            rows.append(Row(kind: .noneTags, tags: conditions.noneTags))
        }
        if !conditions.proficiencies.isEmpty {
            rows.append(Row(kind: .proficiency, proficiencies: Set(conditions.proficiencies)))
        }
        if !conditions.keys.isEmpty {
            rows.append(Row(kind: .keys, keys: conditions.keys))
        }
        if let tempo = conditions.tempo, !tempo.isOpen {
            rows.append(Row(
                kind: .tempo,
                lower: tempo.min.map(Self.bpm) ?? "",
                upper: tempo.max.map(Self.bpm) ?? "",
            ))
        }
        if let length = conditions.length, !length.isOpen {
            rows.append(Row(
                kind: .length,
                lower: length.min.flatMap(LengthValue.init(seconds:))?.text ?? "",
                upper: length.max.flatMap(LengthValue.init(seconds:))?.text ?? "",
            ))
        }
        if conditions.neverPlayed {
            rows.append(Row(kind: .neverPlayed))
        }
        self.rows = rows.isEmpty ? [Row(kind: .anyTags)] : rows
    }

    /// The conditions the rows describe.
    var conditions: SmartFilterConditions {
        var result = SmartFilterConditions()
        for row in rows {
            switch row.kind {
            case .allTags: result.allTags = row.tags
            case .anyTags: result.anyTags = row.tags
            case .noneTags: result.noneTags = row.tags
            case .proficiency:
                result.proficiencies = Proficiency.allCases.filter(row.proficiencies.contains)
            case .keys: result.keys = row.keys
            case .tempo:
                let range = SmartFilterRange(
                    min: Self.number(row.lower),
                    max: Self.number(row.upper),
                )
                result.tempo = range.isOpen ? nil : range
            case .length:
                let range = SmartFilterRange(
                    min: Self.seconds(row.lower),
                    max: Self.seconds(row.upper),
                )
                result.length = range.isOpen ? nil : range
            case .neverPlayed: result.neverPlayed = true
            }
        }
        return result
    }

    /// Why Save is disabled, or nil when the draft can be saved.
    var problem: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give the filter a name."
        }
        for row in rows where row.kind == .tempo || row.kind == .length {
            let isLength = row.kind == .length
            for text in [row.lower, row.upper] where !text.trimmingCharacters(in: .whitespaces)
                .isEmpty
            {
                let valid = isLength ? Self.seconds(text) != nil : Self.number(text) != nil
                if !valid {
                    return isLength
                        ? "Enter lengths as m:ss, for example 3:30."
                        : "Enter tempos as BPM, for example 96."
                }
            }
        }
        return nil
    }

    /// Kinds not used by any row yet (what "+" can add, and what a row's popups offer).
    func unusedKinds(besides row: Row? = nil) -> [Kind] {
        Kind.allCases.filter { kind in
            kind == row?.kind || !rows.contains { $0.kind == kind }
        }
    }

    /// Adds a row of the first unused kind after `row` (or at the end).
    mutating func addRow(after row: Row.ID?) {
        guard let kind = unusedKinds().first else { return }
        let index = row.flatMap { id in rows.firstIndex { $0.id == id } }.map { $0 + 1 }
        rows.insert(Row(kind: kind), at: index ?? rows.count)
    }

    /// Removes `row`; the last row stays (an empty filter matches every song).
    mutating func removeRow(_ row: Row.ID) {
        guard rows.count > 1 else { return }
        rows.removeAll { $0.id == row }
    }

    /// The 24 keys the Key row offers (enharmonic spellings match each other anyway).
    static let keyChoices = [
        "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B",
        "Cm", "C#m", "Dm", "Ebm", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "Bbm", "Bm",
    ]

    private static func bpm(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func seconds(_ text: String) -> Double? {
        (try? LengthValue.parse(text))?.interval
    }
}
