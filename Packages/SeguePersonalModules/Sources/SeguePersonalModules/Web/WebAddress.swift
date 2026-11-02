import Foundation

/// P9-4 spec 8.1: which addresses the web import may read. Only `http` and `https` pages on a
/// public host: no `file:`, `ftp:` or `javascript:`, no host without a dot, no `localhost`, no
/// IP literal in a private, loopback or link-local range, so the feature can never probe the
/// local network. Every redirect hop and every main-frame navigation is checked again.
enum WebAddress {
    /// The address to load, or nil when the import must refuse it before any request.
    static func validated(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(percentEncoded: false)?.lowercased(), isPublic(host: host)
        else { return nil }
        return url
    }

    /// Reads a typed or pasted address: trimmed, `https://` added when no scheme was typed.
    static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let withScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression)
            == nil ? "https://" + trimmed : trimmed
        return URL(string: withScheme).flatMap(validated)
    }

    /// A redirect from `from` to `to` is followed only when `to` is a valid address and it does
    /// not downgrade `https` to `http` (spec 8.2).
    static func allowsRedirect(from: URL, to: URL) -> Bool {
        guard validated(to) != nil else { return false }
        return !(from.scheme?.lowercased() == "https" && to.scheme?.lowercased() == "http")
    }

    /// The host in lowercase, without a leading `www.`, for pacing, back-off and messages.
    static func siteHost(_ url: URL) -> String {
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// True when `host` is `domain` or a subdomain of it (exact suffix match, no regex).
    static func host(_ host: String, isWithin domain: String) -> Bool {
        let host = host.lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }

    private static func isPublic(host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return false
        }
        if host.hasPrefix("[") || host.contains(":") {
            return false // IPv6 literals: never needed for a chord page, refused outright
        }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        if octets.count == 4, octets.allSatisfy({ Int($0) != nil }) {
            return isPublicIPv4(octets.compactMap { Int($0) })
        }
        return octets.count >= 2 && octets.allSatisfy { !$0.isEmpty }
    }

    private static func isPublicIPv4(_ octets: [Int]) -> Bool {
        guard octets.allSatisfy({ (0 ... 255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (0, _), (10, _), (100, 64 ... 127), (127, _), (169, 254), (172, 16 ... 31),
             (192, 168), (224 ... 255, _):
            return false
        default:
            return true
        }
    }
}
