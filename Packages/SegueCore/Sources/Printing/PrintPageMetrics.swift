// Owner: P9-1 (spec 5.1, 5.2, 5.5, 5.10). Fixed page geometry and the heights of the page
// furniture. The page views draw every line in a frame of exactly these heights, so the body
// the paginator fills is the body that is drawn.

import LiveLayout

public enum PrintPageMetrics {
    /// Margins (R178: fixed): 40 pt top, 36 pt sides and bottom.
    public static let top = 40.0
    public static let side = 36.0
    public static let bottom = 36.0
    /// The footer's baseline, above the paper's bottom edge.
    public static let footerBaseline = 20.0

    // The song header (direction A, quiet).
    public static let titleSize = 20.0
    public static let titleLine = 25.0
    public static let creditsLine = 13.0
    public static let performanceLine = 13.0
    public static let smallLine = 12.0
    public static let lineGap = 3.0
    public static let mapTop = 3.0
    public static let ruleTop = 8.0
    public static let rule = 0.5
    public static let headerBottom = 14.0
    public static let continuationLine = 14.0
    public static let continuationRuleTop = 6.0
    public static let continuationBottom = 12.0
    /// The map line's size (9 pt Medium) and its wrap limit.
    public static let mapSize = 9.0
    public static let mapMaxLines = 2

    /// The body width on `paper`.
    public static func bodyWidth(_ paper: PrintPaper) -> Double {
        paper.size.width - 2 * side
    }

    /// The body height below a header `header` tall.
    public static func bodyHeight(_ paper: PrintPaper, header: Double) -> Double {
        paper.size.height - top - bottom - header
    }

    /// The first page's header height.
    public static func headerHeight(_ header: PrintHeader) -> Double {
        var height = titleLine
        for line in [header.credits, header.performance] where line != nil {
            height += lineGap + creditsLine
        }
        for line in [header.scale, header.notice] where line != nil {
            height += lineGap + smallLine
        }
        if !header.mapLines.isEmpty {
            height += mapTop + Double(header.mapLines.count) * (lineGap + smallLine)
        }
        return height + ruleTop + rule + headerBottom
    }

    /// A continuation page's header: "Harbour Lights (cont.)" and a rule.
    public static let continuationHeight = continuationLine + continuationRuleTop + rule
        + continuationBottom

    /// The page geometry of a song with `header` on `paper`.
    public static func geometry(
        _ paper: PrintPaper,
        header: PrintHeader,
        columns: Int?,
    ) -> PageGeometry {
        let width = bodyWidth(paper)
        return PageGeometry(
            firstBody: LayoutSize(
                width: width,
                height: bodyHeight(paper, header: headerHeight(header)),
            ),
            laterBody: LayoutSize(
                width: width,
                height: bodyHeight(paper, header: continuationHeight),
            ),
            columns: columns,
        )
    }
}

/// The set list page's rows and head (R187: direction C, "taped").
public enum SetListMetrics {
    public static let tapeHeight = 8.0
    public static let tapeBottom = 10.0
    public static let titleSize = 34.0
    public static let titleLine = 40.0
    public static let continuationTitleSize = 22.0
    public static let continuationTitleLine = 28.0
    public static let headLineGap = 4.0
    public static let headLine = 14.0
    public static let headBottom = 16.0

    /// A song row: 16 pt title line, credits under it, 4.5 pt above and below.
    public static let rowPadding = 4.5
    public static let rowTitleLine = 20.0
    public static let rowCreditsLine = 11.0
    /// A break heading: 10 pt above, the 13 pt heading line, 4 pt below; the intermission
    /// line above it.
    public static let headingTop = 10.0
    public static let headingLine = 17.0
    public static let headingBottom = 4.0
    public static let intervalTop = 6.0
    public static let intervalLine = 13.0
    public static let intervalBottom = 2.0

    public static func headHeight(continuation: Bool) -> Double {
        continuation
            ? tapeHeight + tapeBottom + continuationTitleLine + headBottom
            : tapeHeight + tapeBottom + titleLine + headLineGap + headLine + headBottom
    }

    public static func height(_ row: SetListRow) -> Double {
        switch row {
        case let .song(song):
            2 * rowPadding + rowTitleLine + (song.credits == nil ? 0 : rowCreditsLine)
        case .medley, .missing:
            2 * rowPadding + rowTitleLine
        case let .breakHeading(_, _, interval):
            headingTop + headingLine + headingBottom
                + (interval == nil ? 0 : intervalTop + intervalLine + intervalBottom)
        }
    }
}

/// The section map line (spec 5.5, R178: a one-line text roadmap).
public enum PrintMapLine {
    public static let separator = " \u{00B7} "

    /// "Intro · V1 · Ch · V2 · Ch 2/3 · Br (chords) · Ch 3/3 (1st line) · Outro"; nil when
    /// the song has at most one shown pass.
    public static func text(_ passes: [PlanPass]) -> String? {
        guard passes.count > 1 else { return nil }
        return passes.map(item).joined(separator: separator)
    }

    /// The map's spelling of a pass, as the R187 mockups and the spec example write it:
    /// "V1", "Ch", "Br", other parts by their title; its number past the first ("Ch 2/3");
    /// its show mode.
    static func item(_ pass: PlanPass) -> String {
        let title = pass.name.title
        var text = if title.hasPrefix("Verse ") {
            "V" + title.dropFirst("Verse ".count)
        } else if title == "Verse" {
            "V"
        } else if title == "Chorus" {
            "Ch"
        } else if title == "Bridge" {
            "Br"
        } else {
            title
        }
        if let number = pass.name.number, number > 1 {
            text += " \(number)/\(pass.name.total)"
        }
        switch pass.mode {
        case .chordsOnly: text += " (chords)"
        case .firstLine: text += " (1st line)"
        case .full, .skip: break
        }
        return text
    }

    /// `text` wrapped between items to `width` at the map size, at most two lines, the
    /// second ending "..." when more would follow.
    public static func lines(_ text: String, width: Double, metrics: any TextMeasuring)
        -> [String]
    {
        let size = PrintPageMetrics.mapSize
        func fits(_ line: String) -> Bool {
            metrics.width(of: line, role: .note, size: size) <= width
        }
        var lines: [String] = []
        var current = ""
        for item in text.components(separatedBy: separator) {
            let candidate = current.isEmpty ? item : current + separator + item
            if current.isEmpty || fits(candidate) {
                current = candidate
            } else {
                lines.append(current)
                current = item
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        guard lines.count > PrintPageMetrics.mapMaxLines else { return lines }
        var last = lines[PrintPageMetrics.mapMaxLines - 1]
        while !last.isEmpty, !fits(last + separator + "...") {
            var items = last.components(separatedBy: separator)
            items.removeLast()
            last = items.joined(separator: separator)
        }
        lines = Array(lines.prefix(PrintPageMetrics.mapMaxLines - 1))
        lines.append(last.isEmpty ? "..." : last + separator + "...")
        return lines
    }
}
