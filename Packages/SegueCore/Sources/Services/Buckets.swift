import Foundation

/// A count or duration reported only as a coarse range (spec section 5). Buckets are closed
/// enums with fixed raw values, so a bucket can never carry anything but its label.
public protocol LogBucket: Sendable, CaseIterable, RawRepresentable where RawValue == String {}

/// Library size in songs.
public enum SongBucket: String, LogBucket {
    case zero = "0"
    case oneToNine = "1-9"
    case tenTo49 = "10-49"
    case fiftyTo99 = "50-99"
    case hundredTo249 = "100-249"
    case twoFiftyTo499 = "250-499"
    case fiveHundredTo999 = "500-999"
    case thousandPlus = "1000+"

    public init(_ count: Int) {
        switch count {
        case ..<1: self = .zero
        case 1 ..< 10: self = .oneToNine
        case 10 ..< 50: self = .tenTo49
        case 50 ..< 100: self = .fiftyTo99
        case 100 ..< 250: self = .hundredTo249
        case 250 ..< 500: self = .twoFiftyTo499
        case 500 ..< 1000: self = .fiveHundredTo999
        default: self = .thousandPlus
        }
    }
}

/// Setlists, gigs, files in an import, songs in a show.
public enum SmallBucket: String, LogBucket {
    case zero = "0"
    case one = "1"
    case twoToFour = "2-4"
    case fiveToNine = "5-9"
    case tenTo19 = "10-19"
    case twentyTo49 = "20-49"
    case fiftyPlus = "50+"

    public init(_ count: Int) {
        switch count {
        case ..<1: self = .zero
        case 1: self = .one
        case 2 ..< 5: self = .twoToFour
        case 5 ..< 10: self = .fiveToNine
        case 10 ..< 20: self = .tenTo19
        case 20 ..< 50: self = .twentyTo49
        default: self = .fiftyPlus
        }
    }
}

/// How long a show lasted.
public enum DurationBucket: String, LogBucket {
    case under15m = "<15m"
    case from15to30m = "15-30m"
    case from30to60m = "30-60m"
    case from60to90m = "60-90m"
    case from90to120m = "90-120m"
    case over120m = "120m+"

    /// `seconds` is the show's length; negative values count as zero.
    public init(seconds: TimeInterval) {
        let minutes = seconds / 60
        switch minutes {
        case ..<15: self = .under15m
        case 15 ..< 30: self = .from15to30m
        case 30 ..< 60: self = .from30to60m
        case 60 ..< 90: self = .from60to90m
        case 90 ..< 120: self = .from90to120m
        default: self = .over120m
        }
    }
}

/// Whole days since the first launch.
public enum DaysBucket: String, LogBucket {
    case zero = "0"
    case one = "1"
    case twoToSix = "2-6"
    case sevenTo13 = "7-13"
    case fourteenTo29 = "14-29"
    case thirtyTo89 = "30-89"
    case ninetyPlus = "90+"

    public init(days: Int) {
        switch days {
        case ..<1: self = .zero
        case 1: self = .one
        case 2 ..< 7: self = .twoToSix
        case 7 ..< 14: self = .sevenTo13
        case 14 ..< 30: self = .fourteenTo29
        case 30 ..< 90: self = .thirtyTo89
        default: self = .ninetyPlus
        }
    }
}
