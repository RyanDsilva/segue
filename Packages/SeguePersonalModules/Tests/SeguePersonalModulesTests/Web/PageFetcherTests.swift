import Foundation
import Plugins
@testable import SeguePersonalModules
import Testing

/// Spec 8.2 and 15.1: the plain loader over `FixtureTransport` (redirects, size cap, content
/// types, charset, status mapping, challenge pages) and the fetcher's load paths with a fake
/// WebKit loader (once only, E-Chords direct, warm-up, back-off, cache).
struct PageFetcherTests {
    static let page = "https://example.com/song"
    static let pageURL = web(page)

    static func plain(_ responses: [URL: [HTTPResponse]]) -> (PlainPageLoader, FixtureTransport) {
        let transport = FixtureTransport(responses)
        return (PlainPageLoader(transport: transport), transport)
    }

    static func load(_ responses: [String: [HTTPResponse]]) async
        -> Result<LoadedPage, ImportFailure>
    {
        let table = Dictionary(uniqueKeysWithValues: responses.map { (web($0), $1) })
        let (loader, _) = plain(table)
        do {
            return try await .success(loader.load(PageLoadRequest(url: pageURL)))
        } catch {
            return .failure(error)
        }
    }

    @Test
    func `a page loads with its final address`() async throws {
        let page = try await Self.load([Self.page: [Pages.response(Self.page)]]).get()
        #expect(page.loadPath == .plain)
        #expect(page.text.contains("La la"))
    }

    @Test
    func `redirects are followed up to five hops`() async throws {
        var chain: [String: [HTTPResponse]] = [:]
        for hop in 0 ..< 5 {
            let from = hop == 0 ? Self.page : "https://example.com/\(hop)"
            chain[from] = [Pages.response(from, status: 301, headers: ["Location": "/\(hop + 1)"])]
        }
        chain["https://example.com/5"] = [Pages.response("https://example.com/5")]
        let page = try await Self.load(chain).get()
        #expect(page.url.absoluteString == "https://example.com/5")

        chain["https://example.com/5"] = [Pages.response(
            "https://example.com/5", status: 302, headers: ["Location": "/6"],
        )]
        chain["https://example.com/6"] = [Pages.response("https://example.com/6")]
        let tooLong = await Self.load(chain)
        #expect(throws: ImportFailure.notAPage) { try tooLong.get() }
    }

    @Test(arguments: ["http://example.com/song", "https://192.168.1.2/", "file:///etc/passwd"])
    func `a refused redirect stops the load`(location: String) async {
        let result = await Self.load([Self.page: [Pages.response(
            Self.page, status: 302, headers: ["Location": location],
        )]])
        #expect(throws: ImportFailure.notAPage) { try result.get() }
    }

    @Test(arguments: [
        (404, ImportFailure.notFound), (410, .notFound), (401, .blocked), (403, .blocked),
        (429, .busy(retryAfter: .seconds(7))), (503, .busy(retryAfter: .seconds(7))),
        (500, .server(status: 500)), (418, .server(status: 418)),
    ])
    func `statuses map to failures`(status: Int, failure: ImportFailure) async {
        let headers = ["Retry-After": "7", "Content-Type": "text/html"]
        let response = Pages.response(
            Self.page,
            status: status,
            headers: headers,
            body: "<p>no</p>",
        )
        let result = await Self.load([Self.page: [response]])
        #expect(throws: failure) { try result.get() }
    }

    @Test
    func `a challenge page is challenged, even with HTTP 200`() async {
        let result = await Self.load([Self.page: [Pages.response(
            Self.page,
            body: Pages.challengeHTML,
        )]])
        #expect(throws: ImportFailure.challenged) { try result.get() }
    }

    @Test(arguments: ["image/png", "application/pdf", "application/octet-stream"])
    func `other content types are not pages`(type: String) async {
        let result = await Self.load([Self.page: [Pages.response(
            Self.page, headers: ["Content-Type": type],
        )]])
        #expect(throws: ImportFailure.notAPage) { try result.get() }
    }

    @Test
    func `a body over the cap is too large`() async {
        let big = String(repeating: "a", count: URLSessionTransport.bodyCap + 1)
        let result = await Self.load([Self.page: [Pages.response(Self.page, body: big)]])
        #expect(throws: ImportFailure.tooLarge) { try result.get() }
    }

    @Test
    func `charset from the header, then meta, then UTF-8, then Windows-1252`() {
        let cp1252 = Data([0x93, 0x48, 0x69, 0x94]) // "Hi" in curly quotes
        #expect(PlainPageLoader.decode(cp1252, contentType: "text/html; charset=windows-1252")
            == "\u{201C}Hi\u{201D}")
        let meta = Data("<meta charset=\"iso-8859-1\">".utf8) + Data([0xE9])
        #expect(PlainPageLoader.decode(meta, contentType: "text/html").hasSuffix("\u{E9}"))
        #expect(PlainPageLoader.decode(Data("na\u{EF}ve".utf8), contentType: nil) == "na\u{EF}ve")
        #expect(PlainPageLoader.decode(cp1252, contentType: nil) == "\u{201C}Hi\u{201D}")
    }

    // MARK: The fetcher's load paths

    struct Rig {
        var fetcher: PageFetcher
        var pacer: RequestPacer
        var clock: TestWebClock
    }

    static func rig(plain: FakePageLoader, webKit: FakePageLoader) -> Rig {
        let clock = TestWebClock()
        let pacer = RequestPacer(clock: clock, random: { 0 })
        let fetcher = PageFetcher(
            plain: plain, webKit: webKit, pacer: pacer, cache: PageCache(clock: clock),
        )
        return Rig(fetcher: fetcher, pacer: pacer, clock: clock)
    }

    static let loaded = LoadedPage(url: pageURL, text: "<pre>x</pre>", loadPath: .plain)
    static let viaWebKit = LoadedPage(url: pageURL, text: "<pre>x</pre>", loadPath: .webKit)

    @Test(arguments: [ImportFailure.challenged, .blocked])
    func `a challenge or 403 goes once to the WebKit loader`(failure: ImportFailure) async throws {
        let plain = FakePageLoader([.failure(failure)])
        let webKit = FakePageLoader([.success(Self.viaWebKit)])
        let rig = Self.rig(plain: plain, webKit: webKit)
        let fetcher = rig.fetcher
        let page = try await fetcher.fetch(PageLoadRequest(url: Self.pageURL), route: .plainFirst)
        #expect(page.loadPath == .webKit)
        #expect(plain.requests.count == 1)
        #expect(webKit.requests.count == 1)
    }

    @Test
    func `a page still challenged after WebKit is challenged, with no back-off`() async throws {
        let plain = FakePageLoader([.failure(.challenged)])
        let webKit = FakePageLoader([.failure(.challenged)])
        let rig = Self.rig(plain: plain, webKit: webKit)
        let fetcher = rig.fetcher
        let pacer = rig.pacer
        let request = PageLoadRequest(url: Self.pageURL, backsOff: true)
        await #expect(throws: ImportFailure.challenged) {
            try await fetcher.fetch(request, route: .plainFirst)
        }
        #expect(webKit.requests.count == 1)
        #expect(await pacer.backOffEnd(for: "example.com") == nil)
    }

    @Test
    func `a hard block on the last path starts the site back-off`() async throws {
        let plain = FakePageLoader([.failure(.blocked)])
        let webKit = FakePageLoader([.failure(.blocked)])
        let rig = Self.rig(plain: plain, webKit: webKit)
        let fetcher = rig.fetcher
        let pacer = rig.pacer
        let request = PageLoadRequest(url: Self.pageURL, backsOff: true)
        await #expect(throws: ImportFailure.blocked) {
            try await fetcher.fetch(request, route: .plainFirst)
        }
        #expect(await pacer.backOffEnd(for: "example.com") != nil)
        await #expect(throws: ImportFailure.backingOff(retryAfter: .seconds(3600))) {
            try await fetcher.fetch(request, route: .plainFirst)
        }
        #expect(plain.requests.count == 1)
    }

    @Test
    func `a block that WebKit gets past starts no back-off`() async throws {
        let rig = Self.rig(
            plain: FakePageLoader([.failure(.blocked)]),
            webKit: FakePageLoader([.success(Self.viaWebKit)]),
        )
        let fetcher = rig.fetcher
        let pacer = rig.pacer
        _ = try await fetcher.fetch(
            PageLoadRequest(url: Self.pageURL, backsOff: true),
            route: .plainFirst,
        )
        #expect(await pacer.backOffEnd(for: "example.com") == nil)
    }

    @Test
    func `a site that blocks plain requests goes straight to WebKit`() async throws {
        let plain = FakePageLoader([.success(Self.loaded)])
        let webKit = FakePageLoader([.success(Self.viaWebKit)])
        let rig = Self.rig(plain: plain, webKit: webKit)
        let fetcher = rig.fetcher
        let page = try await fetcher.fetch(PageLoadRequest(url: Self.pageURL), route: .webKitOnly)
        #expect(page.loadPath == .webKit)
        #expect(plain.requests.isEmpty)
    }

    @Test
    func `a cold store loads the home page once first`() async throws {
        let webKit = FakePageLoader([.success(Self.viaWebKit)], cold: true)
        let rig = Self.rig(plain: FakePageLoader([]), webKit: webKit)
        let fetcher = rig.fetcher
        let clock = rig.clock
        let page = try await fetcher.fetch(PageLoadRequest(url: Self.pageURL), route: .webKitOnly)
        #expect(page.warmUp)
        #expect(webKit.requests.map(\.url.absoluteString) == ["https://example.com/", Self.page])
        #expect(clock.sleeps == [.seconds(2)])
    }

    @Test
    func `a fetched page is cached for ten minutes`() async throws {
        let plain = FakePageLoader([.success(Self.loaded)])
        let rig = Self.rig(plain: plain, webKit: FakePageLoader([]))
        let fetcher = rig.fetcher
        let clock = rig.clock
        let request = PageLoadRequest(url: Self.pageURL)
        _ = try await fetcher.fetch(request, route: .plainFirst)
        _ = try await fetcher.fetch(request, route: .plainFirst)
        #expect(plain.requests.count == 1)
        clock.advance(.seconds(601))
        _ = try await fetcher.fetch(request, route: .plainFirst)
        #expect(plain.requests.count == 2)
    }

    @Test
    func `an address the import refuses sends nothing`() async throws {
        let plain = FakePageLoader([.success(Self.loaded)])
        let rig = Self.rig(plain: plain, webKit: FakePageLoader([]))
        let fetcher = rig.fetcher
        await #expect(throws: ImportFailure.notAPage) {
            try await fetcher.fetch(
                PageLoadRequest(url: #require(URL(string: "http://localhost/x"))),
                route: .plainFirst,
            )
        }
        #expect(plain.requests.isEmpty)
    }

    @Test
    func `the cache keeps the last twenty`() {
        let cache = PageCache<Int, Int>(clock: TestWebClock())
        for index in 0 ..< 25 {
            cache.store(index, for: index)
        }
        #expect(cache.count == 20)
        #expect(cache.value(for: 4) == nil)
        #expect(cache.value(for: 24) == 24)
    }

    @Test
    func `no test source constructs the real transport`() throws {
        let tests = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let files = FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)
        let needle = "URLSession" + "Transport(user"
        for file in files {
            #expect(
                try !String(contentsOf: file, encoding: .utf8).contains(needle),
                "\(file.lastPathComponent)",
            )
        }
    }
}
