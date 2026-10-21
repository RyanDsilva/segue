import Foundation
import Synchronization

/// Intercepts every request of a `URLSession` configured with it, so no test ever reaches a
/// real vendor. Each test registers a route under its own unique path prefix (the
/// TelemetryDeck namespace), scripts the responses and reads back what was sent. A request
/// matching no route fails and is recorded in `unrouted`.
private extension Array {
    func partitioned(by predicate: (Element) -> Bool) -> (matching: [Element], rest: [Element]) {
        (filter(predicate), filter { !predicate($0) })
    }
}

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
            var waiters: [Waiter] = []
        }

        private struct Waiter {
            let isSatisfied: @Sendable (State) -> Bool
            let continuation: CheckedContinuation<Void, Never>
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

        /// Returns once `count` requests have arrived (event-driven: no polling, no timeout).
        func waitForCaptured(_ count: Int) async {
            await wait { $0.captured.count >= count }
        }

        /// Returns once the requests that have arrived carry `count` signals in all, however
        /// they were batched.
        func waitForSignals(_ count: Int) async {
            await wait { $0.captured.flatMap(\.signals).count >= count }
        }

        /// Returns once `count` in-flight requests have been cancelled.
        func waitForCancelled(_ count: Int) async {
            await wait { $0.cancelled >= count }
        }

        private func wait(_ isSatisfied: @escaping @Sendable (State) -> Bool) async {
            await withCheckedContinuation { continuation in
                let ready = state.withLock { state in
                    if isSatisfied(state) {
                        return true
                    }
                    state.waiters.append(Waiter(
                        isSatisfied: isSatisfied,
                        continuation: continuation,
                    ))
                    return false
                }
                if ready {
                    continuation.resume()
                }
            }
        }

        private func resumeSatisfiedWaiters() {
            let ready = state.withLock { state in
                let (ready, waiting) = state.waiters.partitioned(by: { $0.isSatisfied(state) })
                state.waiters = waiting
                return ready
            }
            for waiter in ready {
                waiter.continuation.resume()
            }
        }

        func setFallback(_ reply: Reply) {
            state.withLock { $0.fallback = reply }
        }

        fileprivate func take(_ request: Captured) -> Reply {
            let reply = state.withLock { state in
                state.captured.append(request)
                return state.replies.isEmpty ? state.fallback : state.replies.removeFirst()
            }
            resumeSatisfiedWaiters()
            return reply
        }

        fileprivate func noteCancelled() {
            state.withLock { $0.cancelled += 1 }
            resumeSatisfiedWaiters()
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
        // The loading system can start a protocol for a task that was cancelled (and already
        // completed with `cancelled`) before it got here. A real HTTP stack sends nothing for
        // such a task, so it is not a request: recording it would count a send the client
        // never made.
        if let task, task.state != .running {
            return
        }
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
