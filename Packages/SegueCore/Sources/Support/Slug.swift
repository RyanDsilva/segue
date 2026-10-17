import Foundation

/// File-name slugs for songs and setlists (`songs/<slug>.cho`, `setlists/<slug>.setlist.json`).
public enum Slug {
    /// Longest slug produced by `make(from:)`, before any de-duplication suffix.
    public static let maxLength = 60

    /// Slug used when the text has no ASCII letters or digits (e.g. an empty title).
    public static let fallback = "untitled"

    /// Lowercase ASCII slug of `text`: diacritics folded, apostrophes dropped, every other
    /// run of non-alphanumerics becomes one `-`, no leading/trailing `-`.
    /// `"Tum Hi Ho"` -> `"tum-hi-ho"`, `"Don't Stop"` -> `"dont-stop"`.
    public static func make(from text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil,
        )
        var slug = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash, !slug.isEmpty {
                    slug.append("-")
                }
                pendingDash = false
                slug.unicodeScalars.append(scalar)
                if slug.unicodeScalars.count >= maxLength {
                    break
                }
            } else if !apostrophes.contains(scalar) {
                pendingDash = true
            }
        }
        return slug.isEmpty ? fallback : slug.lowercased()
    }

    /// `base` if it is free, otherwise the first free `base-2`, `base-3`, ...
    public static func unique(_ base: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(base) else { return base }
        var suffix = 2
        while isTaken("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    private static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2019}", "`"]
}
