import Foundation
import Support

extension CalendarDay {
    /// Noon on this day in the current time zone (for date pickers; noon never shifts the
    /// day across a DST change).
    var date: Date {
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        return Calendar.current.date(from: components) ?? .now
    }

    /// "Fri 23 Oct 2026".
    var displayText: String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }
}

/// Parsing and formatting of set lengths typed as "45", "45:00" or "1:05:00".
enum DurationText {
    /// "45" means 45 minutes; "45:30" minutes and seconds; "1:05:00" hours too. Nil when
    /// unreadable or not positive.
    static func parse(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 })
        else { return nil }
        let seconds = switch numbers.count {
        case 1: numbers[0] * 60
        case 2: numbers[0] * 60 + numbers[1]
        case 3: numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        default: 0
        }
        return seconds > 0 ? TimeInterval(seconds) : nil
    }
}
