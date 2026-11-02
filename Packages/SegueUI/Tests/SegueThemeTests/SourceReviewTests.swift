import Foundation
import Ingest
import Library
import Plugins
@testable import SegueUI
import Services
import SwiftUI
import Testing

/// P9-4 spec 15.3: the Personal build's web import and Find Lyrics routes into the review
/// sheet, on a real temp library and the real converter. The plugin views are stand-ins: only
/// whether an entry exists matters to SegueUI.
@MainActor
struct SourceReviewTests {
    static let page = """
    [Intro]
    Am  F  C  G

    [Verse 1]
    Am              F
    Lanterns on the water tonight
    C                  G
    Every boat is coming home
    """

    static let tumHiHo = ImportedSong(
        text: page,
        fields: SourceFields(title: "Tum Hi Ho", artistCredit: "Arijit Singh", album: "Aashiqui 2"),
        provenance: Provenance(
            sourceURL: URL(string: "https://example.com/tab/tum-hi-ho")!,
            reader: .genericPage,
            fellBack: true,
        ),
    )

    static var entries: PluginEntries {
        PluginEntries(
            webImport: WebImportEntry(
                field: { _ in AnyView(EmptyView()) },
                fileExtensions: ["html", "htm", "webarchive"],
            ),
            songSearch: SongSearchEntry(sheet: { _ in AnyView(EmptyView()) }),
        )
    }

    @Test
    func `a source song opens one review item whose source fields win, and Accept is web`()
        async throws
    {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let recording = RecordingLog(url: env.scratch.appending(path: "services.jsonl"))
        library.services = ServicesHub(
            factory: RecordingServicesFactory(log: recording),
            consent: ConsentState(analytics: .granted(.now), crashReports: .declined(.now)),
            throttle: AnalyticsThrottle(suiteName: env.suiteName, clock: env.clock),
        )
        library.plugins = Self.entries
        library.beginSongSearch()
        let review = try #require(library.pasteReview)
        #expect(review.phase == .search)

        review.submitSource(Self.tumHiHo, source: .songSearch)
        #expect(review.phase == .review)
        let item = try #require(review.selected)
        #expect(item.source == .songSearch)
        #expect(item.provenance?.fellBack == true)
        #expect(item.text.contains("{title: Tum Hi Ho}"))
        #expect(item.text.contains("{artist: Arijit Singh}"))
        #expect(item.text.contains("{album: Aashiqui 2}"))

        await review.awaitRefinement()
        await library.acceptPasteReview()
        #expect(env.exists("songs/tum-hi-ho.cho"))
        let created = try #require(recording.entries().first {
            $0["name"] as? String == "Segue.Song.created"
        })
        #expect((created["params"] as? [String: String])?["segue.source"] == "web")
        let finished = try #require(recording.entries().first {
            $0["name"] as? String == "Segue.AI.pasteFinished"
        })
        #expect((finished["params"] as? [String: String])?["segue.source"] == "songSearch")
    }

    @Test(arguments: [
        ("https://tabs.example.com/tab/123", true),
        ("  http://example.com/a?b=c \n", true),
        ("https://example.com/a and more words", false),
        ("Tum Hi Ho\nhttps://example.com/x", false),
        ("ftp://example.com/x", false),
        ("https://localhost/x", false),
        ("example.com/x", false),
    ])
    func `only a lone http(s) address is a page address`(text: String, isAddress: Bool) {
        #expect((LoneWebAddress.url(in: text) != nil) == isAddress)
    }

    @Test
    func `a lone pasted address opens the web field, only when the entry exists`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let address = "https://example.com/tab/tum-hi-ho"

        // App Store composition: no entry, so the address is converted as text, as today.
        library.beginPasteReview(text: address, source: .clipboard)
        #expect(library.pasteReview?.phase == .review)
        #expect(library.pasteReview?.pendingWebInput == nil)
        await library.cancelPasteReview()

        library.plugins = Self.entries
        library.beginPasteReview(text: address, source: .listPaste)
        let review = try #require(library.pasteReview)
        #expect(review.phase == .input)
        #expect(review.focusesWebField)
        let url = try #require(URL(string: address))
        #expect(review.takePendingWebInput() == .address(url, .pastedURL))
        #expect(review.pendingWebInput == nil)

        // Pasted into the New Song text area: the same rule.
        review.draftText = address
        review.submitDraft()
        #expect(review.phase == .input)
        #expect(review.draftText.isEmpty)
        #expect(review.takePendingWebInput() == .address(url, .pastedURL))
        await library.cancelPasteReview()
    }

    @Test
    func `a saved page file goes to the web field; nothing opens during a show`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.plugins = Self.entries
        let file = env.scratch.appending(path: "page.webarchive")
        await library.importWithReview([file])
        #expect(library.pasteReview?.takePendingWebInput() == .file(file))
        await library.cancelPasteReview()

        library.isPerforming = true
        library.beginWebImport()
        library.beginSongSearch()
        library.beginPasteReview(text: "https://example.com/x", source: .clipboard)
        #expect(library.pasteReview == nil)
    }

    @Test
    func `with no entries the web and search routes do nothing`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.beginWebImport()
        #expect(library.pasteReview == nil)
        library.beginSongSearch()
        #expect(library.pasteReview == nil)
        #expect(MenuShortcuts.all(includesPersonal: false) == MenuShortcuts.all)
    }

    @Test
    func `paste the page instead returns to the input state with the hint`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.plugins = Self.entries
        library.beginSongSearch()
        let review = try #require(library.pasteReview)
        review.showPasteInstead()
        #expect(review.phase == .input)
        #expect(review.showsPasteHint)
        await library.cancelPasteReview()
    }

    @Test
    func `the source line names the host, the fallback, the romanizing and the title flag`() {
        var provenance = Self.tumHiHo.provenance
        provenance.sourceURL = URL(string: "https://www.example.com/x")!
        provenance.romanized = true
        let line = ReviewSourceLine.Content(provenance, titleUncertain: true)
        #expect(line.source == "From example.com")
        #expect(line.text == "From example.com - read with the general page reader - "
            + "converted from Devanagari - check where the title and Movie / Album split")
        provenance.attribution = "Lyrics from a test source"
        provenance.fellBack = false
        provenance.romanized = false
        #expect(ReviewSourceLine.Content(provenance, titleUncertain: false).text
            == "Lyrics from a test source")
    }

    @Test
    func `the Personal shortcuts follow Import Songs and clash with nothing`() throws {
        let all = MenuShortcuts.all(includesPersonal: true)
        let index = try #require(all.firstIndex(of: MenuShortcuts.importSongs))
        #expect(all[index + 1].displayText == "⇧⌘U")
        #expect(all[index + 2].displayText == "⇧⌘L")
        let shared = Set(MenuShortcuts.sharedChords.map(\.0.id))
        let chords = all.filter { !shared.contains($0.id) }.map(\.chord)
        #expect(Set(chords).count == chords.count)
    }
}
