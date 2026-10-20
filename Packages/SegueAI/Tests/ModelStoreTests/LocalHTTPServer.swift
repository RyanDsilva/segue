import Foundation
import Network

/// A tiny HTTP/1.1 server on 127.0.0.1 for the downloader tests: real sockets, so the
/// headers asserted are the ones URLSession actually sends (a `URLProtocol` stub never sees
/// the headers CFNetwork adds, such as `Accept-Language`).
final class LocalHTTPServer: @unchecked Sendable {
    struct Request: Sendable {
        var method: String
        var path: String
        /// Header names lowercased.
        var headers: [String: String]
    }

    struct Response: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
        /// The body goes out in chunks of this size with `chunkDelay` between them.
        var chunkSize = 64 << 10
        var chunkDelay: Duration = .zero

        static func status(_ code: Int) -> Self {
            Self(status: code)
        }

        static func redirect(to path: String) -> Self {
            Self(status: 302, headers: ["Location": path])
        }

        /// The file, honouring a `bytes=N-` Range with 206.
        static func file(
            _ data: Data,
            for request: Request,
            chunkSize: Int = 64 << 10,
            chunkDelay: Duration = .zero,
        ) -> Self {
            if let range = request.headers["range"], range.hasPrefix("bytes="),
               let start = Int(range.dropFirst(6).split(separator: "-").first ?? ""),
               start < data.count
            {
                return Self(
                    status: 206,
                    headers: ["Content-Range": "bytes \(start)-\(data.count - 1)/\(data.count)"],
                    body: data.subdata(in: start ..< data.count),
                    chunkSize: chunkSize,
                    chunkDelay: chunkDelay,
                )
            }
            return Self(status: 200, body: data, chunkSize: chunkSize, chunkDelay: chunkDelay)
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalHTTPServer")
    private let lock = NSLock()
    private var requests: [Request] = []
    private let handler: @Sendable (Request) -> Response

    init(handler: @escaping @Sendable (Request) -> Response) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.handler = handler
    }

    /// Every request so far, in arrival order.
    var captured: [Request] {
        lock.withLock { requests }
    }

    /// Starts listening; returns `http://127.0.0.1:<port>`.
    func start() async throws -> URL {
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if once.claim() {
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    }
                case let .failed(error):
                    if once.claim() {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        guard let url = URL(string: "http://127.0.0.1:\(port)") else {
            throw URLError(.badURL)
        }
        return url
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(connection, buffer: Data())
    }

    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        let received: @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
        received = { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(bytes: buffer[..<end.lowerBound], encoding: .utf8) ?? ""
                let request = Self.parse(head)
                lock.withLock { requests.append(request) }
                respond(connection, with: handler(request))
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receiveHead(connection, buffer: buffer)
            }
        }
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 << 10,
            completion: received,
        )
    }

    private func respond(_ connection: NWConnection, with response: Response) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        sendBody(connection, body: response.body, offset: 0, response: response)
    }

    private func sendBody(_ connection: NWConnection, body: Data, offset: Int, response: Response) {
        guard offset < body.count else {
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }
        let end = min(offset + response.chunkSize, body.count)
        let sent: @Sendable (NWError?) -> Void = { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            if response.chunkDelay == .zero {
                sendBody(connection, body: body, offset: end, response: response)
            } else {
                let delay = response.chunkDelay.components
                let nanoseconds = Int(delay.seconds) * 1_000_000_000
                    + Int(delay.attoseconds / 1_000_000_000)
                queue.asyncAfter(deadline: .now() + .nanoseconds(nanoseconds)) {
                    self.sendBody(connection, body: body, offset: end, response: response)
                }
            }
        }
        connection.send(
            content: body.subdata(in: offset ..< end),
            completion: .contentProcessed(sent),
        )
    }

    private static func parse(_ head: String) -> Request {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return Request(
            method: parts.first.map(String.init) ?? "",
            path: parts.count > 1 ? String(parts[1]) : "",
            headers: headers,
        )
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 206: "Partial Content"
        case 302: "Found"
        case 404: "Not Found"
        default: "Status"
        }
    }
}

/// True for the first caller only.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
