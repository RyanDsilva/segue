// Owner: P9-1 (spec 5.11, 9). The PDF outline: "Set list" (or "Contents"), each slot
// nested under its break heading when the set has breaks, a medley's members under it.

extension PrintAssembler {
    /// Single chart: the title. Songbook: "Set list" (or "Contents"), then each song,
    /// nested under its break heading when the set has breaks; a medley's members nest
    /// under it, each pointing at its inline header (spec 9).
    static func outline(
        _ job: PrintJob,
        firstPages: [Int],
        anchors: [Int: [Int: Anchor]] = [:],
    ) -> [PrintOutlineEntry] {
        guard let contents = job.contents else {
            return [PrintOutlineEntry(title: job.title, page: 0)]
        }
        var outline = OutlineBuilder(
            first: PrintOutlineEntry(
                title: job.target == .selection ? "Contents" : "Set list",
                page: 0,
            ),
            hasBreaks: contents.rows.contains { row in
                if case .breakHeading = row {
                    return true
                }
                return false
            },
        )
        for row in contents.rows {
            switch row {
            case let .song(song):
                guard firstPages.indices.contains(song.song) else { continue }
                guard let member = song.member else {
                    outline.add(PrintOutlineEntry(
                        title: job.songs[song.song].outlineTitle,
                        page: firstPages[song.song],
                    ))
                    continue
                }
                let anchor = anchors[song.song]?[member]
                outline.addMember(PrintOutlineEntry(
                    title: "\(song.number). \(song.title)",
                    page: anchor?.page ?? firstPages[song.song],
                    top: anchor?.top,
                ))
            case let .medley(song):
                guard firstPages.indices.contains(song.song) else { continue }
                outline.add(PrintOutlineEntry(
                    title: job.songs[song.song].outlineTitle,
                    page: firstPages[song.song],
                ))
            case let .breakHeading(title, _, _):
                outline.startPart(title)
            case .missing:
                continue
            }
        }
        return outline.entries
    }
}

/// Collects outline entries: top level, or under the current break heading; a medley member
/// under the last entry added.
struct OutlineBuilder {
    private var top: [PrintOutlineEntry]
    private var parts: [PrintOutlineEntry] = []
    private let hasBreaks: Bool

    init(first: PrintOutlineEntry, hasBreaks: Bool) {
        top = [first]
        self.hasBreaks = hasBreaks
    }

    mutating func add(_ entry: PrintOutlineEntry) {
        if hasBreaks, !parts.isEmpty {
            parts[parts.count - 1].children.append(entry)
        } else {
            top.append(entry)
        }
    }

    mutating func addMember(_ entry: PrintOutlineEntry) {
        if hasBreaks, let last = parts.indices.last, !parts[last].children.isEmpty {
            parts[last].children[parts[last].children.count - 1].children.append(entry)
        } else if !hasBreaks || parts.isEmpty, top.count > 1 {
            top[top.count - 1].children.append(entry)
        }
    }

    mutating func startPart(_ title: String) {
        top += parts
        parts = [PrintOutlineEntry(title: title, page: 0)]
    }

    /// The entries; a heading points at its first song's place, one with no songs stays on
    /// the list.
    var entries: [PrintOutlineEntry] {
        (top + parts).map { entry in
            var entry = entry
            if let first = entry.children.first {
                entry.page = first.page
                entry.top = first.top
            }
            return entry
        }
    }
}
