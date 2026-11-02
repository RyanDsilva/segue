import Foundation
@testable import SeguePersonalModules
import Testing

/// Spec 8.6 and 15.1: the challenge rule, `cType`, the wait, and the main-frame rule.
struct ChallengeDetectorTests {
    static func signals(
        _ html: String,
        status: Int = 200,
        headers: [String: String] = [:],
    ) -> PageSignals {
        PageSignals(status: status, headers: headers, html: html)
    }

    @Test
    func `a managed challenge page is a challenge with its type`() {
        let verdict = ChallengeDetector.verdict(Self.signals(Pages.challengeHTML, status: 403))
        #expect(verdict == .challenge(.managed))
    }

    @Test(arguments: [
        ("<title>Just a moment...</title>", ChallengeKind.unknown),
        ("<div class=\"cf-turnstile\"></div><script>cType: 'interactive'</script>", .interactive),
        (
            "<input name=\"cf-turnstile-response\"><script>cType: 'non-interactive'</script>",
            .nonInteractive,
        ),
        ("<div id=\"challenge-form\"></div>", .unknown),
    ])
    func `challenge markers`(html: String, kind: ChallengeKind) {
        #expect(ChallengeDetector.verdict(Self.signals(html)) == .challenge(kind))
    }

    @Test
    func `the cf-mitigated header alone is a challenge`() {
        let signals = Self.signals("<p>hi</p>", status: 403, headers: ["cf-mitigated": "challenge"])
        #expect(ChallengeDetector.verdict(signals) == .challenge(.unknown))
    }

    @Test
    func `a block page and a bare 403 are hard blocks`() {
        #expect(ChallengeDetector.verdict(Self.signals(Pages.blockHTML, status: 403)) == .blocked)
        #expect(ChallengeDetector.verdict(Self.signals("<p>no</p>", status: 403)) == .blocked)
        #expect(ChallengeDetector.verdict(Self.signals("<p>chords</p>")) == .page)
    }

    @Test
    func `an interactive check is not waited for`() {
        #expect(ChallengeDetector.wait(for: .interactive) == .zero)
        #expect(ChallengeDetector.wait(for: .managed) == .seconds(12))
        #expect(ChallengeDetector.wait(for: .unknown) == .seconds(12))
    }

    static let page = URL(string: "https://www.e-chords.com/chords/a/b")!

    @Test(arguments: [
        ("https://challenges.cloudflare.com/cdn-cgi/challenge-platform/x", false, true),
        ("about:blank", false, true),
        ("https://ads.example.net/frame", false, true),
        ("https://www.e-chords.com/chords/a/b?__cf_chl_tk=1", true, true),
        ("https://e-chords.com/", true, true),
        ("https://evil.example.com/", true, false),
        ("http://www.e-chords.com/chords/a/b", true, false),
        ("https://192.168.0.1/", true, false),
    ])
    func `navigation is checked on the main frame only`(
        url: String,
        isMain: Bool,
        allowed: Bool,
    ) throws {
        #expect(try NavigationRule.allows(
            #require(URL(string: url)),
            isMainFrame: isMain,
            page: Self.page,
        ) == allowed)
    }

    @Test
    func `the rule list never blocks the challenge host`() throws {
        let json = ImportContentRules.json
        let rules = try #require(try JSONSerialization
            .jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(rules.count == ImportContentRules.blockedHosts.count + 1)
        #expect(!ImportContentRules.blockedHosts.contains { $0.contains("cloudflare") })
        let last = try #require(rules.last)
        #expect((last["action"] as? [String: String])?["type"] == "ignore-previous-rules")
        #expect(((last["trigger"] as? [String: String])?["url-filter"])?
            .contains("challenges") == true)
    }
}
