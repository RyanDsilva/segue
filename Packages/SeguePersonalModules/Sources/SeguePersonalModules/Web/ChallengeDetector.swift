import Foundation

/// The challenge type a Cloudflare page script states as `cType: '<type>'` (spec 8.6).
enum ChallengeKind: String, Sendable, CaseIterable {
    case notChallenged
    case nonInteractive
    case managed
    case interactive
    case unknown

    init(cType: String?) {
        switch cType?.lowercased() {
        case "", nil: self = .unknown
        case "interactive": self = .interactive
        case "managed": self = .managed
        case "jsch", "non-interactive", "noninteractive": self = .nonInteractive
        default: self = .unknown
        }
    }
}

/// What a load looks like, read from the main response and the page (spec 8.6). Pure: the
/// WebKit loader gathers the facts with one script, the plain loader from the HTML.
struct PageSignals: Sendable, Hashable {
    var status: Int
    /// The main response's `cf-mitigated` header.
    var mitigated: String?
    var title: String
    /// Any of `#challenge-form`, `#challenge-running`, `#challenge-stage`, `.cf-turnstile`,
    /// a `challenges.cloudflare.com` iframe or a `cf-turnstile-response` input is present.
    var hasChallengeElement: Bool
    /// Cloudflare's "Sorry, you have been blocked" page.
    var hasBlockText: Bool
    var cType: String?

    /// Reads the signals from raw HTML (plain responses and saved pages).
    init(status: Int, headers: [String: String], html: String) {
        self.status = status
        mitigated = headers["cf-mitigated"]
        title = Self.title(in: html)
        hasChallengeElement = Self.challengeMarkers.contains { html.contains($0) }
        hasBlockText = html.contains("Sorry, you have been blocked")
        cType = html.firstMatch(of: /cType:\s*'([A-Za-z-]+)'/).map { String($0.output.1) }
    }

    init(
        status: Int,
        mitigated: String? = nil,
        title: String,
        hasChallengeElement: Bool,
        hasBlockText: Bool,
        cType: String?,
    ) {
        self.status = status
        self.mitigated = mitigated
        self.title = title
        self.hasChallengeElement = hasChallengeElement
        self.hasBlockText = hasBlockText
        self.cType = cType
    }

    static let challengeMarkers = [
        "id=\"challenge-form\"", "id=\"challenge-running\"", "id=\"challenge-stage\"",
        "class=\"cf-turnstile\"", "challenges.cloudflare.com/cdn-cgi/challenge-platform",
        "name=\"cf-turnstile-response\"",
    ]

    private static func title(in html: String) -> String {
        guard let match = html.firstMatch(of: /(?is)<title[^>]*>(.*?)<\/title>/) else { return "" }
        return String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The merged challenge rule of prior-art 2.4 (bake-off markers, klank, FlareSolverr).
enum ChallengeDetector {
    enum Verdict: Sendable, Hashable {
        /// The page itself: read it.
        case page
        /// A human check is up; `kind` decides whether the wait is worth it.
        case challenge(ChallengeKind)
        /// A hard block (a 403 with no challenge): Open Here cannot clear it.
        case blocked
    }

    static let challengeTitles = ["Just a moment", "Attention Required", "Verifying"]

    static func verdict(_ signals: PageSignals) -> Verdict {
        let titled = challengeTitles.contains { signals.title.localizedCaseInsensitiveContains($0) }
        let isChallenge = signals.mitigated?.lowercased() == "challenge"
            || signals.hasChallengeElement
            || (titled && !signals.hasBlockText)
        if isChallenge {
            return .challenge(ChallengeKind(cType: signals.cType))
        }
        if signals.status == 403 || signals.hasBlockText {
            return .blocked
        }
        return .page
    }

    /// How long the hidden loader waits for a challenge to clear on its own: none for an
    /// interactive check (only a person can end it, R183), else 12 s (R184).
    static func wait(for kind: ChallengeKind) -> Duration {
        kind == .interactive ? .zero : .seconds(12)
    }
}

/// The hidden view's navigation rule (R183): the main frame stays within the import's
/// address rules, every hop re-checked; subframes load what the page asks for, so the
/// challenge's own frames (`challenges.cloudflare.com`, `about:blank`, `about:srcdoc`) load.
enum NavigationRule {
    static func allows(_ url: URL, isMainFrame: Bool, page: URL) -> Bool {
        guard isMainFrame else { return true }
        guard WebAddress.allowsRedirect(from: page, to: url) else { return false }
        return registrableDomain(WebAddress.siteHost(url))
            == registrableDomain(WebAddress.siteHost(page))
    }

    /// The last two labels of a host (`tabs.ultimate-guitar.com` -> `ultimate-guitar.com`),
    /// enough for the sites the import reads; a cross-site main-frame hop is refused.
    static func registrableDomain(_ host: String) -> String {
        host.split(separator: ".").suffix(2).joined(separator: ".")
    }
}
