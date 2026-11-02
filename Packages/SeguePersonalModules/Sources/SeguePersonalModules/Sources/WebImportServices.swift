import Foundation
import Plugins

/// The shared plumbing of the Personal build's web import and search (spec 4.1): one
/// transport, one pacer, one page fetcher and one lyrics client for the whole launch, so the
/// per-host pacing and back-off hold across every source.
final class WebImportServices: Sendable {
    let pacer: RequestPacer
    let fetcher: PageFetcher
    let lyrics: LRCLIBClient
    let lyricsCache: PageCache<String, [LyricsRecord]>

    init(
        transport: any HTTPTransport,
        webKit: any PageLoader,
        userAgent: String,
        clock: any WebClock = SystemWebClock(),
    ) {
        let pacer = RequestPacer(clock: clock)
        self.pacer = pacer
        fetcher = PageFetcher(
            plain: PlainPageLoader(transport: transport),
            webKit: webKit,
            pacer: pacer,
            cache: PageCache(clock: clock),
        )
        lyrics = LRCLIBClient(transport: transport, pacer: pacer, userAgent: userAgent)
        lyricsCache = PageCache(capacity: 50, clock: clock)
    }

    /// The shipping set: the real network and the hidden WebKit view.
    static func live(userAgent: String) -> WebImportServices {
        WebImportServices(
            transport: URLSessionTransport(userAgent: userAgent),
            webKit: WebKitPageLoader(),
            userAgent: userAgent,
        )
    }

    /// Reads one page and its chart, by the registry's rules (spec 8.3).
    func importPage(_ url: URL) async throws(ImportFailure) -> ImportedSong {
        guard let address = WebAddress.validated(url) else { throw .notAPage }
        let request = PageLoadRequest(
            url: address,
            marker: PageParserRegistry.marker(for: address),
            backsOff: PageParserRegistry.reader(for: address) != .genericPage,
        )
        let route: PageFetcher.Route = PageParserRegistry
            .loadsThroughWebKit(address) ? .webKitOnly : .plainFirst
        let page = try await fetcher.fetch(request, route: route)
        return try PageParserRegistry.read(page.text, url: address, loadPath: page.loadPath).get()
    }
}

/// `SongImporter` for page addresses and saved page files (spec 8.1).
struct WebPageImporter: SongImporter {
    let id = "dev.ryandsilva.segue.web-page"
    let displayName = "Web Page"
    var services: WebImportServices

    func accepts(_ input: ImportInput) -> ReaderKind? {
        switch input {
        case let .url(url):
            WebAddress.validated(url).map(PageParserRegistry.reader(for:))
        case let .webPageFile(file):
            ["html", "htm", "webarchive"]
                .contains(file.pathExtension.lowercased()) ? .genericPage : nil
        }
    }

    func importSong(_ input: ImportInput) async throws(ImportFailure) -> ImportedSong {
        switch input {
        case let .url(url):
            return try await services.importPage(url)
        case let .webPageFile(file):
            let (html, address) = try SavedPage.read(file)
            var song = try PageParserRegistry.read(html, url: address, loadPath: .savedFile).get()
            song.provenance.loadPath = .savedFile
            return song
        }
    }
}

/// A page saved from Safari: `.html`/`.htm` as text, `.webarchive` from its main resource.
/// The page's own address (the webarchive's, else its canonical link) picks the reader.
enum SavedPage {
    static func read(_ file: URL) throws(ImportFailure) -> (html: String, address: URL) {
        guard let data = try? Data(contentsOf: file) else { throw .notFound }
        guard data.count <= URLSessionTransport.bodyCap else { throw .tooLarge }
        if file.pathExtension.lowercased() == "webarchive" {
            guard let plist = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil,
            ) as? [String: Any],
                let main = plist["WebMainResource"] as? [String: Any],
                let body = main["WebResourceData"] as? Data
            else { throw .notAPage }
            let html = PlainPageLoader.decode(
                body,
                contentType: (main["WebResourceTextEncodingName"] as? String)
                    .map { "charset=" + $0 },
            )
            let address = (main["WebResourceURL"] as? String)
                .flatMap(URL.init(string:)) ?? canonical(html) ?? file
            return (html, address)
        }
        let html = PlainPageLoader.decode(data, contentType: nil)
        return (html, canonical(html) ?? file)
    }

    static func canonical(_ html: String) -> URL? {
        let link = html.firstMatch(of: /<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']/)
            ?? html.firstMatch(of: /<meta[^>]+property=["']og:url["'][^>]+content=["']([^"']+)["']/)
        return link.flatMap { URL(string: String($0.output.1)) }.flatMap(WebAddress.validated)
    }
}
