/// The pieces of a directive line as written:
/// `leading "{" innerLeading name separator value innerTrailing "}" trailing`.
struct DirectiveSpelling {
    var leading: Substring
    var innerLeading: Substring
    var name: Substring
    /// Whitespace and/or `:` between the name and the value (empty when there is no value).
    var separator: Substring
    /// `nil` when the directive has no separator (`{chorus}`); `""` for `{c:}`.
    var value: Substring?
    var innerTrailing: Substring
    var trailing: Substring
}

/// What a directive means, independent of how it was spelled.
enum DirectiveMeaning {
    case sectionStart(SectionKind)
    case sectionEnd(SectionKind)
    case chorus
    case comment(CommentStyle)
    /// Metadata or unknown directive, by canonical name.
    case other(String)
}

/// Shared lexing and naming rules for directives (used by both parser and serializer, so
/// the two can never disagree about spelling).
enum DirectiveSyntax {
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")
    static let colon = UInt8(ascii: ":")

    /// Short forms, keyed by lowercased spelling.
    static let aliases: [String: String] = [
        "t": "title",
        "st": "subtitle",
        "c": "comment",
        "ci": "comment_italic",
        "cb": "comment_box",
        "sov": "start_of_verse",
        "eov": "end_of_verse",
        "soc": "start_of_chorus",
        "eoc": "end_of_chorus",
        "sob": "start_of_bridge",
        "eob": "end_of_bridge",
        "sot": "start_of_tab",
        "eot": "end_of_tab",
        "sog": "start_of_grid",
        "eog": "end_of_grid",
    ]

    static let startPrefix = "start_of_"
    static let endPrefix = "end_of_"

    static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09
    }

    /// Index of the first byte that is not a space, tab or UTF-8 byte-order mark.
    static func skipLeadingSpace(_ utf8: Substring.UTF8View) -> Substring.UTF8View.Index {
        var index = utf8.startIndex
        while index < utf8.endIndex {
            if isSpace(utf8[index]) {
                index = utf8.index(after: index)
            } else if utf8[index...].starts(with: [0xEF, 0xBB, 0xBF]) {
                index = utf8.index(index, offsetBy: 3)
            } else {
                break
            }
        }
        return index
    }

    /// Splits a line of the form `ws "{" ... "}" ws` into its pieces; `nil` if the line is
    /// not shaped like a directive. The name may be empty (the caller diagnoses that).
    static func lex(_ line: Substring) -> DirectiveSpelling? {
        let utf8 = line.utf8
        let open = skipLeadingSpace(utf8)
        guard open < utf8.endIndex, utf8[open] == openBrace else { return nil }
        var afterClose = utf8.endIndex
        while afterClose > open, isSpace(utf8[utf8.index(before: afterClose)]) {
            afterClose = utf8.index(before: afterClose)
        }
        guard afterClose > open else { return nil }
        let close = utf8.index(before: afterClose)
        guard close > open, utf8[close] == closeBrace else { return nil }

        var cursor = utf8.index(after: open)
        let innerStart = cursor
        while cursor < close, isSpace(utf8[cursor]) {
            cursor = utf8.index(after: cursor)
        }
        let nameStart = cursor
        while cursor < close, !isSpace(utf8[cursor]), utf8[cursor] != colon {
            cursor = utf8.index(after: cursor)
        }
        let nameEnd = cursor
        var coreEnd = close
        while coreEnd > nameEnd, isSpace(utf8[utf8.index(before: coreEnd)]) {
            coreEnd = utf8.index(before: coreEnd)
        }

        var valueStart = nameEnd
        var value: Substring?
        if nameEnd < coreEnd {
            while valueStart < coreEnd, isSpace(utf8[valueStart]) {
                valueStart = utf8.index(after: valueStart)
            }
            if valueStart < coreEnd, utf8[valueStart] == colon {
                valueStart = utf8.index(after: valueStart)
                while valueStart < coreEnd, isSpace(utf8[valueStart]) {
                    valueStart = utf8.index(after: valueStart)
                }
            }
            value = line[valueStart ..< coreEnd]
        }
        return DirectiveSpelling(
            leading: line[line.startIndex ..< open],
            innerLeading: line[innerStart ..< nameStart],
            name: line[nameStart ..< nameEnd],
            separator: line[nameEnd ..< valueStart],
            value: value,
            innerTrailing: line[(value == nil ? nameEnd : coreEnd) ..< close],
            trailing: line[afterClose...],
        )
    }

    /// Lowercased name with short forms expanded.
    static func canonicalName(_ spelled: some StringProtocol) -> String {
        let lower = spelled.lowercased()
        return aliases[lower] ?? lower
    }

    static func meaning(of spelled: Substring) -> DirectiveMeaning {
        let lower = spelled.lowercased()
        let isAlias = aliases[lower] != nil
        let resolved = aliases[lower] ?? lower
        // Generic sections keep the name as written; aliases only cover the built-in kinds.
        func remainder(dropping prefix: String) -> String {
            isAlias ? String(resolved.dropFirst(prefix.count)) :
                String(spelled.dropFirst(prefix.count))
        }
        if resolved.hasPrefix(startPrefix), resolved.count > startPrefix.count {
            return .sectionStart(sectionKind(remainder(dropping: startPrefix)))
        }
        if resolved.hasPrefix(endPrefix), resolved.count > endPrefix.count {
            return .sectionEnd(sectionKind(remainder(dropping: endPrefix)))
        }
        switch resolved {
        case "chorus": return .chorus
        case "comment": return .comment(.plain)
        case "comment_box": return .comment(.box)
        case "comment_italic": return .comment(.italic)
        case "highlight": return .comment(.highlight)
        default: return .other(resolved)
        }
    }

    static func sectionKind(_ name: String) -> SectionKind {
        switch name.lowercased() {
        case "bridge": .bridge
        case "chorus": .chorus
        case "tab": .tab
        case "verse": .verse
        default: .custom(name)
        }
    }

    static func kindName(_ kind: SectionKind) -> String {
        switch kind {
        case .bridge: "bridge"
        case .chorus: "chorus"
        case let .custom(name): name
        case .tab: "tab"
        case .verse: "verse"
        }
    }

    static func commentName(_ style: CommentStyle) -> String {
        switch style {
        case .box: "comment_box"
        case .highlight: "highlight"
        case .italic: "comment_italic"
        case .plain: "comment"
        }
    }
}
