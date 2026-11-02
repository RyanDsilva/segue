import Foundation

/// The hidden view's ad and tracker block list (R182, spec 8.6), compiled once into a
/// `WKContentRuleList`. It blocks third-party loads from these hosts, which also drops the
/// consent banners they inject, so nothing ever clicks one. The challenge host is never
/// blocked (R183): the list ends with an `ignore-previous-rules` rule for it.
enum ImportContentRules {
    static let identifier = "segue-import-rules-1"
    static let challengeHost = "challenges.cloudflare.com"

    static let blockedHosts = [
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adservice.google.com",
        "googletagmanager.com",
        "googletagservices.com",
        "google-analytics.com",
        "clarity.ms",
        "amazon-adsystem.com",
        "adnxs.com",
        "criteo.com",
        "criteo.net",
        "taboola.com",
        "outbrain.com",
        "scorecardresearch.com",
        "quantserve.com",
        "quantcount.com",
        "pubmatic.com",
        "rubiconproject.com",
        "casalemedia.com",
        "openx.net",
        "smartadserver.com",
        "teads.tv",
        "moatads.com",
        "adsrvr.org",
        "yieldmo.com",
        "sharethrough.com",
        "3lift.com",
        "indexww.com",
        "media.net",
        "bidswitch.net",
        "onetrust.com",
        "cookielaw.org",
        "quantcast.com",
        "hotjar.com",
        "facebook.net",
        "connect.facebook.net",
        "hs-analytics.net",
        "newrelic.com",
        "nr-data.net",
        "pubmine.com",
        "ezoic.net",
        "ezojs.com",
        "adthrive.com",
        "mediavine.com",
        "privacymanager.io",
        "fundingchoicesmessages.google.com",
        "cdn.confiant-integrations.net",
        "btloader.com",
    ]

    /// The rule list in WebKit's content-blocker JSON.
    static var json: String {
        var rules: [[String: [String: Any]]] = blockedHosts.map { host in
            [
                "trigger": [
                    "url-filter": "^https?://([^/]+\\.)?" + escaped(host) + "[:/]",
                    "load-type": ["third-party"],
                ],
                "action": ["type": "block"],
            ]
        }
        rules.append([
            "trigger": ["url-filter": "^https?://" + escaped(challengeHost) + "/"],
            "action": ["type": "ignore-previous-rules"],
        ])
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])) ??
            Data()
        return String(bytes: data, encoding: .utf8) ?? "[]"
    }

    private static func escaped(_ host: String) -> String {
        host.replacingOccurrences(of: ".", with: "\\.")
    }
}
