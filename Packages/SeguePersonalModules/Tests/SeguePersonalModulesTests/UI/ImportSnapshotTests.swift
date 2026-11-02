import AppKit
import ImageIO
import Plugins
@testable import SeguePersonalModules
@testable import SegueUI
import SwiftUI
import Testing
import UniformTypeIdentifiers
import WebKit

/// The P9-4c sheets at their real sizes, dark and light, written to
/// `.build/screenshots/p9-4c` for review: Find Lyrics (results and failures), the New Song
/// sheet's web field (challenged and reading), the review header's source line, Open Here
/// and Settings' Clear Site Data. Stand-in sources, no network.
@MainActor
@Suite(.serialized)
struct ImportSnapshotTests {
    static var directory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".build/screenshots/p9-4c", directoryHint: .isDirectory)
    }

    @Test
    func `find lyrics with results, a challenged group and a romanized record`() async throws {
        let stub = StubHost(search: true)
        let model = FindLyricsModel(
            sources: ImportSamples.sources(),
            challenges: nil,
            previewDelay: .zero,
        )
        model.attach(stub.host)
        model.query = "tum hi ho arijit"
        model.search()
        await model.settle()
        model.noteVariants(["tum hi ho arijit singh"])
        await model.settlePreview()
        try await render("find-lyrics", 960, 600) {
            FindLyricsSheet(model: model, host: stub.host)
        }
    }

    @Test
    func `find lyrics with a back-off, a block and the lyrics source retrying`() async throws {
        try await render("find-lyrics-failures", 960, 600) {
            let stub = StubHost(search: true)
            var sources = ImportSamples.sources(
                tab: .failure(.backingOff(retryAfter: .seconds(2400))),
                pre: .failure(.blocked),
            )
            sources[2] = StubSearchSource.slowLyrics
            let model = FindLyricsModel(sources: sources, challenges: nil, previewDelay: .zero)
            model.attach(stub.host)
            model.query = "kesariya"
            model.search()
            for _ in 0 ..< 100 where model.groups[0].status == .searching {
                try await Task.sleep(for: .milliseconds(5))
            }
            model.noteRetry(2)
            return FindLyricsSheet(model: model, host: stub.host)
        }
    }

    @Test
    func `the new song sheet with the web field`() async throws {
        let stub = StubHost()
        let services = WebImportServices(
            transport: FixtureTransport([URL: HTTPResponse]()),
            webKit: FakePageLoader([.failure(.challenged)]),
            userAgent: "Segue/test",
            clock: TestWebClock(),
        )
        let field = WebImportModel(importer: WebPageImporter(services: services))
        field.address = "https://tabs.ultimate-guitar.com/tab/misc-soundtrack/aashiqui-2-tum-hi-ho-chords-1234996"
        field.state = .failed(ImportCopy.page(.challenged, host: "ultimate-guitar.com", now: .now))
        try await render("new-song-web", 640, 520) { newSong(stub, field) }
    }

    @Test
    func `the new song sheet reading a page`() async throws {
        try await render("new-song-reading", 640, 520) {
            let stub = StubHost()
            let services = WebImportServices(
                transport: FixtureTransport([URL: HTTPResponse]()),
                webKit: FakePageLoader([.failure(.challenged)]),
                userAgent: "Segue/test",
                clock: TestWebClock(),
            )
            let field = WebImportModel(importer: WebPageImporter(services: services))
            field.address = "https://chords.example.com/tum-hi-ho"
            field.state = .reading
            stub.review.isReadingWeb = true
            return newSong(stub, field)
        }
    }

    @Test
    func `the review header's source line, with the film title flagged`() async throws {
        let stub = StubHost()
        var song = ImportSamples.tabSong
        song.fields.titleUncertain = true
        stub.review.submitSource(song, source: .songSearch)
        let context = PasteReviewContext(
            aiEnabled: false,
            availability: [:],
            knownArtists: [],
            knownTags: [],
            accept: {},
            cancel: {},
            startBlank: {},
            openAISettings: {},
            openSystemSettings: {},
        )
        try await render("review-source-line", 1080, 700) {
            PasteReviewSheet(review: stub.review, context: context)
        }
    }

    @Test
    func `open here shows the page as it is`() async throws {
        let source = StaticChallengeSource()
        let url = web("https://www.e-chords.com/chords/arijit-singh/tum-hi-ho")
        try await render("open-here", 900, 680, web: source) {
            OpenHereSheet(url: url, source: source) { _ in }
        }
    }

    @Test
    func `settings clear site data`() async throws {
        let view = Form {
            Section("Web import") {
                SiteDataSettings(clear: {})
            }
        }
        .formStyle(.grouped)
        try await render("settings-site-data", 560, 200) { view }
    }

    // MARK: Rendering

    private func newSong(_ stub: StubHost, _ field: WebImportModel) -> some View {
        var context = PasteReviewContext(
            aiEnabled: false,
            availability: [:],
            knownArtists: [],
            knownTags: [],
            accept: {},
            cancel: {},
            startBlank: {},
            openAISettings: {},
            openSystemSettings: {},
        )
        context.plugins = PluginEntries(webImport: WebImportEntry(
            field: { host in AnyView(WebImportField(model: field, host: host)) },
            fileExtensions: SavedPagePanel.extensions,
        ))
        context.host = { _ in stub.host }
        return PasteReviewSheet(review: stub.review, context: context)
    }

    private func render(
        _ name: String,
        _ width: CGFloat,
        _ height: CGFloat,
        web: StaticChallengeSource? = nil,
        _ make: @MainActor () async throws -> some View,
    ) async throws {
        #expect(Theme.registerFonts())
        for dark in [false, true] {
            let view = try await make()
            let host = NSHostingView(rootView: view.frame(width: width, height: height))
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(
                contentRect: host.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
            )
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            window.orderFront(nil)
            for _ in 0 ..< 30 {
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            if let web {
                await web.loaded()
            }
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            if let web, let page = web.view, let snapshot = try? await page.takeSnapshot(
                configuration: nil,
            ) {
                // WebKit draws out of process: its snapshot goes where the view sits.
                let frame = page.convert(page.bounds, to: host)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                snapshot.draw(in: frame)
                NSGraphicsContext.restoreGraphicsState()
            }
            window.orderOut(nil)
            let image = try #require(rep.cgImage)
            try Self.write(image, "\(name)-\(dark ? "dark" : "light").png")
        }
    }

    static func write(_ image: CGImage, _ file: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: file)
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil,
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

/// A challenge view showing a local page shaped like a human check (no network).
@MainActor
final class StaticChallengeSource: ChallengeViewSource {
    private(set) var view: WKWebView?
    private var navigation: Task<Void, Never>?

    func presentChallenge(for _: URL) async -> WKWebView {
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
        view.loadHTMLString(Self.page, baseURL: nil)
        self.view = view
        return view
    }

    func waitUntilCleared() async -> Bool {
        false
    }

    func endPresentation() {}

    func loaded() async {
        for _ in 0 ..< 100 where view?.isLoading ?? true {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try? await Task.sleep(for: .milliseconds(200))
    }

    static let page = """
    <!doctype html><html><head><style>
    body { font: 15px -apple-system; color: #222; background: #fff; display: flex;
      flex-direction: column; align-items: center; justify-content: center; height: 90vh; }
    h1 { font-size: 24px; margin: 0 0 12px; }
    .box { border: 1px solid #ddd; border-radius: 4px; padding: 14px 18px; width: 260px;
      display: flex; align-items: center; gap: 12px; background: #fafafa; }
    .tick { width: 22px; height: 22px; border: 2px solid #999; border-radius: 4px; }
    small { color: #888; margin-left: auto; font-size: 10px; letter-spacing: .05em; }
    </style></head><body>
    <h1>www.e-chords.com</h1>
    <p>Verify you are human by completing the action below.</p>
    <div class="box"><div class="tick"></div><span>Verify you are human</span>
    <small>CHECK</small></div>
    </body></html>
    """
}
