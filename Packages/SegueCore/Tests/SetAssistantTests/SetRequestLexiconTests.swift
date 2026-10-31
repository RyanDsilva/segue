import Foundation
import Library
@testable import SetAssistant
import Support
import Testing

/// The instant lexicon (spec 7 step 1): the spike's 15 set prompts (section 4), Hinglish
/// requests, and the ambiguous spellings it must not misread.
struct SetRequestLexiconTests {
    static let lexicon = SetRequestLexicon(tags: AssistantFixture.tags)

    struct Case: CustomTestStringConvertible, Sendable {
        var text: String
        var chips: [SetChip]
        var leftover: [String]

        var testDescription: String {
            text
        }
    }

    /// The spike's prompts (`research/phase3-spikes/.../Types.swift` `setRequests`), against
    /// the spike's tag vocabulary.
    static let spikePrompts: [Case] = [
        Case(
            text: "45 min set, mostly songs I know well, upbeat start",
            chips: [.length(2700), .proficiency(.ready), .opener(tag: "upbeat")],
            leftover: [],
        ),
        Case(
            text: "something upbeat in G I know well",
            chips: [.tag("upbeat"), .key("G"), .proficiency(.ready)],
            leftover: [],
        ),
        Case(
            text: "an hour of acoustic stuff, nothing I'm still learning",
            chips: [.length(3600), .tag("acoustic"), .proficiency(.ready)],
            leftover: [],
        ),
        Case(
            text: "10 songs for a wedding, end with a crowd pleaser",
            chips: [.songCount(10), .tag("wedding"), .closer(tag: "crowd pleaser")],
            leftover: [],
        ),
        Case(
            text: "30 minutes of hindi songs I know cold",
            chips: [.length(1800), .tag("hindi"), .proficiency(.pro)],
            leftover: [],
        ),
        Case(
            text: "chill ballads under 90 bpm",
            chips: [.tag("ballad"), .tempo(TempoRange(max: 90))],
            leftover: ["chill"],
        ),
        Case(
            text: "90 minute rock set, high energy throughout, no covers",
            chips: [.length(5400), .tag("rock"), .excludeTag("cover")],
            leftover: ["high", "energy", "throughout"],
        ),
        Case(
            text: "quick 20 min opener set, start soft and build up",
            chips: [.length(1200)],
            leftover: ["quick", "opener", "start", "soft", "up"],
        ),
        Case(
            text: "two hour gig, originals only, songs in D or A",
            chips: [.length(7200), .tag("original"), .key("D"), .key("A")],
            leftover: [],
        ),
        Case(
            text: "singalongs between 100 and 130 bpm",
            chips: [.tag("singalong"), .tempo(TempoRange(min: 100, max: 130))],
            leftover: [],
        ),
        Case(
            text: "give me 5 mellow songs in E minor",
            chips: [.songCount(5), .key("Em")],
            leftover: ["mellow"],
        ),
        Case(
            text: "40 mins, skip the hindi ones, finish big",
            chips: [.length(2400), .excludeTag("hindi"), .closer(tag: "crowd pleaser")],
            leftover: [],
        ),
        Case(
            text: "background dinner music, 1.5 hours, low energy, anything I can play",
            chips: [.length(5400), .proficiency(.ready)],
            leftover: ["background", "dinner", "low", "energy"],
        ),
        Case(
            text: "kuch romantic hindi gaane, 25 minute",
            chips: [.tag("hindi"), .length(1500)],
            leftover: ["romantic"],
        ),
        Case(
            text: "pub night, 75 minutes, crowd pleasers and singalongs, nothing below Ready",
            chips: [
                .length(4500),
                .tag("crowd pleaser"),
                .tag("singalong"),
                .proficiency(.ready),
            ],
            leftover: ["pub", "night"],
        ),
    ]

    @Test(arguments: spikePrompts)
    func `spike set prompts`(_ example: Case) {
        let result = Self.lexicon.parse(example.text)
        #expect(result.chips == example.chips)
        #expect(result.leftover == example.leftover)
    }

    /// Romanized Hindi requests: casual spellings of the library's tags, Hindi numbers and
    /// hour words, postfix "nahi".
    static let hinglish: [Case] = [
        Case(
            text: "kuch romantic gaane, 25 minute",
            chips: [.tag("Romantic"), .length(1500)],
            leftover: [],
        ),
        Case(
            text: "bolywood ke gaane ek ghanta",
            chips: [.tag("Bollywood"), .length(3600)],
            leftover: [],
        ),
        Case(
            text: "pyaar wale gaane, dedh ghante ka set",
            chips: [.tag("pyar"), .length(5400)],
            leftover: [],
        ),
        Case(
            text: "aadha ghanta, sufi nahi",
            chips: [.length(1800), .excludeTag("Sufi")],
            leftover: [],
        ),
        Case(
            text: "do ghante, purane gaane jo achhe se aate hain",
            chips: [.length(7200), .tag("purane"), .proficiency(.ready)],
            leftover: ["jo"],
        ),
    ]

    @Test(arguments: hinglish)
    func `hinglish requests`(_ example: Case) {
        let lexicon = SetRequestLexicon(tags: ["Romantic", "Bollywood", "pyar", "Sufi", "purane"])
        let result = lexicon.parse(example.text)
        #expect(result.chips == example.chips)
        #expect(result.leftover == example.leftover)
    }

    static let edges: [Case] = [
        // Articles and English words are not keys.
        Case(text: "A 30 min set in a minute", chips: [.length(1800)], leftover: []),
        Case(text: "I am ready", chips: [.proficiency(.ready)], leftover: ["am"]),
        Case(
            text: "no Bb, nothing in F#m",
            chips: [.excludeKey("Bb"), .excludeKey("F#m")],
            leftover: [],
        ),
        Case(text: "key of e minor", chips: [.key("Em")], leftover: []),
        Case(text: "F#m and Bb songs", chips: [.key("F#m"), .key("Bb")], leftover: []),
        Case(
            text: "sing-along ones, no covers or ballads",
            chips: [.tag("singalong"), .excludeTag("cover"), .excludeTag("ballad")],
            leftover: [],
        ),
        Case(text: "100-130 bpm", chips: [.tempo(TempoRange(min: 100, max: 130))], leftover: []),
        Case(
            text: "around 120 bpm",
            chips: [.tempo(TempoRange(min: 115, max: 125))],
            leftover: [],
        ),
        Case(text: "at least 140 bpm", chips: [.tempo(TempoRange(min: 140))], leftover: []),
        Case(text: "up to 100bpm", chips: [.tempo(TempoRange(max: 100))], leftover: []),
        Case(
            text: "half an hour, recent ok",
            chips: [.length(1800), .avoidRecent(false)],
            leftover: [],
        ),
        Case(
            text: "an hour and a half including learning",
            chips: [.length(5400), .proficiency(.anything)],
            leftover: [],
        ),
        Case(text: "45min, a dozen songs", chips: [.length(2700), .songCount(12)], leftover: []),
        Case(
            text: "start with a ballad, close with a singalong",
            chips: [.opener(tag: "ballad"), .closer(tag: "singalong")],
            leftover: [],
        ),
        Case(
            text: "upbeat start, 30 minutes, 45 minutes",
            chips: [.opener(tag: "upbeat"), .length(2700)],
            leftover: [],
        ),
    ]

    @Test(arguments: edges)
    func `ambiguous spellings`(_ example: Case) {
        let result = Self.lexicon.parse(example.text)
        #expect(result.chips == example.chips)
        #expect(result.leftover == example.leftover)
    }

    @Test
    func `slot phrases need the tag in the library (R92)`() {
        let lexicon = SetRequestLexicon(tags: ["rock"])
        let result = lexicon.parse("finish big, upbeat start")
        #expect(result.chips.isEmpty)
        #expect(result.leftover == ["finish", "big", "upbeat", "start"])
    }

    @Test
    func `smart filter names, with and without "from"`() {
        let ids = ULIDGenerator(clock: ManualClock(), seed: 3)
        let wedding = SmartFilterName(id: SmartFilterID(ids.next()), name: "Wedding set")
        let lexicon = SetRequestLexicon(tags: ["wedding"], smartFilters: [wedding])
        #expect(lexicon.parse("from Wedding set, 40 min").chips
            == [.smartFilter(wedding.id), .length(2400)])
        #expect(lexicon.parse("wedding set songs").chips == [.smartFilter(wedding.id)])
        #expect(lexicon.parse("wedding songs").chips == [.tag("wedding")])
    }

    @Test
    func `a request of chips merges later chips over earlier ones`() {
        let request = SetRequest(kinds: [
            .length(1800), .tag("rock"), .excludeTag("Rock"), .length(2700), .key("G"),
            .excludeKey("G"),
        ])
        #expect(request.targetLength == 2700)
        #expect(request.includeTags.isEmpty)
        #expect(request.excludeTags == ["Rock"])
        #expect(request.keys.isEmpty)
        #expect(request.excludeKeys == ["G"])
        #expect(request.proficiency == .notLearning)
        #expect(request.avoidRecent)
    }
}
