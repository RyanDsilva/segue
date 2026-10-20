// P3-5 (R91): a song length as a person types it into the song card's Length field.
//
// Files keep their lenient `{duration}` reading (`Metadata.parseDuration`: `ss`, `mm:ss`,
// `h:mm:ss`, fractions allowed). This is the stricter, friendlier entry side: whole seconds,
// forgiving separators, and a reason when the text cannot be a length. An invalid value never
// reaches the file.

import Foundation

/// A known, positive song length in whole seconds, under 24 hours.
public struct LengthValue: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// Whole seconds, at least 1.
    public let seconds: Int

    /// The longest length the field accepts, in seconds (exclusive): 24 hours.
    public static let limit = 24 * 3600

    /// `seconds` rounded to the nearest second; nil when that is zero or less, not finite, or
    /// 24 hours or more (a `{duration}` that says nothing usable reads as no length).
    public init?(seconds: TimeInterval) {
        guard seconds.isFinite else { return nil }
        let rounded = seconds.rounded()
        guard rounded >= 1, rounded < Double(Self.limit) else { return nil }
        self.seconds = Int(rounded)
    }

    /// The length as a `TimeInterval`.
    public var interval: TimeInterval {
        TimeInterval(seconds)
    }

    /// "4:05", "1:02:05" (hours only when needed). Also the `{duration}` value written.
    public var text: String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    public var description: String {
        text
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.seconds < rhs.seconds
    }

    /// Why typed text is not a length; `message` is what the field shows.
    public enum Problem: Error, Sendable, Hashable {
        /// Not a length at all ("abc", "4.5", "1:2:3:4").
        case unreadable
        /// A minutes or seconds part of 60 or more after the first part ("4:75").
        case partOverSixty
        /// Zero ("0", "0:00").
        case zero
        /// Starts with a minus sign.
        case negative
        /// 24 hours or more.
        case tooLong

        public var message: String {
            switch self {
            case .unreadable: "Type a length like 4:05"
            case .partOverSixty: "Minutes and seconds go up to 59"
            case .zero: "Length must be more than zero"
            case .negative: "Length can't be negative"
            case .tooLong: "Length must be under 24 hours"
            }
        }
    }

    /// Reads what a person typed. Returns nil for empty text (clear the length).
    ///
    /// Accepts `ss` (`245` is 4:05), `m:ss` and `h:mm:ss` (a part after the first may be one
    /// or two digits, under 60), and the same with `.` or spaces in place of `:` as long as
    /// every later part has exactly two digits (`4.05` and `4 05` are 4:05; `4.5` is
    /// ambiguous, so it is refused rather than guessed).
    public static func parse(_ text: String) throws(Problem) -> Self? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let first = trimmed.unicodeScalars.first, first == "-" || first == "\u{2212}" {
            throw .negative
        }
        let parts = try parts(of: trimmed)
        guard (1 ... 3).contains(parts.count), parts.allSatisfy(isDigits) else {
            throw .unreadable
        }
        let total = try total(of: parts)
        guard total > 0 else { throw .zero }
        guard total < limit else { throw .tooLong }
        return Self(seconds: TimeInterval(total))
    }

    /// Seconds from digit-only parts, most significant first.
    private static func total(of parts: [String]) throws(Problem) -> Int {
        // Six digits of a leading part is already over the limit; this also keeps the
        // arithmetic far from overflow.
        guard parts[0].count <= 6 else { throw .tooLong }
        var total = 0
        for (index, part) in parts.enumerated() {
            guard let number = Int(part) else { throw .unreadable }
            if index > 0 {
                guard part.count <= 2 else { throw .unreadable }
                guard number < 60 else { throw .partOverSixty }
            }
            total = total * 60 + number
        }
        return total
    }

    /// Splits on `:` (spaces around it ignored), else on runs of `.` and spaces (later
    /// parts must be two digits).
    private static func parts(of text: String) throws(Problem) -> [String] {
        if text.contains(":") {
            return text.split(separator: ":", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let parts = text.split(whereSeparator: { $0 == "." || $0 == " " || $0 == "\t" })
            .map(String.init)
        guard parts.dropFirst().allSatisfy({ $0.count == 2 }) else { throw .unreadable }
        return parts
    }

    private static func isDigits(_ part: String) -> Bool {
        !part.isEmpty && part.unicodeScalars.allSatisfy { ("0" ... "9").contains($0) }
    }
}
