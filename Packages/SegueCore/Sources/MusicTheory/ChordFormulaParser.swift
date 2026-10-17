// Owner: unit A (MusicTheory). The interval table behind `ChordFormula.parse(suffix:)`.

/// Builds a `ChordFormula` from a chord suffix by consuming known tokens left to right.
///
/// Grammar, informally: an optional leading quality (`m min mi - dim ° ø aug +`), then any
/// sequence of extensions (`6 7 9 11 13 69 6/9 2 4`), major-seventh marks (`maj7 M7 Δ ...`),
/// suspensions (`sus sus2 sus4`), additions (`add9 ...`), alterations (`b5 #5 b9 #9 #11 b13`,
/// also `-5 +9` style after the first character), omissions (`no3 no5 omit3 omit5`) and `alt`.
/// Parentheses and commas are transparent (`7(#9)`, `7(b9,#11)`, `m(maj7)`). Anything left
/// over makes the suffix unknown, so the table is deliberately strict.
struct ChordFormulaParser {
    private var third: Int? = 4
    private var fifth: Int? = 7
    private var seventh: Int?
    private var extensions: Set<Int> = []
    private var added: Set<Int> = []
    private var altered: Set<Int> = []
    private var suspension: Int?
    private var isDiminished = false
    private var allowsBareSeven = false
    private var hasExtension = false
    private var fifthIsAltered = false
    private var isAlteredDominant = false

    static func parse(_ suffix: String) -> ChordFormula? {
        let normalized = suffix
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "△", with: "Δ")
        if normalized.isEmpty {
            return ChordFormula(intervals: [0, 4, 7], essential: [0, 4])
        }
        if normalized == "5" {
            return ChordFormula(intervals: [0, 7], essential: [0, 7])
        }
        var parser = Self()
        var rest = Substring(normalized)
        parser.consumeQuality(&rest)
        while let first = rest.first {
            if "(),".contains(first) {
                rest = rest.dropFirst()
                continue
            }
            guard parser.consumeToken(&rest) else { return nil }
        }
        return parser.formula
    }

    // MARK: - Tokens

    private typealias Action = @Sendable (inout Self) -> Bool

    /// Leading quality marks; only valid as the first token.
    private static let qualities: [(String, Action)] = [
        ("min", { $0.makeMinor() }),
        ("mi", { $0.makeMinor() }),
        ("dim", { $0.makeDiminished() }),
        ("°", { $0.makeDiminished() }),
        ("ø", { $0.makeHalfDiminished() }),
        ("Ø", { $0.makeHalfDiminished() }),
        ("aug", { $0.alterFifth(8) }),
        ("+", { $0.alterFifth(8) }),
        ("m", { $0.makeMinor() }),
        ("-", { $0.makeMinor() }),
    ]

    /// Every other token, longest spelling first where one is a prefix of another.
    private static let tokens: [(String, Action)] = majorSevenths + numbers + modifiers
        + alterations

    private static let majorSevenths: [(String, Action)] = {
        var table: [(String, Action)] = []
        for mark in ["maj", "Maj", "MAJ", "ma", "M", "Δ"] {
            for number in [13, 11, 9, 7] {
                table.append(("\(mark)\(number)", { $0.extend(to: number, seventh: 11) }))
            }
        }
        table.append(("Δ", { $0.extend(to: 7, seventh: 11) }))
        // A bare `maj` / `M` names the major triad (`Cmaj`, `CM`).
        for mark in ["maj", "Maj", "MAJ", "M"] {
            table.append((mark, { $0.third == 4 && !$0.hasExtension }))
        }
        return table
    }()

    private static let numbers: [(String, Action)] = [
        ("13", { $0.extend(to: 13, seventh: nil) }),
        ("11", { $0.extend(to: 11, seventh: nil) }),
        ("6/9", { $0.addSixNine() }),
        ("69", { $0.addSixNine() }),
        ("9", { $0.extend(to: 9, seventh: nil) }),
        ("7", { $0.extend(to: 7, seventh: nil) }),
        ("6", { $0.add(9) }),
        ("4", { $0.add(5) }),
        ("2", { $0.add(2) }),
    ]

    private static let modifiers: [(String, Action)] = [
        ("sus2", { $0.suspend(2) }),
        ("sus4", { $0.suspend(5) }),
        ("sus", { $0.suspend(5) }),
        ("add13", { $0.add(21) }),
        ("add11", { $0.add(17) }),
        ("add9", { $0.add(14) }),
        ("add6", { $0.add(9) }),
        ("add4", { $0.add(5) }),
        ("add2", { $0.add(2) }),
        ("no3", { $0.omit(third: true) }),
        ("omit3", { $0.omit(third: true) }),
        ("no5", { $0.omit(third: false) }),
        ("omit5", { $0.omit(third: false) }),
        ("alt", { $0.makeAltered() }),
    ]

    private static let alterations: [(String, Action)] = {
        let lowered: [(String, Action)] = [
            ("13", { $0.alter(20, replacing: 21) }),
            ("5", { $0.alterFifth(6) }),
            ("9", { $0.alter(13, replacing: 14) }),
            ("6", { $0.alter(8, replacing: nil) }),
        ]
        let raised: [(String, Action)] = [
            ("11", { $0.alter(18, replacing: 17) }),
            ("5", { $0.alterFifth(8) }),
            ("9", { $0.alter(15, replacing: 14) }),
        ]
        var table: [(String, Action)] = []
        for (number, action) in lowered {
            table += [("b\(number)", action), ("-\(number)", action)]
        }
        for (number, action) in raised {
            table += [("#\(number)", action), ("+\(number)", action)]
        }
        return table
    }()

    private mutating func consumeQuality(_ rest: inout Substring) {
        // A major-seventh mark wins over the `m` of a minor quality (`maj7`, `M7`).
        if Self.majorSevenths.contains(where: { rest.hasPrefix($0.0) }) {
            return
        }
        for (spelling, action) in Self.qualities where rest.hasPrefix(spelling) {
            _ = action(&self)
            rest = rest.dropFirst(spelling.count)
            return
        }
    }

    private mutating func consumeToken(_ rest: inout Substring) -> Bool {
        for (spelling, action) in Self.tokens where rest.hasPrefix(spelling) {
            guard action(&self) else { return false }
            rest = rest.dropFirst(spelling.count)
            return true
        }
        return false
    }

    // MARK: - Actions

    private mutating func makeMinor() -> Bool {
        third = 3
        return true
    }

    /// `no3` / `no5`.
    private mutating func omit(third omitsThird: Bool) -> Bool {
        if omitsThird {
            third = nil
        } else {
            fifth = nil
        }
        return true
    }

    private mutating func makeDiminished() -> Bool {
        third = 3
        isDiminished = true
        return alterFifth(6)
    }

    private mutating func makeHalfDiminished() -> Bool {
        third = 3
        seventh = 10
        allowsBareSeven = true
        return alterFifth(6)
    }

    /// `alt` / `7alt`: dominant seventh with b9 #9 #11 b13 and no natural 5th.
    private mutating func makeAltered() -> Bool {
        guard altered.isEmpty, seventh == nil || seventh == 10, extensions.isEmpty else {
            return false
        }
        hasExtension = true
        seventh = 10
        fifth = nil
        altered.formUnion([13, 15, 18, 20])
        isAlteredDominant = true
        return true
    }

    /// A 7th/9th/11th/13th chord: the seventh (major when `seventh` is 11, diminished
    /// after `dim`, else minor) plus the stacked extensions below `number`.
    private mutating func extend(to number: Int, seventh requested: Int?) -> Bool {
        if number == 7, requested == nil, allowsBareSeven {
            allowsBareSeven = false
            return true
        }
        guard !hasExtension else { return false }
        hasExtension = true
        allowsBareSeven = false
        seventh = requested ?? seventh ?? (isDiminished ? 9 : 10)
        let stacked: [Int: [Int]] = [7: [], 9: [14], 11: [14, 17], 13: [14, 17, 21]]
        extensions.formUnion(stacked[number] ?? [])
        return true
    }

    private mutating func addSixNine() -> Bool {
        added.formUnion([9, 14])
        return true
    }

    private mutating func add(_ interval: Int) -> Bool {
        added.insert(interval)
        return true
    }

    private mutating func suspend(_ interval: Int) -> Bool {
        guard suspension == nil else { return false }
        suspension = interval
        third = nil
        return true
    }

    private mutating func alterFifth(_ interval: Int) -> Bool {
        fifth = interval
        fifthIsAltered = true
        return true
    }

    private mutating func alter(_ interval: Int, replacing natural: Int?) -> Bool {
        if let natural {
            extensions.remove(natural)
        }
        altered.insert(interval)
        return true
    }

    // MARK: - Result

    private var formula: ChordFormula {
        var tones: Set = [0]
        var essential: Set = [0]
        if let third {
            tones.insert(third)
            essential.insert(third)
        }
        if let suspension {
            tones.insert(suspension)
            essential.insert(suspension)
        }
        if let fifth {
            tones.insert(fifth)
            if fifthIsAltered || (third == nil && suspension == nil) {
                essential.insert(fifth)
            }
        }
        if let seventh {
            tones.insert(seventh)
            essential.insert(seventh)
        }
        tones.formUnion(extensions)
        if let top = extensions.max() {
            essential.insert(top)
        }
        tones.formUnion(added)
        essential.formUnion(added)
        tones.formUnion(altered)
        // `alt` names a colour, not four required tones: keep a guitar-sized core (#9, b13).
        essential.formUnion(isAlteredDominant ? [15, 20] : altered)
        // A sus4 already sounds the 11th's pitch class; keep one.
        if suspension == 5 {
            tones.remove(17)
            essential.remove(17)
        }
        return ChordFormula(intervals: tones.sorted(), essential: essential.sorted())
    }
}
