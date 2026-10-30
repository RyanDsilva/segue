import Library
import MusicTheory
import Setlists
import Testing

/// `SetComposer.resolve` over the corpus (P8-5 section 13.2): key token or title words,
/// breaks, and the ghost completion.
struct SetComposerResolveTests {
    private static func resolve(_ typed: String, matcher: SongMatcher = ComposerCorpus.matcher)
        -> SetComposerResolution
    {
        SetComposer.resolve(SetComposerLine.parse(typed), rawText: typed, matcher: matcher)
    }

    @Test(arguments: [
        ("kesariya in A", "Kesariya", "A"),
        ("kesariya in a", "Kesariya", "A"),
        ("Kesariyaa (Am)", "Kesariya", "Am"),
        ("tum hi ho key of D", "Tum Hi Ho", "D"),
        ("tum hi ho key D", "Tum Hi Ho", "D"),
        ("tum hi ho key: D", "Tum Hi Ho", "D"),
        ("channa mereya in f#m", "Channa Mereya", "F#m"),
        ("channa mereya in Bb", "Channa Mereya", "Bb"),
        ("channa mereya in C minor", "Channa Mereya", "Cm"),
    ])
    func `a key token sets the key of the song it follows`(
        typed: String,
        title: String,
        keyName: String,
    ) throws {
        let resolution = Self.resolve(typed)
        #expect(resolution.kind == .song)
        let first = try #require(resolution.matches.first)
        #expect(ComposerCorpus.title(of: first.id) == title)
        #expect(resolution.key == SongKey(parsing: keyName))
    }

    @Test
    func `the full line wins when it names a title strongly`() throws {
        let resolution = Self.resolve("stuck in a")
        let first = try #require(resolution.matches.first)
        #expect(ComposerCorpus.title(of: first.id) == "Stuck in a Moment")
        #expect(resolution.key == nil)
    }

    @Test
    func `a title that ends in a key name wins over the key`() {
        var candidates = ComposerCorpus.candidates
        let titled = ComposerCorpus.id(500)
        candidates.append(MatchCandidate(id: titled, title: "Kesariya in A", firstLine: ""))
        let resolution = Self.resolve("kesariya in A", matcher: SongMatcher(candidates: candidates))
        #expect(resolution.matches.first?.id == titled)
        #expect(resolution.matches.first?.tier == .exactTitle)
        #expect(resolution.key == nil)
    }

    @Test
    func `a token that is not a key leaves the whole line as the query`() {
        let resolution = Self.resolve("tum hi ho in H")
        #expect(resolution.kind == .song)
        #expect(resolution.matches.isEmpty)
        #expect(resolution.key == nil)
        #expect(resolution.query == "tum hi ho in H")
    }

    @Test
    func `in A alone is a query`() {
        let resolution = Self.resolve("in A")
        #expect(resolution.kind == .song)
        #expect(resolution.key == nil)
        #expect(resolution.query == "in A")
    }

    @Test(arguments: ["---", "----", "\u{2013}-", "\u{2014}"])
    func `dashes resolve to a break`(typed: String) {
        #expect(Self.resolve(typed).kind == .breakRow)
    }

    @Test(arguments: ["--", "- -", "--- x"])
    func `fewer dashes or more text are a song query`(typed: String) {
        #expect(Self.resolve(typed).kind != .breakRow)
    }

    @Test(arguments: ["", "   ", "!!!", "--"])
    func `blank or punctuation lines resolve to nothing`(typed: String) {
        #expect(Self.resolve(typed) == .empty)
    }

    @Test(arguments: [
        ("Kesa", "Kesariya", "riya"),
        ("kesar", "Kesariya", "iya"),
        ("tum hi", "Tum Hi Ho", " Ho"),
        ("tum hi ", "Tum Hi Ho", "Ho"),
        ("TUM HI HO B", "Tum Hi Ho Bandhu", "andhu"),
        ("dont", "Don't Stop", " Stop"),
        ("cafe", "Café Del Mar", " Del Mar"),
    ])
    func `the ghost completes the title the line starts`(
        typed: String,
        title: String,
        rest: String,
    ) {
        #expect(SetComposer.ghostSuffix(typed: typed, title: title) == rest)
    }

    @Test(arguments: [
        ("kesriya", "Kesariya"),
        ("Kesariya", "Kesariya"),
        ("hi ho", "Tum Hi Ho"),
        ("tum h ", "Tum Hi Ho"),
        ("", "Kesariya"),
        ("tum hi ho bandhu x", "Tum Hi Ho Bandhu"),
    ])
    func `no inline ghost when the title does not start with the line`(
        typed: String,
        title: String,
    ) {
        #expect(SetComposer.ghostSuffix(typed: typed, title: title) == nil)
    }
}
