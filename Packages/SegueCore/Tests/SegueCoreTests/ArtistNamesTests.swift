import ChordPro
import Library
import Testing

/// `ArtistNames` (P8-8 section 3.1, R172, R173): the split table, the matching forms and
/// the display join.
struct ArtistNamesTests {
    @Test(arguments: [
        ("Vishal & Shekhar", ["Vishal", "Shekhar"]),
        ("Arijit Singh, Shreya Ghoshal", ["Arijit Singh", "Shreya Ghoshal"]),
        ("DJ Saahil ft. Rhea", ["DJ Saahil", "Rhea"]),
        ("Atif Aslam featuring Shreya Ghoshal", ["Atif Aslam", "Shreya Ghoshal"]),
        ("Badshah feat. Aastha Gill & Neha Kakkar", ["Badshah", "Aastha Gill", "Neha Kakkar"]),
        ("Atif Aslam (feat. Shreya Ghoshal)", ["Atif Aslam", "Shreya Ghoshal"]),
        ("Atif Aslam (Featuring Shreya Ghoshal)", ["Atif Aslam", "Shreya Ghoshal"]),
        ("A FT. B", ["A", "B"]),
        ("Simon and Garfunkel", ["Simon and Garfunkel"]),
        ("Salim-Sulaiman", ["Salim-Sulaiman"]),
        ("Shankar Ehsaan Loy", ["Shankar Ehsaan Loy"]),
        ("A x B", ["A x B"]),
        ("A with B", ["A with B"]),
        ("A / B", ["A / B"]),
        ("Featherstone", ["Featherstone"]),
        ("Daft Punk ft", ["Daft Punk ft"]),
        ("A feat B", ["A feat B"]),
        ("Microsoft. Band", ["Microsoft. Band"]),
        ("Featuringly", ["Featuringly"]),
        ("arijit singh, Arijit Singh", ["arijit singh"]),
        ("Sōnu, sonu", ["Sōnu"]),
        (", A ,, B,", ["A", "B"]),
        ("mohd rafi, kishore kumaar", ["mohd rafi", "kishore kumaar"]),
    ])
    func `split table`(value: String, parts: [String]) {
        let split = ArtistNames.split(value)
        #expect(split.parts == parts)
        #expect(split.original == value)
        #expect(split.didSplit == (parts.count > 1))
        if parts.count < 2 {
            #expect(split.separators.isEmpty)
        }
    }

    static let separatorCases: [(String, Set<ArtistSeparator>)] = [
        ("Vishal & Shekhar", [.ampersand]),
        ("A, B", [.comma]),
        ("A ft. B", [.feat]),
        ("A (feat. B)", [.feat]),
        ("A feat. B & C", [.feat, .ampersand]),
        ("A,", []),
    ]

    @Test(arguments: separatorCases)
    func `separators record what split`(value: String, separators: Set<ArtistSeparator>) {
        #expect(ArtistNames.split(value).separators == separators)
    }

    @Test
    func `forms of a legacy combined value equal the forms of its split`() {
        #expect(ArtistNames.forms(["Vishal & Shekhar"]) == ArtistNames.forms(["Vishal", "Shekhar"]))
        #expect(ArtistNames.forms(["Vishal & Shekhar"]).count == 2)
        #expect(ArtistNames.forms([]).isEmpty)
        #expect(ArtistNames.forms(["  "]).isEmpty)
        // Case folds in the forms; the stored spelling is never touched.
        #expect(ArtistNames.forms(["ARIJIT SINGH"]) == ArtistNames.forms(["arijit singh"]))
    }

    @Test(arguments: [
        ([String](), nil as String?),
        (["Arijit Singh"], "Arijit Singh"),
        (["Arijit Singh", " Shreya Ghoshal "], "Arijit Singh, Shreya Ghoshal"),
        (["", "B"], "B"),
    ])
    func `display join`(artists: [String], expected: String?) {
        #expect(ArtistNames.display(artists) == expected)
    }

    @Test(arguments: [
        ("  Arijit  ", "Arijit" as String?),
        ("A}B", "AB"),
        ("A\nB", "A B"),
        ("A\r\nB", "A B"),
        ("   ", nil),
    ])
    func `cleaned values`(value: String, expected: String?) {
        #expect(ArtistNames.cleaned(value) == expected)
    }
}
