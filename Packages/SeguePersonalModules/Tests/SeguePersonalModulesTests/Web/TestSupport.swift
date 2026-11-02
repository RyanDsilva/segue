import Foundation
import Plugins
@testable import SeguePersonalModules
import Synchronization

/// A clock that moves only when the code under test sleeps, and records every sleep.
final class TestWebClock: WebClock {
    private let state = Mutex<(now: Date, sleeps: [Duration])>(
        (Date(timeIntervalSince1970: 1_767_225_600), []),
    )

    func now() -> Date {
        state.withLock { $0.now }
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        state.withLock { state in
            state.now = state.now.addingTimeInterval(duration.seconds)
            state.sleeps.append(duration)
        }
    }

    func advance(_ duration: Duration) {
        state.withLock { $0.now = $0.now.addingTimeInterval(duration.seconds) }
    }

    var sleeps: [Duration] {
        state.withLock { $0.sleeps }
    }

    var elapsed: TimeInterval {
        now().timeIntervalSince1970 - 1_767_225_600
    }
}

/// A page loader that answers from a script and records what it was asked.
final class FakePageLoader: PageLoader {
    private let answers: Mutex<[Result<LoadedPage, ImportFailure>]>
    private let log = Mutex<[PageLoadRequest]>([])
    private let cold: Bool

    init(_ answers: [Result<LoadedPage, ImportFailure>], cold: Bool = false) {
        self.answers = Mutex(answers)
        self.cold = cold
    }

    var requests: [PageLoadRequest] {
        log.withLock { $0 }
    }

    func load(_ request: PageLoadRequest) async throws(ImportFailure) -> LoadedPage {
        log.withLock { $0.append(request) }
        let answer = answers.withLock { list in list.count > 1 ? list.removeFirst() : list.first }
        guard let answer else { throw .server(status: 0) }
        return try answer.get()
    }

    func needsWarmUp(for _: URL) async -> Bool {
        cold && requests.isEmpty
    }
}

enum Pages {
    static func html(_ body: String, title: String = "Song") -> String {
        "<!doctype html><html><head><title>\(title)</title></head><body>\(body)</body></html>"
    }

    static func response(
        _ url: String,
        status: Int = 200,
        headers: [String: String] = ["Content-Type": "text/html; charset=utf-8"],
        body: String = html("<pre>C G\nLa la</pre>"),
    ) -> HTTPResponse {
        HTTPResponse(
            url: web(url),
            status: status,
            headers: headers,
            body: Data(body.utf8),
        )
    }

    static let challengeHTML = html(
        "<div id=\"challenge-stage\"></div><script>window._cf_chl_opt={cType: 'managed'}</script>",
        title: "Just a moment...",
    )

    static let blockHTML = html(
        "<h1>Sorry, you have been blocked</h1>",
        title: "Attention Required! | Cloudflare",
    )
}

/// A test address; a typo in a literal fails loudly.
func web(_ text: String) -> URL {
    guard let url = URL(string: text) else { preconditionFailure("bad test URL \(text)") }
    return url
}
