import Foundation
import Synchronization

/// A ULID (https://github.com/ulid/spec): 48-bit millisecond timestamp + 80 bits of
/// randomness, rendered as 26 Crockford base32 characters. Lexicographic order of the string
/// form equals chronological order of the timestamp.
public struct ULID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    /// The 16 raw bytes, big-endian (timestamp first).
    public let bytes: [UInt8]

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)

    /// Creates a ULID from a timestamp and 10 bytes of randomness.
    public init(timestamp: Date, randomness: [UInt8]) {
        self.init(milliseconds: timestamp.ulidMilliseconds, randomness: randomness)
    }

    /// Creates a ULID from a millisecond timestamp and 10 bytes of randomness.
    public init(milliseconds millis: UInt64, randomness: [UInt8]) {
        precondition(randomness.count == 10, "ULID randomness must be exactly 10 bytes")
        var raw = [UInt8](repeating: 0, count: 16)
        for index in 0 ..< 6 {
            raw[index] = UInt8(truncatingIfNeeded: millis >> (8 * UInt64(5 - index)))
        }
        raw.replaceSubrange(6 ..< 16, with: randomness)
        bytes = raw
    }

    /// Parses the canonical 26-character form (case-insensitive). Returns nil if malformed.
    public init?(string: String) {
        let chars = Array(string.uppercased().utf8)
        guard chars.count == 26 else { return nil }
        var value: (high: UInt64, low: UInt64) = (0, 0)
        for (index, char) in chars.enumerated() {
            guard let digit = Self.alphabet.firstIndex(of: char) else { return nil }
            // The first character may only carry 3 bits (128 = 26 * 5 - 2).
            if index == 0, digit > 7 {
                return nil
            }
            value.high = (value.high << 5) | (value.low >> 59)
            value.low = (value.low << 5) | UInt64(digit)
        }
        var raw = [UInt8](repeating: 0, count: 16)
        for index in 0 ..< 8 {
            raw[index] = UInt8(truncatingIfNeeded: value.high >> (8 * UInt64(7 - index)))
            raw[index + 8] = UInt8(truncatingIfNeeded: value.low >> (8 * UInt64(7 - index)))
        }
        bytes = raw
    }

    /// The embedded timestamp in milliseconds since the Unix epoch.
    public var milliseconds: UInt64 {
        var millis: UInt64 = 0
        for index in 0 ..< 6 {
            millis = (millis << 8) | UInt64(bytes[index])
        }
        return millis
    }

    /// The embedded timestamp (millisecond precision).
    public var timestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    /// The canonical 26-character Crockford base32 form.
    public var description: String {
        var high: UInt64 = 0
        var low: UInt64 = 0
        for index in 0 ..< 8 {
            high = (high << 8) | UInt64(bytes[index])
            low = (low << 8) | UInt64(bytes[index + 8])
        }
        var out = [Character](repeating: "0", count: 26)
        for index in (0 ..< 26).reversed() {
            out[index] = Character(Unicode.Scalar(Self.alphabet[Int(low & 0x1F)]))
            low = (low >> 5) | (high << 59)
            high >>= 5
        }
        return String(out)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let ulid = Self(string: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ULID string: \(string)",
            )
        }
        self = ulid
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Produces new unique identifiers. Injected so tests get reproducible IDs.
public protocol IDGenerator: Sendable {
    /// Returns a new ULID. Successive calls return strictly increasing values.
    func next() -> ULID
}

/// ULID generator stamped from an injected `Clock`.
///
/// With a `seed` the randomness is a deterministic SplitMix64 stream (tests); without one it
/// uses the system CSPRNG. IDs are monotonic: if the clock has not advanced since the last ID
/// (or went backwards), the previous ID's randomness is incremented instead.
public final class ULIDGenerator: IDGenerator {
    private struct State {
        var seed: UInt64?
        var last: ULID?
    }

    private let clock: any Clock
    private let state: Mutex<State>

    public init(clock: any Clock, seed: UInt64? = nil) {
        self.clock = clock
        state = Mutex(State(seed: seed, last: nil))
    }

    public func next() -> ULID {
        let now = clock.now()
        return state.withLock { state in
            let ulid: ULID = if let last = state.last, last.milliseconds >= now.ulidMilliseconds {
                Self.increment(last)
            } else {
                ULID(timestamp: now, randomness: Self.randomBytes(seed: &state.seed))
            }
            state.last = ulid
            return ulid
        }
    }

    private static func randomBytes(seed: inout UInt64?) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 10)
        if var current = seed {
            for index in out.indices {
                current &+= 0x9E37_79B9_7F4A_7C15
                var mixed = current
                mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
                mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
                mixed ^= mixed >> 31
                out[index] = UInt8(truncatingIfNeeded: mixed)
            }
            seed = current
        } else {
            var generator = SystemRandomNumberGenerator()
            for index in out.indices {
                out[index] = UInt8.random(in: .min ... .max, using: &generator)
            }
        }
        return out
    }

    private static func increment(_ ulid: ULID) -> ULID {
        var raw = ulid.bytes
        var index = raw.count - 1
        while index >= 6 {
            if raw[index] == .max {
                raw[index] = 0
                index -= 1
            } else {
                raw[index] += 1
                break
            }
        }
        precondition(index >= 6, "ULID randomness overflow within one millisecond")
        return ULID(milliseconds: ulid.milliseconds, randomness: Array(raw[6 ..< 16]))
    }
}

private extension Date {
    var ulidMilliseconds: UInt64 {
        UInt64(max(0, (timeIntervalSince1970 * 1000).rounded(.down)))
    }
}
