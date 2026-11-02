import Foundation
import Plugins
@testable import SeguePersonalModules
import Testing

/// Spec 8.4, 8.5 and 15.1: the site readers, the generic reader and the fallback, over the
/// committed lyric-redacted fixtures plus malformed variants made from them in code.
struct PageReaderTests {
    static func chart(_ reading: PageReading) throws -> ParsedChart {
        guard case let .chart(chart) = reading else {
            Issue.record("expected a chart, got \(reading)")
            throw CancellationError()
        }
        return chart
    }

    // MARK: Ultimate Guitar

    @Test
    func `a film song on UG reads title, movie, singer and capo`() throws {
        let html = try FixturePages.text("ug/film-song-capo.html")
        let chart = try Self.chart(TabJSONParser.read(html, url: FixturePages.ugURL))
        let store = try #require(TabJSONParser.store(in: html, url: FixturePages.ugURL))
        let tab = HTMLText.value(store, ["store", "page", "data", "tab"])
        let singer = try #require(
            (HTMLText.value(tab, ["recording", "recording_artists"]) as? [Any])?.first
                .flatMap { HTMLText.string($0, ["artist", "name"]) },
        )
        let name = try #require(HTMLText.string(tab, ["song_name"]))
        #expect(HTMLText.string(tab, ["artist_name"]) == "Misc Soundtrack")
        #expect(chart.fields.title == name.components(separatedBy: " - ").last)
        #expect(chart.fields.album == name.components(separatedBy: " - ").first)
        #expect(chart.fields.artistCredit == singer)
        #expect(chart.fields.capo == 1)
        #expect(chart.fields.key == "Fm")
        #expect(chart.text.contains("[Verse 1]"))
        #expect(!chart.text.contains("[ch]") && !chart.text.contains("[tab]"))
        #expect(chart.text.contains("e|-------7-----8"))
        #expect(SanityCheck.failures(chart).isEmpty)
        #expect(!chart.foundByContentSearch)
    }

    @Test
    func `an English UG chart keeps its artist and capo`() throws {
        let chart = try Self.chart(TabJSONParser.read(
            FixturePages.text("ug/english-capo.html"), url: FixturePages.ugURL,
        ))
        #expect(chart.fields.artistCredit != nil)
        #expect(chart.fields.album == nil)
        #expect(chart.fields.capo == 2)
        #expect(SanityCheck.failures(chart).isEmpty)
    }

    @Test(arguments: [("ug/tab-only.html", NoChartReason.tab), ("ug/pro.html", .pro)])
    func `tab and Pro pages are refused`(name: String, reason: NoChartReason) throws {
        let html = try FixturePages.text(name)
        #expect(TabJSONParser.read(html, url: FixturePages.ugURL) == .refused(reason))
        #expect(PageParserRegistry.read(html, url: FixturePages.ugURL, loadPath: .plain)
            == .failure(.noChart(reason)))
    }

    @Test
    func `the hidden view's store wrapper reads like the page`() throws {
        let html = try FixturePages.text("ug/film-song-capo.html")
        let store = try #require(TabJSONParser.store(in: html, url: FixturePages.ugURL))
        let data = try JSONSerialization.data(withJSONObject: store)
        let wrapped = try #require(String(bytes: data, encoding: .utf8))
        #expect(TabJSONParser.read(wrapped, url: FixturePages.ugURL)
            == TabJSONParser.read(html, url: FixturePages.ugURL))
    }

    @Test
    func `a moved content path is found by the content search`() throws {
        let html = try FixturePages.text("ug/film-song-capo.html")
        var store = try #require(TabJSONParser.store(in: html, url: FixturePages.ugURL))
        var root = try #require(store["store"] as? [String: Any])
        var page = try #require(root["page"] as? [String: Any])
        var data = try #require(page["data"] as? [String: Any])
        var view = try #require(data["tab_view"] as? [String: Any])
        view["moved"] = ["deeper": view["wiki_tab"] as Any]
        view["wiki_tab"] = nil
        data["tab_view"] = view
        page["data"] = data
        root["page"] = page
        store["store"] = root
        let json = try #require(try String(
            bytes: JSONSerialization.data(withJSONObject: store),
            encoding: .utf8,
        ))
        let chart = try Self.chart(TabJSONParser.read(json, url: FixturePages.ugURL))
        #expect(chart.foundByContentSearch)
    }

    @Test(arguments: [
        "<html><body><p>no store here</p></body></html>",
        "<div class=\"js-store\" data-content=\"{&quot;store&quot;: {\"></div>",
    ])
    func `a missing or truncated store is unreadable`(html: String) {
        #expect(TabJSONParser.read(html, url: FixturePages.ugURL) == .unreadable)
    }

    @Test(arguments: [
        ("[ch]D[/ch]/[ch]F#[/ch]", "D/F#"), ("[ch]D[/ch]/F#", "D/F#"), (
            "[ch]A[/ch](add9)",
            "A(add9)",
        ),
    ])
    func `split slash chords and qualities rejoin`(markup: String, chord: String) throws {
        #expect(try #require(TabJSONParser.convert("[tab]\(markup)  [ch]G[/ch]\nla la la[/tab]"))
            .hasPrefix("\(chord)  G"))
    }

    @Test
    func `glued chords are re-spaced on chord-only lines only`() throws {
        let text = try #require(TabJSONParser.convert("[ch]Am[/ch][ch]G[/ch]\nHello there"))
        #expect(text == "Am G\nHello there")
        #expect(TabJSONParser.converted("[ch]C[/ch]Hello there").isSuccess == false)
    }

    @Test
    func `section and style tags, entities and line ends`() throws {
        let text = try #require(TabJSONParser.convert(
            "[verse]\r\n[b]Rock &amp; roll[/b] all [i]night[/i]\r\n[/verse]",
        ))
        #expect(text == "[Verse]\nRock & roll all night")
    }

    // MARK: Chordie and E-Chords

    @Test
    func `a Chordie page writes its chords inline`() throws {
        let chart = try Self.chart(ChordSpansParser.read(
            FixturePages.text("chordie/hindi.html"), url: FixturePages.chordieURL,
        ))
        #expect(chart.text.contains("[Gm]"))
        #expect(!chart.text.contains("<span"))
        #expect(chart.fields.title != nil && chart.fields.artistCredit != nil)
        #expect(SanityCheck.failures(chart).isEmpty)
    }

    @Test
    func `a Chordie removal notice is refused as removed`() throws {
        let html = try FixturePages.text("chordie/removed.html")
        #expect(ChordSpansParser.read(html, url: FixturePages.chordieURL) == .refused(.removed))
    }

    @Test
    func `an E-Chords pre keeps its columns and fields`() throws {
        let html = try FixturePages.text("echords/english.html")
        let chart = try Self.chart(ChordPreParser.read(html, url: FixturePages.echordsURL))
        #expect(chart.text.components(separatedBy: "\n").count > 20)
        #expect(chart.text.contains("Em7            G"))
        #expect(chart.fields.title != nil && chart.fields.artistCredit != nil)
        #expect(SanityCheck.failures(chart).isEmpty)
    }

    @Test
    func `the Hindi word Ab tagged as a chord stays lyric text`() throws {
        let chart = try Self.chart(ChordPreParser.read(
            FixturePages.text("echords/ab-lyric.html"), url: FixturePages.echordsURL,
        ))
        let line = try #require(chart.text.components(separatedBy: "\n")
            .first { $0.hasPrefix("Ab ") })
        #expect(line.split(separator: " ").count > 1)
        #expect(chart.fields.album != nil)
        #expect(chart.fields.artistCredit == nil)
    }

    @Test
    func `a page with chords glued into words imports nothing`() throws {
        let html = try FixturePages.text("echords/glued-chords.html")
        let chart = try Self.chart(ChordPreParser.read(html, url: FixturePages.echordsURL))
        #expect(SanityCheck.failures(chart).contains(.gluedChords))
        #expect(PageParserRegistry.read(html, url: FixturePages.echordsURL, loadPath: .webKit)
            == .failure(.noChart(.notFound)))
    }

    // MARK: Generic reader and fallback

    @Test(arguments: [
        "generic/plain-text.html", "generic/pre-page.html", "generic/wordpress.html",
        "generic/indichords.html",
    ])
    func `the generic reader finds the chart`(name: String) throws {
        let html = try FixturePages.text(name)
        let song = try PageParserRegistry.read(html, url: FixturePages.genericURL, loadPath: .plain)
            .get()
        #expect(song.provenance.reader == .genericPage)
        #expect(!song.provenance.fellBack)
        #expect(song.text.components(separatedBy: "\n").count >= 8)
    }

    @Test
    func `a script-only page has no chart`() throws {
        let html = try FixturePages.text("generic/script-app.html")
        #expect(PageParserRegistry.read(html, url: FixturePages.genericURL, loadPath: .plain)
            == .failure(.noChart(.notFound)))
    }

    @Test
    func `a site page the site reader cannot read falls back, flagged`() throws {
        let html = try FixturePages.text("generic/pre-page.html")
        let song = try PageParserRegistry.read(html, url: FixturePages.ugURL, loadPath: .plain)
            .get()
        #expect(song.provenance.reader == .genericPage)
        #expect(song.provenance.fellBack)
    }

    /// A heading and the title and artist it should give ("|" separates the artist; none
    /// when absent).
    @Test(arguments: [
        "Tum Hi Ho Chords by Arijit Singh => Tum Hi Ho|Arijit Singh",
        "Channa Mereya Chords by Arijit Singh @Ae Dil Hai Mushkil => Channa Mereya|Arijit Singh",
        "Tum Hi Ho (Aashiqui 2 | Guitar Chords) => Tum Hi Ho",
        "Channa Mereya Chords- Ae Dil Hai Mushkil => Channa Mereya",
        "Wonderwall Lyrics => Wonderwall",
    ])
    func `heading patterns`(row: String) throws {
        let parts = row.components(separatedBy: " => ")
        let expected = try #require(parts.last).components(separatedBy: "|")
        let fields = try GenericPageReader.heading(#require(parts.first))
        #expect(fields.title == expected.first)
        #expect(fields.artistCredit == (expected.count > 1 ? expected[1] : nil))
    }

    @Test
    func `in Artist - Title headings the address names the title`() {
        let url = web("https://www.example.com/tabs/o/oasis/wonderwall_crd_ver_8.html")
        let fields = GenericPageReader.heading("Oasis - Wonderwall Chords & Tabs", url: url)
        #expect(fields.title == "Wonderwall")
        #expect(fields.artistCredit == "Oasis")
    }

    @Test(arguments: [
        ("C G\nla la", [SanityCheck.Failure.fewLines, .fewLyricLines]),
        ("Am G\nHello there friend\nAm G\nHello again my friend", []),
        ("Xq7 Zz Qq\nHello there friend\nXq7 Zz\nHello again my friend\nmore words here", []),
    ] as [(String, [SanityCheck.Failure])])
    func `sanity checks`(text: String, failures: [SanityCheck.Failure]) {
        let chart = ParsedChart(text: text, fields: SourceFields())
        #expect(SanityCheck.failures(chart) == failures)
    }

    @Test
    func `a film credit splits only under a placeholder artist`() {
        #expect(SourceCredits.titleAndAlbum(
            songName: "Aashiqui 2 - Tum Hi Ho",
            artist: "Misc Soundtrack",
        )
            == ("Tum Hi Ho", "Aashiqui 2"))
        #expect(SourceCredits.titleAndAlbum(
            songName: "Tum Hi Ho - Rehnuma",
            artist: "Shreya Ghoshal",
        )
            == ("Tum Hi Ho - Rehnuma", nil))
        #expect(SourceCredits.credit("Misc Unsigned Bands") == nil)
        #expect(SourceCredits.credit(" Adele ") == "Adele")
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
