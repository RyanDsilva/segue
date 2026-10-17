import Foundation

/// A calendar date with no time or time zone ("2026-10-23"): a setlist's gig date and a
/// gig log entry's date. Stored as that string so the day never shifts with the time zone.
public struct CalendarDay: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// A day from its parts. Returns nil when the parts are not a real date.
    public init?(year: Int, month: Int, day: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard Self.calendar.date(from: components).map({ date in
            let back = Self.calendar.dateComponents([.year, .month, .day], from: date)
            return back.year == year && back.month == month && back.day == day
        }) == true else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `timeZone` (default: the current one).
    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Self.calendar
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    /// `YYYY-MM-DD`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Self(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid calendar day: \(text)",
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static let calendar = Calendar(identifier: .gregorian)
}
