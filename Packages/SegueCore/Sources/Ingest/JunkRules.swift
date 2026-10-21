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
            $0.wholeMatch(of: #/
            (?: difficulty | tags | views | last \ updated | updated \ on | posted \ on
            | categories | category ) \s* : .*
            /#) != nil
                // A widget's label with its value left behind: `Tuning:`, `BPM:`.
                || $0.wholeMatch(of: /(?:tuning|key|capo|tempo|bpm|mesure|measure|strumming)\s*:/)
                != nil
        },
        JunkRule(name: "share") {
            $0.wholeMatch(of: /share\s+(?:on|via)\s+.*|share\s+this\s+(?:song|tab|page)\b.*/) != nil
                || $0.wholeMatch(of: /share(?:\s+this)?\s*:/) != nil
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
        // R124: the page's own controls, menus and widgets, which a browser select-all copies
        // with the song.
        JunkRule(name: "site control", matches: isSiteControl),
        JunkRule(name: "views") {
            // `15,376,054 views, added to favorites 368,221 times`, `157 258 Views`.
            $0.wholeMatch(of: #/
            \W* \d[\d,.\s]* \s+ views?
            (?: \s*,\s* added \s+ to \s+ favou?rites \s+ [\d,.\s]+ times? )?
            /#) != nil
        },
        JunkRule(name: "rating widget") {
            // `Rating` / `4.8` / `12,628 rates`, `Average rating 4.8 / 5. Vote count: 30`.
            $0.wholeMatch(of: /\d[\d,.\s]*\s+(?:rates|votes|ratings)/) != nil
                || $0.wholeMatch(of: /\d\.\d{1,2}/) != nil
                || $0.wholeMatch(of: /(?:average\s+)?rating\s*:?\s*[\d.]+\s*\/\s*\d+.*/) != nil
                || $0.wholeMatch(of: /click\s+(?:on\s+)?a\s+star\s+to\s+rate\s+it.*/) != nil
                || $0.wholeMatch(of: /how\s+useful\s+was\s+this\s+(?:post|page|tab)\W*/) != nil
        },
        JunkRule(name: "simplify chords") {
            // A site's "Simplify chords" feature and its blurb.
            $0.contains("simplify") && $0.contains("chord")
        },
        JunkRule(name: "page date") { line in
            // A post date or byline on its own line: `Friday, December 05, 2008`,
            // `By Utkatsh / August 9, 2025`, `Published on June 4, 2022 by x`,
            // `16 Nov 2000, by SuN`, `Last update: Feb 19, 2021`. A date needs its day, so
            // a title such as `December, 1963` is kept.
            let date = #/
            (?: (?:mon|tues|wednes|thurs|fri|satur|sun)day ,? \s+ )?
            (?: (?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.? \s+
                \d{1,2}(?:st|nd|rd|th)? ,? \s+ \d{4}
            | \d{1,2}(?:st|nd|rd|th)? \s+
                (?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.? ,? \s+ \d{4} )
            /#
            let marked = line.replacing(date, with: "\u{1}")
            guard marked != line else { return false }
            return marked.wholeMatch(of: /\u{1}/) != nil
                || marked.wholeMatch(of: /by\s+\S+(?:\s+\S+)?\s*\/\s*\u{1}/) != nil
                || marked
                .wholeMatch(of: /(?:published|posted|updated)\s+on\s+\u{1}(?:\s+by\s+\S+)?/) != nil
                || marked.wholeMatch(of: /\u{1}\s*,?\s+by\s+\S+/) != nil
                || marked
                .wholeMatch(of: /last\s+(?:update|edit)(?:ed)?(?:\s+on)?\s*:?\s*\u{1}/) != nil
                || marked.wholeMatch(of: /author\s+\S+.*\blast\s+edit\s+on\s+\u{1}/) != nil
        },
        JunkRule(name: "version tabs") {
            // `chordsver. 1`, `tabs ver. 1 6`: a site's version switcher.
            $0.wholeMatch(of: /(?:(?:chords|tabs?|ukulele|bass)\s*ver\.?\s*[\d\s]+)+/) != nil
        },
        JunkRule(name: "promo") {
            $0.wholeMatch(of: /.*\bsubscribe\s+to\s+(?:our|my)\s+(?:youtube\s+)?channel\b.*/)
                != nil
                || $0.wholeMatch(of: #/
                how \s+ to \s+ read (?: \s+ and \s+ play )? \s+ (?: a \s+ | the \s+ )?
                (?: tabs? | chords ) (?: \s+ for \s+ beginners )?
                /#) != nil
                || $0.wholeMatch(of: #/
                collection \s+ of \s+ strumming \s+ patterns
                | what \s+ strumming \s+ pattern \s+ for \s+ this \s+ song \W*
                | there \s+ is \s+ no \s+ strumming \s+ pattern \s+ for \s+ this \s+ song .*
                /#) != nil
        },
    ]

    // MARK: - Site controls

    /// A line made only of a site's control and widget names (`Transpose`, `Font Size 100%`,
    /// `-+Reset`, `Display Settings Guitar tuner Show all chords diagrams`, `Transpose Up
    /// Transpose Down`, `Facebook`, `Newer Post Older Post`) and the numbers they show. One
    /// word that is not a control keeps the line (`Transpose my heart`), so a lyric is only
    /// dropped if every word of it is a control name.
    static func isSiteControl(_ lowered: String) -> Bool {
        let words = lowered
            .replacing(/[^\p{L}\p{N}%+\-.]+/, with: " ")
            .split(separator: " ")
            .map(String.init)
        guard !words.isEmpty, words.count <= 12 else { return false }
        // A widget's value left on its own line: a zoom or font size (`100%`), or a transpose
        // or key widget's `0` (R142).
        if words.count == 1, words[0] == "0" || words[0].wholeMatch(of: /\d{1,3}%/) != nil {
            return true
        }
        var index = 0
        var controls = 0
        while index < words.count {
            let word = words[index]
            if word.wholeMatch(of: /[-+]*\d*(?:\.\d+)?%?|[-+]+/) != nil {
                index += 1
                continue
            }
            // `-+reset`: control signs glued to a word.
            let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "-+."))
            var matched = 0
            for phrase in controlPhrases where phrase.count > matched {
                guard index + phrase.count <= words.count else { continue }
                let slice = Array(words[index ..< index + phrase.count])
                if slice == phrase || [bare] + slice.dropFirst() == phrase {
                    matched = phrase.count
                }
            }
            guard matched > 0 else { return false }
            index += matched
            controls += 1
        }
        return controls > 0
    }

    /// Control and widget names a select-all copies from chord sites, blogs and share bars.
    /// Single words here must never be a plausible whole lyric line on their own.
    private static let controlPhrases: [[String]] = [
        "transpose", "transpose up", "transpose down", "change key", "original key",
        "font size", "text size", "font", "reset", "autoscroll", "auto scroll", "auto-scroll",
        "stop scroll", "scroll speed", "print", "display settings", "settings",
        "guitar tuner", "tuner", "metronome", "chord diagrams", "guitar chord diagrams",
        "show all chords diagrams", "show all chord diagrams", "show chord diagrams",
        "show chords", "hide chords", "chords", "column", "columns", "add to favorites",
        "add to favourites", "add to playlist", "newer post", "older post",
        "rating", "submit rating", "rate this", "facebook", "twitter", "google+",
        "stumbleupon", "pinterest", "linkedin", "reddit", "tumblr", "whatsapp", "telegram",
        "instagram", "facebook comments", "related", "related posts", "edit tab",
        "edit this tab", "edit this page",
    ].map { $0.split(separator: " ").map(String.init) }

    private static let navigationWords = [
        "home", "songs", "artists", "login", "log in", "sign up", "share", "facebook",
        "twitter", "whatsapp", "chords", "report", "suggest", "print", "tabs",
    ]
}
