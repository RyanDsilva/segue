import Foundation
import GenerableTasks
import ModelPort

/// The no-free-whitespace grammars (P3-A section 5.8, the real-paste eval's final design):
/// compact JSON only, so the model cannot pretty-print or run away on spaces. Each grammar
/// accepts exactly the JSON the task's wire type decodes, with the spike's dynamic
/// constraints built in: fixed entry numbers in order (the model chooses only the label or
/// class), closed vocabularies, bounded strings and at most 4 tags per list.
public enum MLXGrammars {
    /// `{"blocks":[{"block":<i>,"label":<label>},...]}` with the task's block numbers in order.
    public static func labels(blockNumbers: [Int]) -> String {
        let items = blockNumbers.indices.map { "b\($0)" }
        let body = items.isEmpty ? "" : " " + items.joined(separator: " \(literal(",")) ") + " "
        var rules = ["root ::= \(literal(#"{"blocks":["#))\(body)\(literal("]}"))"]
        for (position, number) in blockNumbers.enumerated() {
            rules.append("b\(position) ::= \(literal(#"{"block":\#(number),"label":"#)) label "
                + literal("}"))
        }
        rules.append("label ::= " + alternatives(WireVocabulary.labels))
        return rules.joined(separator: "\n")
    }

    /// `{"title":"...","artist":"...","key":<key>}`: strings of at most 80 characters, the key
    /// from the vocabulary or `unknown`.
    public static func metadata() -> String {
        [
            "root ::= \(literal(#"{"title":"#)) str \(literal(#","artist":"#)) str "
                + "\(literal(#","key":"#)) key \(literal("}"))",
            stringRule,
            characterRule,
            "key ::= " + alternatives(WireVocabulary.keysOrUnknown),
        ].joined(separator: "\n")
    }

    /// `{"lines":[{"line":<i>,"kind":<class>},...]}` with lines numbered from 0 as the prompt
    /// shows them.
    public static func lineClasses(count: Int) -> String {
        let items = (0 ..< count).map { "l\($0)" }
        let body = items.isEmpty ? "" : " " + items.joined(separator: " \(literal(",")) ") + " "
        var rules = ["root ::= \(literal(#"{"lines":["#))\(body)\(literal("]}"))"]
        for number in 0 ..< count {
            rules.append("l\(number) ::= \(literal(#"{"line":\#(number),"kind":"#)) kind "
                + literal("}"))
        }
        rules.append("kind ::= " + alternatives(WireVocabulary.lineClasses))
        return rules.joined(separator: "\n")
    }

    /// The set-request chips: tags only from the library (at most 4 per list), opener and
    /// closer a library tag or empty. Without library tags every tag field is empty.
    public static func setRequest(libraryTags: [String]) -> String {
        let tags = Array(Set(libraryTags)).sorted()
        var rules = [
            "root ::= \(literal(#"{"minProficiency":"#)) proficiency "
                + "\(literal(#","includeTags":"#)) tags \(literal(#","excludeTags":"#)) tags "
                + "\(literal(#","openerTag":"#)) tagOrNone \(literal(#","closerTag":"#)) "
                + "tagOrNone \(literal("}"))",
            "proficiency ::= " + alternatives(WireVocabulary.proficiency),
        ]
        if tags.isEmpty {
            rules.append("tags ::= \(literal("[]"))")
            rules.append("tagOrNone ::= \(literal(#""""#))")
        } else {
            rules
                .append("tags ::= \(literal("[]")) | \(literal("[")) tag more{0,3} \(literal("]"))")
            rules.append("more ::= \(literal(",")) tag")
            rules.append("tag ::= " + alternatives(tags))
            rules.append("tagOrNone ::= \(literal(#""""#)) | tag")
        }
        return rules.joined(separator: "\n")
    }

    /// The rule each task's call uses.
    public static func grammar(for task: some ModelTask) -> String {
        switch task {
        case let task as SectionLabelTask:
            labels(blockNumbers: task.blocks.map(\.index))
        case let task as AmbiguousLineTask:
            lineClasses(count: task.lines.count)
        case let task as SetRequestTask:
            setRequest(libraryTags: task.libraryTags)
        default:
            metadata()
        }
    }

    // MARK: - EBNF text

    private static let stringRule = "str ::= \(literal("\"")) char{0,80} \(literal("\""))"
    private static let characterRule = #"char ::= [^"\\\x00-\x1f] | "\\" ["\\/bfnrt]"#

    /// `"v1" | "v2"` where each value is a JSON string literal.
    private static func alternatives(_ values: [String]) -> String {
        values.map { literal(jsonString($0)) }.joined(separator: " | ")
    }

    /// An EBNF string literal for a fragment of JSON text.
    static func literal(_ text: String) -> String {
        let escaped = text.unicodeScalars.map { scalar -> String in
            switch scalar {
            case "\\": #"\\"#
            case "\"": #"\""#
            case "\n": #"\n"#
            case "\r": #"\r"#
            case "\t": #"\t"#
            default: String(scalar)
            }
        }.joined()
        return "\"\(escaped)\""
    }

    /// `value` as a compact JSON string (quotes included).
    static func jsonString(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return text
    }
}
