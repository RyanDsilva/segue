import Foundation

/// Spec 6.6: plain lyrics with blank lines between stanzas go in as they are; with no blank
/// lines but synced lyrics, a blank line goes before any line whose timestamp is at least
/// 5 s after the previous line's. Timestamps are used only for this, then discarded (R172).
enum LRCSections {
    static let stanzaGap = 5.0

    static func text(plain: String, synced: String?) -> String {
        let plain = plain.replacingOccurrences(of: "\r\n", with: "\n")
        guard !plain.contains("\n\n"), let synced, !synced.isEmpty else { return plain }
        var lines: [String] = []
        var previous: Double?
        for raw in synced.components(separatedBy: "\n") {
            guard let match = raw.firstMatch(of: /^\[(\d+):(\d+(?:\.\d+)?)\]\s?(.*)$/),
                  let minutes = Double(match.output.1), let seconds = Double(match.output.2)
            else { continue }
            let time = minutes * 60 + seconds
            let text = String(match.output.3).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if let previous, time - previous >= stanzaGap, !lines.isEmpty {
                lines.append("")
            }
            lines.append(text)
            previous = time
        }
        let plainLines = plain.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // The synced text must be the same lyrics; otherwise keep the plain text as one block.
        guard lines.filter({ !$0.isEmpty }) == plainLines
            .map({ $0.trimmingCharacters(in: .whitespaces) })
        else {
            return plain
        }
        return lines.joined(separator: "\n")
    }
}
