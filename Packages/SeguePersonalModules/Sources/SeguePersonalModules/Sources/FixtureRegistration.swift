import Foundation
import Plugins

/// Saved responses for the E2E launch (spec 15.4): the app passes these only in Debug, with
/// its `-SegueImportFixtures` option, so a UI test drives the real readers, pacer, sources
/// and sheets without any network.
public struct ImportFixtures: Sendable {
    public struct Page: Sendable {
        public var status: Int
        public var contentType: String
        public var body: String

        public init(status: Int = 200, contentType: String = "text/html", body: String) {
            self.status = status
            self.contentType = contentType
            self.body = body
        }
    }

    /// Address prefix to page; the longest matching prefix answers, anything else is a 404.
    public var pages: [String: Page]
    /// Address prefixes the hidden page loader answers as still asking for a person.
    public var challenged: [String]

    public init(pages: [String: Page], challenged: [String] = []) {
        self.pages = pages
        self.challenged = challenged
    }

    func page(for url: URL) -> Page? {
        let address = url.absoluteString
        return pages.filter { address.hasPrefix($0.key) }.max { $0.key.count < $1.key.count }?
            .value
    }
}

public extension PersonalModules {
    /// `register(into:)` over `fixtures` instead of the network and the hidden view.
    static func register(into registry: PluginRegistry, fixtures: ImportFixtures) {
        let services = WebImportServices(
            transport: PrefixFixtureTransport(fixtures: fixtures),
            webKit: FixturePageLoader(fixtures: fixtures),
            userAgent: userAgent,
        )
        registry.register(WebPageImporter(services: services))
        registry.register(UGSearchSource(services: services))
        registry.register(EChordsSearchSource(services: services))
        registry.register(LyricsSearchSource(services: services))
    }
}

/// Serves `ImportFixtures` pages by address prefix.
struct PrefixFixtureTransport: HTTPTransport {
    let fixtures: ImportFixtures

    func send(_ request: HTTPRequest) async throws(ImportFailure) -> HTTPResponse {
        if Task.isCancelled {
            throw .cancelled
        }
        guard let page = fixtures.page(for: request.url) else {
            return HTTPResponse(url: request.url, status: 404)
        }
        return HTTPResponse(
            url: request.url,
            status: page.status,
            headers: ["Content-Type": page.contentType + "; charset=utf-8"],
            body: Data(page.body.utf8),
        )
    }
}

/// The hidden loader's stand-in: challenged prefixes stay challenged; other pages load.
struct FixturePageLoader: PageLoader {
    let fixtures: ImportFixtures

    func load(_ request: PageLoadRequest) async throws(ImportFailure) -> LoadedPage {
        let address = request.url.absoluteString
        if fixtures.challenged.contains(where: { address.hasPrefix($0) }) {
            throw .challenged
        }
        guard let page = fixtures.page(for: request.url) else { throw .notFound }
        return LoadedPage(url: request.url, text: page.body, loadPath: .webKit)
    }
}
