import AppKit
import ChordPro
import CoreText
import Editing
import ImageIO
import LiveLayout
@testable import SegueUI
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// Fixtures, stage sizes and a plan renderer for `StageLayoutRenderTests`.
enum StageLayoutSupport {
    /// `Packages/SegueCore/Tests/Fixtures`, found from this file's location.
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "SegueCore/Tests/Fixtures", directoryHint: .isDirectory)

    static var fixtureNames: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: fixtures.path)) ?? []
        return names.filter { $0.hasSuffix(".cho") }.sorted()
    }

    static func model(_ name: String) throws -> RenderModel {
        try model(source: String(contentsOf: fixtures.appending(path: name), encoding: .utf8))
    }

    static func model(source: String) -> RenderModel {
        RenderModel(document: ChordProParser.parse(source).0, options: DisplayOptions())
    }

    /// Stage body: the screen less 48pt side padding, a 100pt header, a 64pt footer and
    /// 24pt above and below the body (the same assumption as the core suites).
    static func body(_ width: Double, _ height: Double) -> LayoutSize {
        LayoutSize(width: width - 96, height: height - 100 - 64 - 48)
    }

    static let stages: [(name: String, size: LayoutSize)] = [
        ("13in", body(1470, 956)), ("16in", body(1728, 1117)), ("1080p", body(1920, 1080)),
    ]

    static func lyricLines(_ model: RenderModel) -> Int {
        model.sections.flatMap(\.items).count { item in
            if case .lyrics = item {
                return true
            }
            return false
        }
    }

    /// `<repo>/.build/screenshots/layout`.
    static let screenshots = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/screenshots/layout", directoryHint: .isDirectory)

    @MainActor
    static func writeScreenshot(
        _ plan: LayoutPlan,
        name: String,
        showMetrics: Bool = false,
    ) throws {
        let view = PlanCanvas(plan: plan, showMetrics: showMetrics)
            .frame(
                width: plan.viewport.width + 96,
                height: max(plan.viewport.height, plan.contentHeight) + 48,
            )
            .background(Theme.color.ground)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "no image for \(name)")
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        let url = screenshots.appending(path: "\(name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil,
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "could not write \(url.path)")
    }
}

/// Draws a plan exactly as positioned (the stage view's job in unit C), for screenshots.
/// The viewport is outlined; content past it is what scrolls. With `showMetrics`, each run
/// is underlined at its measured width, so drawing and measurement can be compared by eye.
struct PlanCanvas: View {
    let plan: LayoutPlan
    var showMetrics = false
    let style = LayoutStyle.stage
    let origin = CGPoint(x: 48, y: 24)

    var body: some View {
        Canvas { context, _ in
            context.stroke(
                Path(CGRect(origin: origin, size: CGSize(
                    width: plan.viewport.width, height: plan.viewport.height,
                ))),
                with: .color(Theme.color.line),
            )
            for column in plan.columns {
                for block in column.blocks {
                    draw(block, in: column, context: context)
                }
            }
        }
    }

    private func draw(_ block: LayoutBlock, in column: LayoutColumn, context: GraphicsContext) {
        let top = origin.y + block.y
        let left = origin.x + column.x
        let lyricX = left + plan.gutterWidth + style.gutterGap
        context.fill(
            Path(
                roundedRect: CGRect(x: left, y: top, width: column.width, height: block.height),
                cornerRadius: 6,
            ),
            with: .color(tint(block.tint)),
        )
        drawText(block, top: top, left: left, lyricX: lyricX, context: context)
    }

    private func drawText(
        _ block: LayoutBlock,
        top: Double,
        left: Double,
        lyricX: Double,
        context: GraphicsContext,
    ) {
        for line in block.labelLines {
            let isName = line.text.role == .sectionLabel
            text(
                line.text,
                x: left + line.text.x,
                baseline: top + line.baseline,
                color: block.isChorusLabel && isName ? Theme.color.ink : Theme.color.muted,
                context,
            )
        }
        for cue in block.cues {
            let rect = CGRect(
                x: lyricX + cue.x,
                y: top + cue.y,
                width: cue.width,
                height: cue.height,
            )
            context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(Theme.color.cue))
            for line in cue.lines {
                text(
                    line.text,
                    x: rect.minX + line.text.x,
                    baseline: rect.minY + line.baseline,
                    color: Theme.color.cueText,
                    context,
                )
            }
        }
        drawRows(block, top: top, lyricX: lyricX, context: context)
    }

    private func drawRows(
        _ block: LayoutBlock,
        top: Double,
        lyricX: Double,
        context: GraphicsContext,
    ) {
        for row in block.allRows {
            let rowTop = top + row.y
            for chord in row.chords {
                text(
                    chord,
                    x: lyricX + chord.x,
                    baseline: rowTop + (row.chordBaseline ?? 0),
                    color: Theme.color.cueText,
                    context,
                )
            }
            for run in row.text {
                let color = row.kind == .lyric ? Theme.color.ink : Theme.color.muted
                text(
                    run,
                    x: lyricX + run.x,
                    baseline: rowTop + row.textBaseline,
                    color: color,
                    context,
                )
            }
        }
    }

    private func text(
        _ run: PlacedText,
        x: Double,
        baseline: Double,
        color: Color,
        _ context: GraphicsContext,
    ) {
        let resolved = context.resolve(
            Text(run.text).font(StageTypography.font(run.role, size: run.size))
                .foregroundStyle(color),
        )
        let first = resolved.firstBaseline(in: CGSize(width: 10000, height: 10000))
        context.draw(resolved, at: CGPoint(x: x, y: baseline - first), anchor: .topLeading)
        if showMetrics {
            context.fill(
                Path(CGRect(x: x, y: baseline + 2, width: run.width, height: 1)),
                with: .color(Theme.color.cue.opacity(0.7)),
            )
        }
    }

    private func tint(_ tint: SectionTint) -> Color {
        switch tint {
        case .chorus: Color.white.opacity(0.06)
        case .verse: Color.white.opacity(0.025)
        case .bridge: Theme.color.cue.opacity(0.07)
        case .tab: Color.white.opacity(0.04)
        case .other: Color.clear
        }
    }
}
