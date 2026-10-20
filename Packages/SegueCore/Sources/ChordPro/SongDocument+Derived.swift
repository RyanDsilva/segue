import Foundation

public extension SongDocument {
    /// Lyric text without chords, for full-text search: one line per lyric line in document
    /// order (inside and outside sections), chords removed, blank lines kept as empty lines.
    /// Comments, directives and metadata are excluded. Lyric text is never altered.
    var plainLyrics: String {
        var lines: [String] = []
        func visit(_ blocks: [Block]) {
            for block in blocks {
                switch block {
                case .blank: lines.append("")
                case let .line(line): lines.append(line.segments.map(\.text).joined())
                case let .section(section): visit(section.items)
                case .chorusRef, .commentDirective, .directive, .fileComment: break
                }
            }
        }
        visit(blocks)
        return lines.joined(separator: "\n")
    }

    /// The song as the performer sees it, in order:
    /// - each `{start_of_x}` section becomes one `DisplaySection` with its kind and label;
    /// - lyric lines outside sections are grouped into unlabelled sections (`kind == nil`),
    ///   split at blank lines;
    /// - `{chorus}` becomes `DisplaySection(kind: .chorus, label: <label or "Chorus">,
    ///   lines: [], isRepeat: true)`; inside a section it splits that section around it.
    ///
    /// Comments and directives are not included.
    var displaySections: [DisplaySection] {
        var result: [DisplaySection] = []
        var loose: [Line] = []
        func flushLoose() {
            if !loose.isEmpty {
                result.append(DisplaySection(kind: nil, label: nil, lines: loose))
                loose = []
            }
        }
        for block in blocks {
            switch block {
            case .blank:
                flushLoose()
            case let .chorusRef(ref):
                flushLoose()
                result.append(Self.repeatSection(ref))
            case let .line(line):
                loose.append(line)
            case let .section(section):
                flushLoose()
                result += Self.displaySections(of: section)
            case .commentDirective, .directive, .fileComment:
                break
            }
        }
        flushLoose()
        return result
    }

    private static func repeatSection(_ ref: ChorusRef) -> DisplaySection {
        let label = ref.label.flatMap { $0.isEmpty ? nil : $0 } ?? "Chorus"
        return DisplaySection(kind: .chorus, label: label, lines: [], isRepeat: true)
    }

    private static func displaySections(of section: Section) -> [DisplaySection] {
        var result: [DisplaySection] = []
        var lines: [Line] = []
        var isFirstPart = true
        func flush() {
            while lines.first?.segments.isEmpty == true {
                lines.removeFirst()
            }
            while lines.last?.segments.isEmpty == true {
                lines.removeLast()
            }
            if isFirstPart || !lines.isEmpty {
                let label = isFirstPart ? section.label.flatMap { $0.isEmpty ? nil : $0 } : nil
                result.append(DisplaySection(kind: section.kind, label: label, lines: lines))
            }
            lines = []
            isFirstPart = false
        }
        for item in section.items {
            switch item {
            case .blank:
                lines.append(Line())
            case let .chorusRef(ref):
                flush()
                result.append(repeatSection(ref))
            case let .line(line):
                lines.append(line)
            case let .section(nested):
                flush()
                result += displaySections(of: nested)
            case .commentDirective, .directive, .fileComment:
                break
            }
        }
        flush()
        return result
    }
}

extension Metadata {
    /// Standard metadata directives that have no dedicated field and land in `extra`.
    static let extraNames: Set = [
        "album", "arranger", "composer", "copyright", "lyricist", "sorttitle", "year",
    ]

    /// Collects metadata from the directives in `blocks` (including inside sections).
    init(blocks: [Block]) {
        self.init()
        collect(blocks)
    }

    private mutating func collect(_ blocks: [Block]) {
        for block in blocks {
            switch block {
            case let .directive(directive):
                if let value = directive.value {
                    apply(name: directive.name, value: value)
                }
            case let .section(section):
                collect(section.items)
            case .blank, .chorusRef, .commentDirective, .fileComment, .line:
                break
            }
        }
    }

    private mutating func apply(name: String, value: String) {
        switch name {
        case "artist": artists.append(value)
        case "capo": capo = capo ?? Int(value)
        case "duration": duration = duration ?? Self.parseDuration(value)
        case "key": key = key ?? value
        case "meta": addMeta(value)
        case "subtitle": subtitle = subtitle ?? value
        case "tempo": tempo = tempo ?? Self.parseTempo(value)
        case "time": time = time ?? value
        case "title": title = title ?? value
        default: addExtra(name: name, value: value)
        }
    }

    /// Collects a known non-core metadata directive; unknown names are ignored.
    private mutating func addExtra(name: String, value: String) {
        guard Self.extraNames.contains(name) else { return }
        extra[name, default: []].append(value)
    }

    /// `{meta: name value}`.
    private mutating func addMeta(_ value: String) {
        let parts = value.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
        guard let name = parts.first else { return }
        let rest = parts.count > 1 ? String(parts[1]) : ""
        extra[name.lowercased(), default: []].append(rest)
    }

    public static func parseTempo(_ value: String) -> Double? {
        guard let tempo = Double(value), tempo.isFinite, tempo > 0 else { return nil }
        return tempo
    }

    /// Seconds from `ss`, `mm:ss` or `h:mm:ss`.
    static func parseDuration(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let number = Double(part), number.isFinite, number >= 0 else { return nil }
            total = total * 60 + number
        }
        return total
    }

    /// A diagnostic message if a metadata value cannot be understood, else `nil`.
    public static func valueProblem(name: String, value: String) -> String? {
        switch name {
        case "capo" where Int(value) == nil:
            "Capo '\(value)' is not a whole number"
        case "duration" where parseDuration(value) == nil:
            "Duration '\(value)' is not seconds, mm:ss or h:mm:ss"
        case "tempo" where parseTempo(value) == nil:
            "Tempo '\(value)' is not a positive number"
        case "time" where parseTime(value) == nil:
            "Time '\(value)' is not a time signature like 4/4, 3/4 or 6/8"
        default:
            nil
        }
    }

    /// Beats and note value from `n/d` (spaces around the slash allowed): 1-32 beats,
    /// a note value of 1, 2, 4, 8, 16, 32 or 64.
    public static func parseTime(_ value: String) -> (beats: Int, noteValue: Int)? {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let beats = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let noteValue = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              (1 ... 32).contains(beats),
              [1, 2, 4, 8, 16, 32, 64].contains(noteValue)
        else { return nil }
        return (beats, noteValue)
    }
}
