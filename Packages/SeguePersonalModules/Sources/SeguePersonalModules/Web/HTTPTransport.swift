import Foundation
import Plugins
import Synchronization

/// One plain `GET` (spec 8.2). The transport never follows redirects itself: it returns the
/// 3xx response, and `PlainPageLoader` follows each hop after checking it (`WebAddress`).
struct HTTPRequest: Sendable, Hashable {
    var url: URL
    var headers: [String: String]

    init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

struct HTTPResponse: Sendable, Hashable {
    var url: URL
    var status: Int
    /// Header names in lowercase.
    var headers: [String: String]
    var body: Data

    init(url: URL, status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.url = url
        self.status = status
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first },
        )
        self.body = body
    }

    /// `Retry-After` in seconds, when the response gave one.
    var retryAfter: Duration? {
        headers["retry-after"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .map { .milliseconds(Int(max(0, $0) * 1000)) }
    }
}

/// The injectable IO of the web import (spec 8.2): `URLSessionTransport` ships, and
/// `FixtureTransport` serves saved responses to tests and the E2E fixture launch option.
protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws(ImportFailure) -> HTTPResponse
}

/// Serves saved responses by exact URL; any other URL is a 404. Records every request, so a
/// test can assert exactly what would have reached the network.
final class FixtureTransport: HTTPTransport {
    private let responses: [URL: [HTTPResponse]]
    private let log = Mutex<[HTTPRequest]>([])
    private let served = Mutex<[URL: Int]>([:])

    /// `responses[url]` is served in order, the last one repeating.
    init(_ responses: [URL: [HTTPResponse]]) {
        self.responses = responses
    }

    convenience init(_ responses: [URL: HTTPResponse]) {
        self.init(responses.mapValues { [$0] })
    }

    var requests: [HTTPRequest] {
        log.withLock { $0 }
    }

    func send(_ request: HTTPRequest) async throws(ImportFailure) -> HTTPResponse {
        if Task.isCancelled {
            throw .cancelled
        }
        log.withLock { $0.append(request) }
        guard let list = responses[request.url], !list.isEmpty else {
            return HTTPResponse(url: request.url, status: 404)
        }
        let index = served.withLock { counts in
            let index = counts[request.url, default: 0]
            counts[request.url] = index + 1
            return index
        }
        return list[min(index, list.count - 1)]
    }
}
