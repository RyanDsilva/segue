// Row 14's route and origin (P9-5 section 6), beside AnalyticsEvent.swift so that file stays
// within the file length limit.

extension AnalyticsEvent {
    /// Row 14's parameters: `segue.via` and `segue.from` only when known.
    static func helpParams(
        _ item: HelpItem,
        via: HelpRoute?,
        from: HelpOrigin?,
    ) -> [String: String] {
        var params = ["segue.item": item.rawValue]
        params["segue.via"] = via?.rawValue
        params["segue.from"] = from?.rawValue
        return params
    }
}

/// Which way a Help item opened the guide (P9-5 6): the bundled Help Book, or the web page
/// as its fallback.
public enum HelpRoute: String, Sendable, CaseIterable {
    case book
    case web
}

/// Where Report a Problem was chosen (P9-5 6).
public enum HelpOrigin: String, Sendable, CaseIterable {
    case menu
    case errorBanner
}
