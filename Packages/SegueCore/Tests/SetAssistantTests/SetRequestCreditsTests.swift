import Foundation
import Library
@testable import SetAssistant
import Support
import Testing

/// Artists and movies in a set request (P8-8 section 3.5.2, R173): "by <artist>", "<artist>
/// songs", "from <movie>", negation, and admission (any of, ANDed with the other kinds).
struct SetRequestCreditsTests {
    static let artists = [
        "Arijit Singh", "Shreya Ghoshal", "Shreya Iyer", "Vishal & Shekhar", "Atif Aslam",
    ]
    static let albums = ["Kalank", "Dil Chahta Hai"]
    static let lexicon = SetRequestLexicon(
        tags: ["ballad", "hindi", "upbeat"],
        artists: artists,
        albums: albums,
    )

    @Test(arguments: [
        ("ballads by arijit", [SetChip.tag("ballad"), .artist("Arijit Singh")]),
        ("arijit songs", [.artist("Arijit Singh")]),
        ("by Arijit Singh", [.artist("Arijit Singh")]),
        ("songs by shekhar", [.artist("Shekhar")]),
        ("by vishal & shekhar", [.artist("Vishal & Shekhar")]),
        ("from kalank", [.album("Kalank")]),
        ("songs from the movie kalank", [.album("Kalank")]),
        ("from the film dil chahta hai", [.album("Dil Chahta Hai")]),
        ("kalank songs", [.album("Kalank")]),
        ("no arijit", [.excludeArtist("Arijit Singh")]),
        ("not by atif", [.excludeArtist("Atif Aslam")]),
        ("not from kalank", [.excludeAlbum("Kalank")]),
        ("hindi songs by arijit or atif", [.tag("hindi"), .artist("Arijit Singh")]),
        ("upbeat by arijit, by atif", [
            .tag("upbeat"),
            .artist("Arijit Singh"),
            .artist("Atif Aslam"),
        ]),
    ])
    func `credits read as chips`(text: String, chips: [SetChip]) {
        #expect(Self.lexicon.parse(text).chips == chips)
    }

    @Test
    func `an ambiguous first name stays leftover`() {
        let result = Self.lexicon.parse("shreya songs")
        #expect(result.chips.isEmpty)
        #expect(result.leftover == ["shreya"])
        #expect(Self.lexicon.parse("by shreya ghoshal").chips == [.artist("Shreya Ghoshal")])
    }

    @Test
    func `a bare name without by or songs is not a chip`() {
        #expect(Self.lexicon.parse("arijit").chips.isEmpty)
        #expect(Self.lexicon.parse("kalank").chips.isEmpty)
    }

    @Test
    func `a smart filter name wins over an album after from`() {
        let ids = ULIDGenerator(clock: ManualClock(), seed: 3)
        let filter = SmartFilterName(id: SmartFilterID(ids.next()), name: "Kalank")
        let lexicon = SetRequestLexicon(tags: [], smartFilters: [filter], albums: ["Kalank"])
        #expect(lexicon.parse("from kalank").chips == [.smartFilter(filter.id)])
        #expect(lexicon.parse("songs from the movie kalank").chips == [.album("Kalank")])
    }

    @Test
    func `tags win a name they share`() {
        let lexicon = SetRequestLexicon(tags: ["hindi"], artists: ["Hindi"], albums: ["Hindi"])
        #expect(lexicon.parse("hindi songs").chips == [.tag("hindi")])
    }

    @Test
    func `without library names nothing changes`() {
        let plain = SetRequestLexicon(tags: ["ballad"])
        #expect(plain.parse("ballads by arijit").chips == [.tag("ballad")])
        #expect(plain.parse("ballads by arijit").leftover == ["by", "arijit"])
    }

    @Test
    func `chip titles and slots`() {
        #expect(SetChip.artist("Arijit Singh").title() == "by Arijit Singh")
        #expect(SetChip.excludeArtist("Arijit Singh").title() == "not by Arijit Singh")
        #expect(SetChip.album("Kalank").title() == "from Kalank")
        #expect(SetChip.excludeAlbum("Kalank").title() == "not from Kalank")
        #expect(SetChip.artist("A").slot == SetChip.excludeArtist("a").slot)
        #expect(SetChip.artist("A").slot != SetChip.album("A").slot)
    }

    static func song(_ id: Int, artists: [String], album: String? = nil, tags: [String] = [])
        -> AssistantSong
    {
        AssistantSong(
            id: SongID(ULID(milliseconds: UInt64(id), randomness: Array(repeating: 0, count: 10))),
            title: "Song \(id)",
            tags: tags,
            artists: artists,
            album: album,
        )
    }

    @Test
    func `artist and album chips admit any of and AND with tags`() {
        let arijit = Self.song(1, artists: ["Arijit Singh"], album: "Kalank", tags: ["ballad"])
        let duo = Self.song(2, artists: ["Vishal & Shekhar"], tags: ["upbeat"])
        let atif = Self.song(3, artists: ["Atif Aslam"], album: "Kalank")
        let none = Self.song(4, artists: [])
        func admitted(_ kinds: [SetChip]) -> [Int] {
            let request = SetRequest(kinds: kinds)
            return [arijit, duo, atif, none].enumerated()
                .filter { SetBuilder.admits($1, request, smartFilterMatches: [:]) }
                .map { $0.offset + 1 }
        }
        #expect(admitted([.artist("Arijit Singh"), .artist("Atif Aslam")]) == [1, 3])
        #expect(admitted([.artist("Shekhar")]) == [2])
        #expect(admitted([.artist("Arijit Singh"), .tag("upbeat")]).isEmpty)
        #expect(admitted([.album("kalank")]) == [1, 3])
        #expect(admitted([.album("Kalank"), .excludeArtist("Atif Aslam")]) == [1])
        #expect(admitted([.excludeAlbum("Kalank")]) == [2, 4])
        #expect(admitted([.artist("A"), .excludeArtist("A")]).count == 4)
    }

    @Test
    func `the request's song filter carries artists and albums`() throws {
        let request = SetRequest(kinds: [.artist("Shekhar"), .excludeAlbum("Kalank")])
        let filter = try #require(request.songFilter)
        #expect(filter.artists == SongFilter.artistForms(["Shekhar"]))
        #expect(filter.excludedAlbums == SongFilter.albumForms(["Kalank"]))
        #expect(SetRequest(kinds: [.album("Dus")]).songFilter?.albums
            == SongFilter.albumForms(["Dus"]))
    }
}
