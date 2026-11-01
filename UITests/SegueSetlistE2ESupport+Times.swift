import XCTest

// P8-8: the builder's times from tempo x bars, and reading a time cell or total by its label
// (their accessibility value is the spoken form).

extension SetlistFixture {
    /// "3:40" of whole seconds (as the builder rounds).
    static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// The builder's start column for `titles` in one part (`SetlistTiming`'s rules): known
    /// times accumulate with `changeover` between songs; after an unknown, starts are "≥"
    /// lower bounds and a lower bound of 0:00 reads "--:--".
    static func starts(_ titles: [String], changeover: Double = 0) -> [String] {
        var start = 0.0
        var unknown = false
        var result: [String] = []
        for (index, title) in titles.enumerated() {
            if index > 0 {
                start += changeover
            }
            result.append(!unknown ? clock(start) : start > 0 ? "≥" + clock(start) : "--:--")
            if let seconds = song(title).seconds {
                start += seconds
            } else {
                unknown = true
            }
        }
        return result
    }

    /// The builder's total for `titles` in one part: "~12:00", "~12:00 + 1 unknown" (R189:
    /// no "≥" on totals).
    static func total(_ titles: [String], changeover: Double = 0) -> String {
        let known = titles.compactMap { song($0).seconds }.reduce(0, +)
            + changeover * Double(max(titles.count - 1, 0))
        let unknown = titles.count { song($0).seconds == nil }
        return unknown == 0 ? "~" + clock(known) : "~\(clock(known)) + \(unknown) unknown"
    }
}

extension SetlistE2E {
    /// The labels alone of every element with `identifier` (a time cell or a total whose
    /// value is its spoken form, P8-8 section 9).
    static func labels(_ app: XCUIApplication, _ identifier: String) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var found: [String] = []
        var stack: [any XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            if node.identifier == identifier {
                found.append(node.label)
            }
            stack.append(contentsOf: node.children.reversed())
        }
        return found
    }
}
