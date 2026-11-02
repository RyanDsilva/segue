import Foundation
import SwiftSoup

/// SwiftSoup helpers shared by the page readers (spec 4.4: JSON first, then the DOM).
enum HTMLText {
    /// Line endings are normalised first: E-Chords writes its `<pre>` with bare CR line
    /// ends, which the parser would otherwise turn into spaces.
    static func document(_ html: String, url: URL) -> Document? {
        let normalised = html.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return try? SwiftSoup.parse(normalised, url.absoluteString)
    }

    /// The text of `node` with every newline and space kept (`<pre>` content): text nodes as
    /// written (`getWholeText`, since `text()` loses newlines in some `<pre>`s), `<br>` as a
    /// newline, and `transform` given a chance to write an element itself.
    static func wholeText(of node: Node, transform: (Element) -> String? = { _ in nil }) -> String {
        var output = ""
        for child in node.getChildNodes() {
            if let text = child as? TextNode {
                output += text.getWholeText()
            } else if let element = child as? Element {
                if let written = transform(element) {
                    output += written
                } else if element.tagName() == "br" {
                    output += "\n"
                } else {
                    output += wholeText(of: element, transform: transform)
                }
            }
        }
        return output
    }

    /// Every JSON-LD object on the page, `@graph` entries included.
    static func jsonLD(_ document: Document) -> [[String: Any]] {
        let scripts = (try? document.select("script[type=application/ld+json]").array()) ?? []
        return scripts.flatMap { script -> [[String: Any]] in
            guard let data = script.data().data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
            else { return [] }
            let list = (object as? [[String: Any]]) ?? [(object as? [String: Any]) ?? [:]]
            return list.flatMap { item in [item] + ((item["@graph"] as? [[String: Any]]) ?? []) }
        }
    }

    /// The first JSON-LD object of one of `types`.
    static func jsonLD(_ document: Document, types: Set<String>) -> [String: Any]? {
        jsonLD(document).first { item in
            if let type = item["@type"] as? String {
                return types.contains(type)
            }
            return ((item["@type"] as? [String]) ?? []).contains(where: types.contains)
        }
    }

    static func meta(_ document: Document, property: String) -> String? {
        let value = try? document.select("meta[property=\(property)], meta[name=\(property)]")
            .first()?.attr("content")
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func title(_ document: Document) -> String? {
        let value = try? document.title()
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Decodes HTML entities once (UG double-encodes some content, spec 8.4 step 5).
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return (try? Entities.unescape(text)) ?? text
    }

    /// A JSON value at a key path, navigated tolerantly (never a strict model).
    static func value(_ object: Any?, _ path: [String]) -> Any? {
        path.reduce(object) { current, key in (current as? [String: Any])?[key] }
    }

    static func string(_ object: Any?, _ path: [String]) -> String? {
        let value = value(object, path)
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func int(_ object: Any?, _ path: [String]) -> Int? {
        let value = value(object, path)
        if let number = value as? NSNumber {
            return number.intValue
        }
        return (value as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}
