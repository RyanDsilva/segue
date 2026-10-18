import Foundation
import Synchronization

/// Intercepts every request of a `URLSession` configured with it, so no test ever reaches a
/// real vendor. Each test registers a route under its own unique path prefix (the
/// TelemetryDeck namespace), scripts the responses and reads back what was sent. A request
/// matching no route fails and is recorded in `unrouted`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case status(Int)
        /// Fails like a Mac without a network.
        case offline
        /// Never answers (until the request is cancelled).
        case hang
    }

    struct Captured: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data

        /// The body parsed as the ingest JSON array.
        var signals: [[String: Any]] {
            (try? JSONSerialization.jsonObject(with: body)) as? [[String: Any]] ?? []
        }
    }

    final class Route: Sendable {
        private struct State {
            var replies: [Reply]
            var fallback: Reply
            var captured: [Captured] = []
            var cancelled = 0
        }

        private let state: Mutex<State>

        init(replies: [Reply], fallback: Reply) {
            state = Mutex(State(replies: replies, fallback: fallback))
        }

        var captured: [Captured] {
            state.withLock { $0.captured }
        }

        var cancelled: Int {
            state.withLock { $0.cancelled }
        }

        func setFallback(_ reply: Reply) {
            state.withLock { $0.fallback = reply }
        }

        fileprivate func take(_ request: Captured) -> Reply {
            state.withLock { state in
                state.captured.append(request)
                return state.replies.isEmpty ? state.fallback : state.replies.removeFirst()
            }
        }

        fileprivate func noteCancelled() {
            state.withLock { $0.cancelled += 1 }
        }
    }

    private static let routes = Mutex<[String: Route]>([:])
    private static let unroutedRequests = Mutex<[URL]>([])

    /// Registers a route for every URL whose path starts with `pathPrefix`.
    static func route(
        _ pathPrefix: String,
        replies: [Reply] = [],
        fallback: Reply = .status(200),
    ) -> Route {
        let route = Route(replies: replies, fallback: fallback)
        routes.withLock { $0[pathPrefix] = route }
        return route
    }

    static var unrouted: [URL] {
        unroutedRequests.withLock { $0 }
    }

    // MARK: - URLProtocol

    private let routeForRequest = Mutex<Route?>(nil)

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let route = Self.routes.withLock { routes in
            routes.first { url.path.hasPrefix($0.key) }?.value
        }
        guard let route else {
            Self.unroutedRequests.withLock { $0.append(url) }
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let captured = Captured(
            method: request.httpMethod ?? "",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? Self.read(request.httpBodyStream),
        )
        switch route.take(captured) {
        case let .status(code):
            let response = HTTPURLResponse(
                url: url,
                statusCode: code,
                httpVersion: "HTTP/1.1",
                headerFields: [:],
            )
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .hang:
            routeForRequest.withLock { $0 = route }
        }
    }

    /// Only a hanging request is still open here; answered ones never set the route.
    override func stopLoading() {
        routeForRequest.withLock { $0 }?.noteCancelled()
    }

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
