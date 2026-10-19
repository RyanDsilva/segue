import Foundation

/// One kind of web junk a pasted chord sheet carries.
struct JunkRule: Sendable {
    var name: String
    /// Whether the rest of the block is a comment thread.
    var startsCommentSection = false
    var matches: @Sendable (_ lowercased: String) -> Bool
}

/// The rule table the normalizer drops lines by. Every rule is tested
/// (`IngestClassificationTests`); a line under a chord line is never tested against it.
enum JunkRules {
    static func match(_ line: String) -> JunkRule? {
        let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
        return all.first { $0.matches(lowered) }
    }

    static let all: [JunkRule] = [
        JunkRule(name: "credit") {
            $0.wholeMatch(of: /(?:tabbed|transcribed|submitted|uploaded|chords?)\s+by\s*:?\s*.+/)
                != nil
        },
        JunkRule(name: "app ad") { line in
            (line.contains("download") && (line.contains("app") || line.contains("now")))
                || line.contains("ultimate tabs app") || line.contains("ultimate guitar app")
        },
        JunkRule(name: "navigation") { line in
            let parts = line.split(separator: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 2, !line.contains(":"),
                  parts.allSatisfy({ $0.contains(where: \.isLetter) })
            else { return false }
            let shortParts = parts.allSatisfy { $0.split(separator: " ").count <= 4 }
            let navWord = parts.contains { part in navigationWords.contains { part.contains($0) } }
            return shortParts && (parts.count >= 3 || navWord)
        },
        JunkRule(name: "toolbar") { line in
            line == "print" || line.hasPrefix("print ") && line.contains("share")
                || line.contains("autoscroll") || line.contains("auto scroll")
                || line.wholeMatch(of: /.*transpose\s*:?\s*[-+]?\d.*/) != nil
        },
        JunkRule(name: "rating") { line in
            line.contains("\u{2605}") || line.contains("\u{2606}") || line.contains("rate this")
                || line
                .wholeMatch(of: /[\d.]+\s*(?:\/\s*5|stars?)(?:\s*\(\d+\s*ratings?\))?/) != nil
                || line.wholeMatch(of: /\(?\d+\s+ratings?\)?/) != nil
        },
        JunkRule(name: "site field") {
            $0.wholeMatch(of: /(?:difficulty|tags|views|last updated|updated on|posted on)\s*:.*/)
                != nil
        },
        JunkRule(name: "share") {
            $0.wholeMatch(of: /share\s+(?:on|via)\s+.*|share\s+this\s+(?:song|tab|page)\b.*/) != nil
                || $0.wholeMatch(of: /(?:see|view)\s+more\s+(?:songs|chords|tabs)\b.*/) != nil
        },
        JunkRule(name: "advert") {
            $0.wholeMatch(of: /advertisement|sponsored(?:\s+content)?|ads?|skip ad/) != nil
        },
        JunkRule(name: "comment section", startsCommentSection: true) {
            $0.wholeMatch(of: /(?:\d+\s+)?comments?(?:\s*\(\d+\))?|leave a comment|add a comment/)
                != nil
        },
        JunkRule(name: "report") {
            $0.wholeMatch(of: /(?:report|suggest)\s+(?:bad\s+tab|a\s+correction|correction).*/)
                != nil
        },
    ]

    private static let navigationWords = [
        "home", "songs", "artists", "login", "log in", "sign up", "share", "facebook",
        "twitter", "whatsapp", "chords", "report", "suggest", "print", "tabs",
    ]
}
