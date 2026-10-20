import Foundation

/// A stable, platform-independent hash of a value's canonical JSON (sorted keys): the
/// recording key of a task input. Not cryptographic; only stable.
public enum StableHash {
    /// 16 lowercase hex digits of the FNV-1a 64 hash of `value` encoded as sorted-key JSON.
    public static func hex(of value: some Encodable) -> String {
        hex(of: canonicalJSON(value))
    }

    /// 16 lowercase hex digits of the FNV-1a 64 hash of `data`.
    public static func hex(of data: Data) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    /// Sorted keys, no escaped slashes, no whitespace.
    public static func canonicalJSON(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Plain Codable structs of strings, ints and arrays: encoding cannot fail.
        return (try? encoder.encode(value)) ?? Data()
    }
}
