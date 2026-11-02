import Foundation
import Plugins
@testable import SeguePersonalModules
@testable import SegueUI
import Services
import Testing

/// Spec 6.4-6.11, 8.7 and 11.3: the web field's and Find Lyrics' models over stand-in
/// sources and a fixture transport (no network), and the failure copy table.
/// One row of the failure copy table.
struct CopyRow: Sendable, CustomTestStringConvertible {
    let failure: ImportFailure
    let text: String
    let actions: [ImportCopy.Action]

    init(_ failure: ImportFailure, _ text: String, _ actions: [ImportCopy.Action]) {
        self.failure = failure
        self.text = text
        self.actions = actions
    }

    var testDescription: String {
        text
    }
}

@MainActor
struct ImportUITests {
    // MARK: Copy (spec 6.8, 8.7)

    @Test(arguments: [
        CopyRow(
            .challenged,
            "e-chords.com wants to check you're a person.",
            [.openHere, .openInBrowser, .importSavedPage, .pasteInstead],
        ),
        CopyRow(
            .blocked,
            "e-chords.com doesn't let apps read this page.",
            [.openInBrowser, .importSavedPage, .pasteInstead],
        ),
        CopyRow(.notFound, "That page doesn't exist anymore.", [.openInBrowser]),
        CopyRow(.tooLarge, "That address isn't a web page Segue can read.", []),
        CopyRow(
            .noChart(.tab),
            "This page is a tab, not a chord chart.",
            [.openInBrowser, .pasteInstead],
        ),
        CopyRow(
            .offline,
            "You're offline. Importing a web page needs the internet.",
            [.tryAgain],
        ),
        CopyRow(
            .server(status: 502),
            "e-chords.com isn't answering right now.",
            [.tryAgain, .openInBrowser],
        ),
    ])
    func `each page failure has its message and actions`(row: CopyRow) {
        let (failure, text, actions) = (row.failure, row.text, row.actions)
        let message = ImportCopy.page(failure, host: "e-chords.com", now: Date())
        #expect(message.text == text)
        #expect(message.actions == actions)
    }

    @Test
    func `busy and back-off keep the action off until their time`() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let busy = ImportCopy.search(.busy(retryAfter: .seconds(4)), source: "LRCLIB", now: now)
        #expect(busy.text == "LRCLIB is busy. Try again in 4 seconds.")
        #expect(busy.retryAt == now.addingTimeInterval(4))
        let waiting = ImportCopy.search(
            .backingOff(retryAfter: .seconds(3600)), source: "E-Chords", now: now,
        )
        #expect(waiting.text.hasPrefix("E-Chords asked Segue to wait. Try again after "))
        #expect(waiting.actions == [.searchInBrowser])
        #expect(ImportCopy.outcome(.challenged) == .challenged)
        #expect(ImportCopy.outcome(.noChart(.pro)) == .noChart)
    }

    // MARK: Find Lyrics

    @Test
    func `one search fills the groups in their fixed order, versions nested, best selected`()
        async
    {
        let stub = StubHost(search: true)
        let model = FindLyricsModel(
            sources: ImportSamples.sources(),
            challenges: nil,
            previewDelay: .zero,
        )
        model.attach(stub.host)
        model.query = "tum hi ho"
        model.search()
        await model.settle()

        #expect(model.groups.map(\.id) == [.tabJSON, .chordPre, .lyricsRecord])
        let tab = model.groups[0]
        #expect(tab.songs.map(\.versions.count) == [4, 1])
        #expect(model.expanded.contains(tab.songs[0].id))
        let best = model.key(.tabJSON, ImportSamples.tabVersions[0])
        #expect(model.selection == .version(best))
        if case let .failed(failure, message) = model.groups[1].status {
            #expect(failure == .challenged)
            #expect(message.actions == [.openHere, .searchInBrowser])
        } else {
            Issue.record("the challenged group shows its status")
        }
        #expect(model.groups[2].songs.first?.best.romanized == true)

        // Rows run through the groups; Left collapses the selected song's versions.
        #expect(model.rows.count == 7)
        model.setExpanded(false)
        #expect(model.selection == .song(tab.songs[0].id))
        #expect(model.rows.count == 3)

        let searched = stub.events.compactMap { event -> SongSearchedSummary? in
            if case let .importSearched(summary) = event {
                summary
            } else {
                nil
            }
        }
        #expect(searched.count == 1)
        #expect(searched.first?.groupsFailed == .one)
        #expect(searched.first?.outcome == .results)
    }

    @Test
    func `picking the previewed version moves the sheet to review and records the pick`() async {
        let stub = StubHost(search: true)
        let model = FindLyricsModel(
            sources: ImportSamples.sources(),
            challenges: nil,
            previewDelay: .zero,
        )
        model.attach(stub.host)
        model.query = "tum hi ho"
        model.search()
        await model.settle()
        await model.settlePreview()
        guard case let .loaded(_, song, chordPro) = model.preview else {
            Issue.record("the best version previews")
            return
        }
        #expect(song.provenance.attribution == "From Ultimate Guitar · ver 2 · ★4.8")
        #expect(chordPro.contains("{title: Tum Hi Ho}"))
        #expect(chordPro.contains("{album: Aashiqui 2}"))

        model.pick()
        for _ in 0 ..< 200 where stub.review.phase != .review {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(stub.review.phase == .review)
        #expect(stub.review.selected?.source == .songSearch)
        let picks = stub.events.compactMap { event -> SearchPickedSummary? in
            if case let .importSearchPicked(summary) = event {
                summary
            } else {
                nil
            }
        }
        #expect(picks.first?.group == .tabJSON)
        #expect(picks.first?.rank == .one)
        #expect(picks.first?.versionRank == .one)
    }

    @Test
    func `a chord group answering after the lyrics still takes the selection`() async {
        let stub = StubHost(search: true)
        var sources = ImportSamples.sources()
        sources[0] = StubSearchSource(
            id: "tab",
            displayName: "Ultimate Guitar",
            group: .tabJSON,
            result: .success(ImportSamples.tabVersions),
            delay: .milliseconds(80),
        )
        let model = FindLyricsModel(sources: sources, challenges: nil, previewDelay: .zero)
        model.attach(stub.host)
        model.query = "tum hi ho"
        model.search()
        await model.settle()
        let best = model.key(.tabJSON, ImportSamples.tabVersions[0])
        #expect(model.selection == .version(best))

        // Once the user moved, a later answer leaves the selection alone.
        let lyrics = model.groups[2].songs[0].id
        model.selection = .song(lyrics)
        model.search()
        model.selection = .song(lyrics)
        await model.settle()
        #expect(model.selection == .song(lyrics))
    }

    @Test
    func `escape cancels a running search first, then closes`() {
        let stub = StubHost(search: true)
        var slow = ImportSamples.sources()
        slow[2] = StubSearchSource.slowLyrics
        let model = FindLyricsModel(sources: slow, challenges: nil, previewDelay: .zero)
        model.attach(stub.host)
        model.query = "tum hi ho"
        model.search()
        #expect(model.isRunning)
        model.escape()
        #expect(!model.isRunning)
        #expect(!stub.cancelled)
        model.escape()
        #expect(stub.cancelled)
    }

    // MARK: The web field

    @Test
    func `a challenged page shows Open Here and the fallbacks, and records the read`() async {
        let transport = FixtureTransport([
            FixturePages.echordsURL: Pages.response(FixturePages.echordsURL.absoluteString),
        ])
        let services = WebImportServices(
            transport: transport,
            webKit: FakePageLoader([.failure(.challenged)]),
            userAgent: "Segue/test",
            clock: TestWebClock(),
        )
        let stub = StubHost()
        let model = WebImportModel(importer: WebPageImporter(services: services))
        model.attach(stub.host)
        model.address = FixturePages.echordsURL.absoluteString
        model.importAddress()
        for _ in 0 ..< 200 where model.isReading {
            try? await Task.sleep(for: .milliseconds(5))
        }
        guard case let .failed(message) = model.state else {
            Issue.record("the failure shows under the field")
            return
        }
        #expect(message.text == "e-chords.com wants to check you're a person.")
        #expect(message.actions.first == .openHere)
        #expect(!stub.review.isReadingWeb)
        let read = stub.events.compactMap { event -> PageReadSummary? in
            if case let .importPageRead(summary) = event {
                summary
            } else {
                nil
            }
        }
        #expect(read.first?.outcome == .challenged)
        #expect(read.first?.reader == .chordPre)
        #expect(read.first?.webKitBlocked == true)

        await model.perform(.pasteInstead) { nil }
        #expect(stub.review.showsPasteHint)
    }

    @Test
    func `a pending address is read at once and a read page opens the review`() async throws {
        let page = Pages.html("<pre>\(ImportSamples.chart)</pre>", title: "Tum Hi Ho Chords")
        let url = FixturePages.genericURL
        let services = WebImportServices(
            transport: FixtureTransport([url: Pages.response(url.absoluteString, body: page)]),
            webKit: FakePageLoader([.failure(.notFound)]),
            userAgent: "Segue/test",
            clock: TestWebClock(),
        )
        let stub = StubHost()
        stub.review.receive(.address(url, .droppedLink))
        let model = WebImportModel(importer: WebPageImporter(services: services))
        model.attach(stub.host)
        model.readPending()
        #expect(model.address == url.absoluteString)
        for _ in 0 ..< 400 where stub.review.phase != .review {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let item = try #require(stub.review.selected)
        #expect(item.source == .webPage)
        #expect(item.provenance?.reader == .genericPage)
        let read = stub.events.compactMap { event -> PageReadSummary? in
            if case let .importPageRead(summary) = event {
                summary
            } else {
                nil
            }
        }
        #expect(read.first?.entry == .droppedLink)
        #expect(read.first?.outcome == .reviewed)
    }
}
