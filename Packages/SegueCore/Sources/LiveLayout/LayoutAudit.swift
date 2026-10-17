// Owner: unit B. Geometric invariants of a plan, for tests and debug checks: nothing
// clipped, nothing overlapping, the lyric size never below the minimum. Vertically, a run's
// glyphs span from its ink top (capitals, ascenders, or the run's own taller glyphs such as
// Devanagari matras) to its descent: chords may sit closer to the lyric than the font boxes
// would, but their ink never meets.

public enum LayoutAudit {
    /// Human-readable violations; empty when the plan is sound.
    public static func violations(
        of plan: LayoutPlan,
        request: LayoutRequest,
        metrics: any TextMeasuring,
    ) -> [String] {
        var issues: [String] = []
        let style = request.style
        if plan.lyricSize < request.minLyricSize - 1e-9 {
            issues.append("lyric size \(plan.lyricSize) below minimum \(request.minLyricSize)")
        }
        if plan.fit == .fits, plan.contentHeight > plan.viewport.height + epsilon {
            issues.append("fits but content \(plan.contentHeight) > \(plan.viewport.height)")
        }
        if plan.needsScroll != (plan.fit != .fits) {
            issues.append("fit \(plan.fit) disagrees with overflow \(plan.overflow)")
        }
        for (index, column) in plan.columns.enumerated() {
            let name = "column \(index)"
            if column.x < -epsilon || column.x + column.width > plan.viewport.width + epsilon {
                issues.append("\(name) outside the viewport width")
            }
            if index > 0, column.x < plan.columns[index - 1].x + plan.columns[index - 1].width {
                issues.append("\(name) overlaps the previous column")
            }
            let lyricWidth = column.width - plan.gutterWidth - style.gutterGap
            var bottom = -Double.infinity
            for block in column.blocks {
                let label = "\(name) block \(block.id).\(block.part)"
                if block.y < bottom - epsilon {
                    issues.append("\(label) overlaps the block above")
                }
                bottom = block.y + block.height
                issues += blockViolations(
                    block,
                    lyricWidth: lyricWidth,
                    gutter: plan.gutterWidth,
                    metrics,
                )
                .map { "\(label): \($0)" }
            }
            if bottom > plan.contentHeight + epsilon {
                issues.append("\(name) taller than contentHeight")
            }
        }
        return issues
    }

    static let epsilon = 0.01

    private static func blockViolations(
        _ block: LayoutBlock,
        lyricWidth: Double,
        gutter: Double,
        _ metrics: any TextMeasuring,
    ) -> [String] {
        var issues: [String] = []
        var bottom = 0.0
        for cue in block.cues {
            if cue.y < bottom - epsilon || cue.y + cue.height > block.height + epsilon {
                issues.append("cue \"\(cue.text)\" outside the block or overlapping")
            }
            if cue.x < -epsilon || cue.x + cue.width > lyricWidth + epsilon {
                issues.append("cue \"\(cue.text)\" wider than the column")
            }
            bottom = cue.y + cue.height
        }
        if let baseline = block.collapsedBaseline, case let .collapsed(line, _) = block.content {
            issues += glyphViolations(
                line, baseline: baseline, top: bottom, bottom: block.height, metrics,
            )
            issues += horizontal([line], width: lyricWidth, what: "collapsed line")
        }
        for row in block.allRows {
            if row.y < bottom - epsilon || row.y + row.height > block.height + epsilon {
                issues.append("row at \(row.y) outside the block or overlapping")
            }
            bottom = row.y + row.height
            issues += rowViolations(row, lyricWidth: lyricWidth, metrics)
        }
        for line in block.labelLines {
            issues += horizontal([line.text], width: gutter, what: "label")
            if line.text.size < LayoutStyle.stage.minLabelSize - epsilon {
                issues
                    .append("label \"\(line.text.text)\" below \(LayoutStyle.stage.minLabelSize)pt")
            }
            issues += glyphViolations(
                line.text, baseline: line.baseline, top: 0, bottom: block.height, metrics,
            )
        }
        return issues
    }

    private static func rowViolations(
        _ row: LayoutRow,
        lyricWidth: Double,
        _ metrics: any TextMeasuring,
    ) -> [String] {
        var issues = horizontal(row.text, width: lyricWidth, what: "text")
            + horizontal(row.chords, width: lyricWidth, what: "chord")
        let chordBottom = row.chordBaseline.map { baseline in
            baseline + (row.chords.map { chord in
                let descent = metrics.extents(of: chord.role).descent
                return max(descent, metrics.inkExtents(of: chord.text, role: chord.role).bottom)
                    * chord.size
            }.max() ?? 0)
        } ?? 0
        for chord in row.chords {
            issues += glyphViolations(
                chord, baseline: row.chordBaseline ?? 0, top: 0, bottom: row.height, metrics,
            ).map { "row at \(row.y): \($0)" }
        }
        for run in row.text {
            issues += glyphViolations(
                run, baseline: row.textBaseline, top: chordBottom, bottom: row.height, metrics,
            ).map { "row at \(row.y): \($0)" }
        }
        return issues
    }

    /// Runs inside `0 ... width`, in order, not overlapping.
    private static func horizontal(_ runs: [PlacedText], width: Double, what: String) -> [String] {
        var issues: [String] = []
        var right = -Double.infinity
        for run in runs {
            if run.x < -epsilon || run.x + run.width > width + epsilon {
                issues.append("\(what) \"\(run.text)\" at \(run.x)+\(run.width) outside \(width)")
            }
            if run.x < right - epsilon {
                issues.append("\(what) \"\(run.text)\" overlaps the previous run")
            }
            if run.size <= 0 {
                issues.append("\(what) \"\(run.text)\" has no size")
            }
            right = run.x + run.width
        }
        return issues
    }

    /// The run's glyphs (ink top above, descent below the baseline) inside `top ... bottom`.
    private static func glyphViolations(
        _ run: PlacedText,
        baseline: Double,
        top: Double,
        bottom: Double,
        _ metrics: any TextMeasuring,
    ) -> [String] {
        // The face's capitals and descenders, or the run's own glyphs where they reach
        // further (Devanagari matras, accents).
        let extents = metrics.extents(of: run.role)
        let ink = metrics.inkExtents(of: run.text, role: run.role)
        let ascent = baseline - max(extents.inkTop, ink.top) * run.size
        let descent = baseline + max(extents.descent, ink.bottom) * run.size
        guard ascent < top - epsilon || descent > bottom + epsilon else { return [] }
        return ["\"\(run.text)\" glyphs \(ascent)...\(descent) clipped by \(top)...\(bottom)"]
    }
}
