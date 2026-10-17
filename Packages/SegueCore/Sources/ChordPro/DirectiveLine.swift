// Owner: unit C (Editing). Public helpers over the internal directive lexer, so the editing
// engine can re-spell one directive line with exactly the rules the parser and serializer
// use (never a second, drifting copy of them).

/// One directive source line as written, split into the parts an editor needs.
public struct DirectiveLine: Sendable {
    /// The whole line (without its line ending).
    public let source: String
    /// Canonical name: lowercased, short forms expanded (`t` -> `title`).
    public let name: String
    /// Value after the separator; `nil` when the directive has none (`{chorus}`).
    public let value: String?

    private let spelling: DirectiveSpelling

    /// Lexes `line` (without a line ending); `nil` if it is not shaped like a directive or
    /// has no name.
    public init?(_ line: String) {
        guard let spelling = DirectiveSyntax.lex(line[...]), !spelling.name.isEmpty else {
            return nil
        }
        self.spelling = spelling
        source = line
        name = DirectiveSyntax.canonicalName(spelling.name)
        value = spelling.value.map(String.init)
    }

    /// The line with its value replaced (`nil` removes the value), keeping the leading and
    /// trailing whitespace, the name as spelled, the separator and the inner padding, as the
    /// serializer does for an edited node.
    public func replacingValue(with newValue: String?) -> String {
        if newValue == value {
            return source
        }
        var text = String(spelling.leading) + "{" + spelling.innerLeading + spelling.name
        if let newValue {
            text += (spelling.separator.isEmpty ? ": " : String(spelling.separator)) + newValue
            text += value == nil ? "" : spelling.innerTrailing
        } else if value == nil {
            text += spelling.innerTrailing
        }
        return text + "}" + spelling.trailing
    }

    /// Canonical spelling of a new directive line: `{name: value}` or `{name}`.
    public static func canonical(name: String, value: String?) -> String {
        value.map { "{\(name): \($0)}" } ?? "{\(name)}"
    }

    /// Lowercased name with short forms expanded, as the parser stores `Directive.name`.
    public static func canonicalName(_ spelled: String) -> String {
        DirectiveSyntax.canonicalName(spelled)
    }

    /// The `SectionKind`s that are pass-through blocks (tab and grid): shown verbatim and
    /// never edited visually.
    public static func isVerbatimSection(_ kind: SectionKind) -> Bool {
        switch kind {
        case .tab: true
        case let .custom(name): name.lowercased() == "grid"
        case .bridge, .chorus, .verse: false
        }
    }
}
