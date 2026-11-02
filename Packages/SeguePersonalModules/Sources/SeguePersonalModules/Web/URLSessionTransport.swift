import Foundation
import Plugins

/// The only type that reaches the real network for plain requests (spec 8.2): an ephemeral
/// session with no cookies, credentials or cache, one connection per host, 15 s request and
/// 30 s resource timeouts, redirects returned rather than followed, and the body streamed
/// against the 5 MB cap. The user's Safari session is never used.
final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate {
    static let bodyCap = 5 * 1024 * 1024

    private let session: URLSession
    private let userAgent: String

    init(userAgent: String) {
        // Spec 15.1: no test may reach the network; a test run that builds this crashes.
        precondition(!Self.isTestProcess, "URLSessionTransport constructed in a test")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        self.userAgent = userAgent
        session = URLSession(configuration: configuration)
        super.init()
    }

    func send(_ request: HTTPRequest) async throws(ImportFailure) -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest, delegate: self)
            guard let http = response as? HTTPURLResponse else { throw ImportFailure.notAPage }
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > Self.bodyCap {
                    throw ImportFailure.tooLarge
                }
            }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                if let name = pair.key as? String, let value = pair.value as? String {
                    result[name] = value
                }
            }
            return HTTPResponse(
                url: http.url ?? request.url, status: http.statusCode, headers: headers, body: body,
            )
        } catch let failure as ImportFailure {
            throw failure
        } catch {
            throw Self.failure(for: error)
        }
    }

    /// Redirects come back as their 3xx response so every hop is checked (spec 8.2).
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
    ) async -> URLRequest? {
        nil
    }

    /// True inside an `xctest` bundle run (both XCTest and Swift Testing load one).
    static var isTestProcess: Bool {
        Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
    }

    static func failure(for error: any Error) -> ImportFailure {
        if error is CancellationError {
            return .cancelled
        }
        guard let urlError = error as? URLError else { return .server(status: 0) }
        switch urlError.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .dataNotAllowed, .internationalRoamingOff, .networkConnectionLost,
             .notConnectedToInternet:
            return .offline
        case .dataLengthExceedsMaximum: return .tooLarge
        default: return .server(status: 0)
        }
    }
}
