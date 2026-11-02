import Foundation

extension HindiRomanizer {
    /// The casual map (spec 7.3 step 3, with bake-off 5.5 rule 1: ड़ "d", ढ़ "dh").
    enum Table {
        static let consonants: [Unicode.Scalar: String] = [
            "\u{0915}": "k", "\u{0916}": "kh", "\u{0917}": "g", "\u{0918}": "gh", "\u{0919}": "n",
            "\u{091A}": "ch", "\u{091B}": "chh", "\u{091C}": "j", "\u{091D}": "jh", "\u{091E}": "n",
            "\u{091F}": "t", "\u{0920}": "th", "\u{0921}": "d", "\u{0922}": "dh", "\u{0923}": "n",
            "\u{0924}": "t", "\u{0925}": "th", "\u{0926}": "d", "\u{0927}": "dh", "\u{0928}": "n",
            "\u{092A}": "p", "\u{092B}": "ph", "\u{092C}": "b", "\u{092D}": "bh", "\u{092E}": "m",
            "\u{092F}": "y", "\u{0930}": "r", "\u{0932}": "l", "\u{0935}": "v", "\u{0936}": "sh",
            "\u{0937}": "sh", "\u{0938}": "s", "\u{0939}": "h", "\u{0933}": "l",
        ]

        /// Consonant plus nukta.
        static let nuktaConsonants: [Unicode.Scalar: String] = [
            "\u{0915}": "q", "\u{0916}": "kh", "\u{0917}": "gh", "\u{091C}": "z", "\u{092B}": "f",
            "\u{0921}": "d", "\u{0922}": "dh", "\u{092F}": "y",
        ]

        /// U+0958-095F, the precomposed nukta letters, to their base consonant.
        static let nuktaBases: [UInt32: UInt32] = [
            0x0958: 0x0915, 0x0959: 0x0916, 0x095A: 0x0917, 0x095B: 0x091C, 0x095C: 0x0921,
            0x095D: 0x0922, 0x095E: 0x092B, 0x095F: 0x092F,
        ]

        static let vowels: [Unicode.Scalar: String] = [
            "\u{0905}": "a", "\u{0906}": "aa", "\u{0907}": "i", "\u{0908}": "ee", "\u{0909}": "u",
            "\u{090A}": "oo", "\u{090F}": "e", "\u{0910}": "ai", "\u{0913}": "o", "\u{0914}": "au",
            "\u{090B}": "ri", "\u{0911}": "o", "\u{090D}": "e",
        ]

        static let signs: [Unicode.Scalar: String] = [
            "\u{093E}": "aa", "\u{093F}": "i", "\u{0940}": "ee", "\u{0941}": "u", "\u{0942}": "oo",
            "\u{0947}": "e", "\u{0948}": "ai", "\u{094B}": "o", "\u{094C}": "au", "\u{0943}": "ri",
            "\u{0949}": "o", "\u{0945}": "e",
        ]

        /// Frequent lyric words whose casual spelling the rules would not produce, with the
        /// long function-word spellings of R182 (woh, nahin, kyun, hain). Keys are decomposed
        /// (a nukta letter as base plus U+093C). Every entry has a test row.
        static let overrides: [String: String] = [
            "\u{0939}\u{0948}": "hai",
            "\u{0939}\u{0948}\u{0902}": "hain",
            "\u{092E}\u{0947}\u{0902}": "mein",
            "\u{092E}\u{0948}\u{0902}": "main",
            "\u{0915}\u{094D}\u{092F}\u{094B}\u{0902}": "kyun",
            "\u{0928}\u{0939}\u{0940}\u{0902}": "nahin",
            "\u{092A}\u{094D}\u{092F}\u{093E}\u{0930}": "pyaar",
            "\u{0926}\u{093F}\u{0932}": "dil",
            "\u{0924}\u{0941}\u{092E}": "tum",
            "\u{091C}\u{093C}\u{093F}\u{0902}\u{0926}\u{0917}\u{0940}": "zindagi",
            "\u{0906}\u{0901}\u{0916}\u{0947}\u{0902}": "aankhen",
            "\u{0926}\u{0940}\u{0935}\u{093E}\u{0928}\u{093E}": "deewana",
            "\u{0939}\u{0942}\u{0901}": "hoon",
            "\u{0935}\u{094B}": "woh",
            "\u{0939}\u{092E}": "hum",
        ]
    }
}
