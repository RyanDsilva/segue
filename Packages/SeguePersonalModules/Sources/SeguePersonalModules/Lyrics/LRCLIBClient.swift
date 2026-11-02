import Foundation
import Plugins

/// One LRCLIB record (spec 6.1). Decoded tolerantly: unknown fields ignored, missing optional
/// fields nil. `duration` is never stored (R172).
struct LyricsRecord: Sendable, Hashable, Decodable {
    var id: Int
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var instrumental: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?

    var isInstrumental: Bool {
        instrumental ?? false
    }
}

/// The LRCLIB API client (spec 6.2): `GET /api/search?q=` and `GET /api/get/{id}`, through the
/// shared pacer (300 ms gap, five 503 retries), identified as Segue. No App-Id (R179).
struct LRCLIBClient: Sendable {
    static let base = "https://lrclib.net"

    var transport: any HTTPTransport
    var pacer: RequestPacer
    var userAgent: String

    func search(
        _ query: String,
        onRetry: @escaping @Sendable (Int) -> Void = { _ in },
    ) async throws(ImportFailure) -> [LyricsRecord] {
        var components = URLComponents(string: Self.base + "/api/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { throw .notAPage }
        let response = try await send(url, onRetry: onRetry)
        return try Self.decode([LyricsRecord].self, response)
    }

    /// One record, for a search hit whose lyrics were missing but which is not instrumental.
    func record(id: Int) async throws(ImportFailure) -> LyricsRecord {
        guard let url = URL(string: Self.base + "/api/get/\(id)") else { throw .notAPage }
        return try await Self.decode(LyricsRecord.self, send(url, onRetry: { _ in }))
    }

    private func send(
        _ url: URL,
        onRetry: @escaping @Sendable (Int) -> Void,
    ) async throws(ImportFailure) -> HTTPResponse {
        let request = HTTPRequest(
            url: url,
            headers: ["Accept": "application/json", "Lrclib-Client": userAgent],
        )
        let response = try await pacer.sendRetryingOverload(
            request,
            via: transport,
            onRetry: onRetry,
        )
        if response.status == 429 {
            // Nothing is retried after a 429: the host is held for the full Retry-After.
            await pacer.hold(RequestPacer.lyricsHost, for: response.retryAfter ?? .seconds(60))
            throw .busy(retryAfter: response.retryAfter)
        }
        return response
    }

    /// 200 with a JSON body decodes; 404 is not found; anything else, or a body that is not
    /// the expected JSON (an edge error page), is a server failure.
    static func decode<T: Decodable>(
        _ type: T.Type,
        _ response: HTTPResponse,
    ) throws(ImportFailure) -> T {
        switch response.status {
        case 200: break
        case 404: throw .notFound
        default: throw .server(status: response.status)
        }
        let contentType = response.headers["content-type"] ?? "application/json"
        guard contentType.contains("json"),
              let value = try? JSONDecoder().decode(T.self, from: response.body)
        else { throw .server(status: response.status) }
        return value
    }
}
