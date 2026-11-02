import Foundation
import Plugins

/// What a reader waits for before it reads a page in the hidden view (spec 8.6).
enum ReadyMarker: String, Sendable, Hashable {
    /// UG's `window.UGAPP.store` or its `js-store` element.
    case tabStore
    /// E-Chords' chart `<pre>`.
    case chordPre
    /// Any other page: document ready plus 1 s.
    case document
}

/// One page to load.
struct PageLoadRequest: Sendable, Hashable {
    var url: URL
    var marker: ReadyMarker
    /// A same-origin path fetched from inside the loaded page instead of the page itself
    /// (E-Chords' `/api/search`, spec 6.11). The plain loader requests it directly.
    var inPageFetch: String?
    /// A chord site: a hard block starts its one-hour back-off (spec 9).
    var backsOff: Bool

    init(
        url: URL,
        marker: ReadyMarker = .document,
        inPageFetch: String? = nil,
        backsOff: Bool = false,
    ) {
        self.url = url
        self.marker = marker
        self.inPageFetch = inPageFetch
        self.backsOff = backsOff
    }

    var host: String {
        url.host(percentEncoded: false)?.lowercased() ?? ""
    }
}

/// A page as read, with how it was read (analytics row 31, spec 12).
struct LoadedPage: Sendable, Hashable {
    var url: URL
    /// The HTML (or the in-page JSON for an `inPageFetch` request).
    var text: String
    var loadPath: LoadPath
    var challenge: ChallengeKind = .notChallenged
    /// A cold-store home page load ran first.
    var warmUp = false
    /// The owner completed a check with Open Here.
    var openedHere = false
}

/// A way to read a page: plain requests or the hidden WebKit view (spec 8.6). Tests use fakes.
protocol PageLoader: Sendable {
    func load(_ request: PageLoadRequest) async throws(ImportFailure) -> LoadedPage
    /// True when the loader's cookie store holds nothing for this site yet (R183 warm-up).
    func needsWarmUp(for url: URL) async -> Bool
}

extension PageLoader {
    func needsWarmUp(for _: URL) async -> Bool {
        false
    }
}

/// Plain `GET`s through an `HTTPTransport` (spec 8.2): redirects followed by hand (at most
/// 5, every hop checked, never `https` -> `http`), status mapping, content types and charset.
/// A challenge page is `.challenged` and a 403 is `.blocked`, so `PageFetcher` can try the
/// WebKit loader once.
struct PlainPageLoader: PageLoader {
    static let maxRedirects = 5
    static let acceptedTypes = [
        "text/html",
        "application/xhtml+xml",
        "text/plain",
        "application/json",
    ]

    var transport: any HTTPTransport

    func load(_ request: PageLoadRequest) async throws(ImportFailure) -> LoadedPage {
        var url = request.url
        if let path = request.inPageFetch {
            guard let api = URL(string: path, relativeTo: url)?.absoluteURL else { throw .notAPage }
            url = api
        }
        guard WebAddress.validated(url) != nil else { throw .notAPage }
        for _ in 0 ... Self.maxRedirects {
            let response = try await transport.send(HTTPRequest(url: url, headers: [
                "Accept": "text/html,application/xhtml+xml",
                "Accept-Language": "en",
            ]))
            if (300 ... 399).contains(response.status), response.status != 304 {
                guard let location = response.headers["location"],
                      let next = URL(string: location, relativeTo: url)?.absoluteURL,
                      WebAddress.allowsRedirect(from: url, to: next)
                else { throw .notAPage }
                url = next
                continue
            }
            return try Self.page(from: response, url: url)
        }
        throw .notAPage
    }

    static func page(from response: HTTPResponse, url: URL) throws(ImportFailure) -> LoadedPage {
        let html = decode(response.body, contentType: response.headers["content-type"])
        let verdict = ChallengeDetector.verdict(PageSignals(
            status: response.status, headers: response.headers, html: html,
        ))
        if case .challenge = verdict {
            throw .challenged
        }
        switch response.status {
        case 200 ... 299: break
        case 404, 410: throw .notFound
        case 401, 403: throw .blocked
        case 429, 503: throw .busy(retryAfter: response.retryAfter)
        default: throw .server(status: response.status)
        }
        let type = response.headers["content-type"]?.split(separator: ";").first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if let type, !acceptedTypes.contains(type) {
            throw .notAPage
        }
        if response.body.count > URLSessionTransport.bodyCap {
            throw .tooLarge
        }
        return LoadedPage(url: url, text: html, loadPath: .plain)
    }

    /// Charset from the header, then `<meta charset>`, then UTF-8, then Windows-1252.
    static func decode(_ data: Data, contentType: String?) -> String {
        let declared = charset(in: contentType ?? "") ?? sniffedCharset(data)
        if let declared, let encoding = encoding(named: declared),
           let text = String(bytes: data, encoding: encoding)
        {
            return text
        }
        return String(bytes: data, encoding: .utf8)
            ?? String(bytes: data, encoding: .windowsCP1252)
            ?? String(bytes: data, encoding: .isoLatin1) ?? ""
    }

    private static func charset(in text: String) -> String? {
        text.firstMatch(of: /(?i)charset\s*=\s*["']?([A-Za-z0-9_-]+)/).map { String($0.output.1) }
    }

    private static func sniffedCharset(_ data: Data) -> String? {
        let head = String(bytes: data.prefix(2048), encoding: .isoLatin1) ?? ""
        return head.firstMatch(of: /(?i)<meta[^>]+charset\s*=\s*["']?([A-Za-z0-9_-]+)/)
            .map { String($0.output.1) }
    }

    private static func encoding(named name: String) -> String.Encoding? {
        switch name.lowercased() {
        case "utf-8", "utf8": .utf8
        case "ascii", "cp1252", "iso-8859-1", "latin1", "us-ascii", "windows-1252": .windowsCP1252
        case "utf-16": .utf16
        default: nil
        }
    }
}
