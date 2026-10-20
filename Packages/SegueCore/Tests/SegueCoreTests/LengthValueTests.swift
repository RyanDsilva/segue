import ChordPro
import Foundation
import Testing

/// The forgiving Length field parser (P3-5, R91): what a person types, and why it is refused.
struct LengthValueTests {
    @Test(arguments: [
        ("245", 245), ("4:05", 245), ("4:5", 245), ("04:05", 245), ("4.05", 245),
        ("4 05", 245), (" 4 : 05 ", 245), ("1:02:05", 3725), ("1.02.05", 3725),
        ("100:00", 6000), ("59", 59), ("1", 1),
    ])
    func `accepts what people type`(text: String, seconds: Int) throws {
        #expect(try LengthValue.parse(text)?.seconds == seconds)
    }

    @Test(arguments: [
        ("abc", LengthValue.Problem.unreadable), ("4.5", .unreadable), ("4 5", .unreadable),
        ("4:", .unreadable), ("1:2:3:4", .unreadable), ("4:05.5", .unreadable),
        ("4:005", .unreadable), ("4:75", .partOverSixty), ("1:60:00", .partOverSixty),
        ("0", .zero), ("0:00", .zero), ("-4:05", .negative), ("\u{2212}5", .negative),
        ("24:00:00", .tooLong), ("9999999", .tooLong),
    ])
    func `refuses with a reason`(text: String, problem: LengthValue.Problem) {
        #expect(throws: problem) { try LengthValue.parse(text) }
    }

    @Test
    func `empty text clears and values format back`() throws {
        #expect(try LengthValue.parse("  ") == nil)
        #expect(LengthValue(seconds: 245)?.text == "4:05")
        #expect(LengthValue(seconds: 59)?.text == "0:59")
        #expect(LengthValue(seconds: 3725)?.text == "1:02:05")
        #expect(LengthValue(seconds: 244.6)?.seconds == 245)
        #expect(LengthValue(seconds: 0.4) == nil)
        #expect(LengthValue(seconds: -3) == nil)
        #expect(LengthValue(seconds: .infinity) == nil)
    }
}
