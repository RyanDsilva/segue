import Foundation
@testable import SeguePersonalModules
import Testing

/// Spec 7.3 and 15.1: the override list (R182's long spellings), the bake-off's rule cases,
/// and Latin, digits and punctuation passing through unchanged. Lines are self-written.
struct HindiRomanizerTests {
    @Test(arguments: [
        ("है", "hai"), ("हैं", "hain"), ("में", "mein"), ("मैं", "main"), ("क्यों", "kyun"),
        ("नहीं", "nahin"), ("प्यार", "pyaar"), ("दिल", "dil"), ("तुम", "tum"), ("ज़िंदगी", "zindagi"),
        ("आँखें", "aankhen"), ("दीवाना", "deewana"), ("हूँ", "hoon"), ("वो", "woh"), ("हम", "hum"),
    ])
    func `every override entry`(deva: String, latin: String) {
        #expect(HindiRomanizer.romanize(deva) == latin)
    }

    @Test(arguments: [
        ("चलते", "chalte"), ("करना", "karna"), ("मरने", "marne"), ("सकते", "sakte"),
        ("धड़कन", "dhadkan"), ("थोड़ी", "thodi"), ("बढ़ा", "badha"), ("पहला", "pehla"),
        ("कहती", "kehti"), ("रह", "reh"), ("न", "na"), ("साथ", "saath"), ("रात", "raat"),
        ("बादल", "baadal"), ("सपना", "sapna"), ("ज़रा", "zara"), ("फ़िर", "fir"), ("गाना", "gaana"),
    ])
    func `rule cases`(deva: String, latin: String) {
        #expect(HindiRomanizer.romanize(deva) == latin)
    }

    @Test
    func `a precomposed nukta letter reads like base plus nukta`() {
        #expect(HindiRomanizer.romanize("\u{095B}\u{0930}\u{093E}") == HindiRomanizer
            .romanize("ज़रा"))
    }

    @Test(arguments: [
        "Tum hi ho, ab tum hi ho", "I'm on my way - 2x", "", "123 (Chorus) [Am] ...",
    ])
    func `text in Latin passes through byte for byte`(line: String) {
        #expect(HindiRomanizer.romanize(line) == line)
        #expect(!HindiRomanizer.containsDevanagari(line))
    }

    @Test
    func `a mixed line converts only its Devanagari, keeping spacing and punctuation`() {
        #expect(HindiRomanizer.romanize("Oh  तुम हो, 2x! दिल।") == "Oh  tum ho, 2x! dil.")
        #expect(HindiRomanizer.containsDevanagari("Oh तुम"))
    }
}
