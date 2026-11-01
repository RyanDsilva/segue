#if os(macOS)
    import Diagrams
    import Editing
    import LiveLayout
    import Printing
    import SwiftUI

    /// The diagrams a printed song draws after its last section (spec 5.8).
    struct PrintSongDiagrams {
        var diagrams: [RenderDiagram]
        var instrument: Instrument
        var tuning: Tuning
    }

    /// One printed page (spec 5.2, 5.10; R187: quiet song pages, the "taped" set list page),
    /// drawn in the light scheme whatever the app's appearance (5.12). Every line sits in a
    /// frame of the height `PrintPageMetrics` / `SetListMetrics` give, so the body drawn is
    /// the body the paginator filled.
    struct PrintPageView: View {
        let page: PrintPage
        let paper: PrintPaper
        /// By song index.
        var diagrams: [Int: PrintSongDiagrams] = [:]

        var body: some View {
            ZStack(alignment: .topLeading) {
                Theme.color.ground
                Group {
                    switch page {
                    case let .song(song):
                        PrintSongPage(
                            page: song,
                            diagrams: diagrams[song.song],
                            bodyWidth: PrintPageMetrics.bodyWidth(paper),
                        )
                    case let .setList(list):
                        PrintSetListPage(page: list, paper: paper)
                    }
                }
                .padding(.top, PrintPageMetrics.top)
                .padding(.horizontal, PrintPageMetrics.side)
                .frame(width: paper.size.width, height: paper.size.height, alignment: .topLeading)
                PrintFooterView(footer: footer, paper: paper)
            }
            .frame(width: paper.size.width, height: paper.size.height)
            .environment(\.colorScheme, .light)
        }

        private var footer: PrintFooter {
            switch page {
            case let .song(song): song.footer
            case let .setList(list): list.footer
            }
        }
    }

    /// Text in a face, size and colour token.
    private func printText(_ text: String, _ face: SchibstedGrotesk, _ size: Double, _ color: Color)
        -> some View
    {
        Text(text).font(face.font(size: size)).foregroundStyle(color).lineLimit(1)
    }

    /// A line in a frame exactly `height` tall, its text vertically centred.
    private extension View {
        func line(_ height: Double, top: Double = 0) -> some View {
            frame(height: height, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, top)
        }
    }

    // MARK: - Song page

    private struct PrintSongPage: View {
        let page: SongPage
        let diagrams: PrintSongDiagrams?
        let bodyWidth: Double

        private typealias Metrics = PrintPageMetrics

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if page.isFirst {
                    header
                } else {
                    continuation
                }
                ZStack(alignment: .topLeading) {
                    StagePlanView(plan: page.plan, style: page.plan.printStyle, tintOverhang: 0)
                    ForEach(page.extras, id: \.self) { extra in
                        if let diagrams {
                            PrintDiagramGrid(
                                diagrams: diagrams,
                                block: page.diagrams,
                                bodyWidth: bodyWidth,
                            )
                            .offset(y: extra.y)
                        }
                    }
                }
            }
        }

        private var header: some View {
            let header = page.header
            return VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    printText(header.title, .extraBold, Metrics.titleSize, Theme.color.ink)
                        .tracking(Theme.tracking.title * Metrics.titleSize)
                        .truncationMode(.tail)
                    Spacer(minLength: 12)
                    if let slot = header.slotLabel {
                        printText(slot, .semiBold, 10, Theme.color.muted).fixedSize()
                    }
                }
                .line(Metrics.titleLine)
                if let credits = header.credits {
                    printText(credits, .medium, 10, Theme.color.muted)
                        .line(Metrics.creditsLine, top: Metrics.lineGap)
                }
                if let performance = header.performance {
                    printText(performance, .semiBold, 10, Theme.color.muted)
                        .line(Metrics.performanceLine, top: Metrics.lineGap)
                }
                if let scale = header.scale {
                    printText(scale, .medium, 9, Theme.color.muted)
                        .line(Metrics.smallLine, top: Metrics.lineGap)
                }
                if let notice = header.notice {
                    printText(notice, .medium, 9, Theme.color.muted)
                        .line(Metrics.smallLine, top: Metrics.lineGap)
                }
                if !header.mapLines.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(header.mapLines.indices, id: \.self) { index in
                            printText(
                                header.mapLines[index],
                                .medium,
                                Metrics.mapSize,
                                Theme.color.muted,
                            )
                            .line(Metrics.smallLine, top: Metrics.lineGap)
                        }
                    }
                    .padding(.top, Metrics.mapTop)
                    .accessibilityElement(children: .combine)
                }
                Rectangle().fill(Theme.color.line)
                    .frame(height: Metrics.rule)
                    .padding(.top, Metrics.ruleTop)
            }
            .padding(.bottom, Metrics.headerBottom)
        }

        private var continuation: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    printText(page.header.continuationTitle, .bold, 10, Theme.color.ink)
                    Spacer(minLength: 12)
                    if let slot = page.header.slotLabel {
                        printText(slot, .semiBold, 10, Theme.color.muted).fixedSize()
                    }
                }
                .line(Metrics.continuationLine)
                Rectangle().fill(Theme.color.line)
                    .frame(height: Metrics.rule)
                    .padding(.top, Metrics.continuationRuleTop)
            }
            .padding(.bottom, Metrics.continuationBottom)
        }
    }

    /// The chord diagrams after the last section: compact cells wrapped across the body.
    private struct PrintDiagramGrid: View {
        let diagrams: PrintSongDiagrams
        let block: PrintDiagramBlock?
        let bodyWidth: Double

        var body: some View {
            if let block {
                let perRow = block.perRow(width: bodyWidth)
                let rows = stride(from: 0, to: diagrams.diagrams.count, by: perRow).map { start in
                    Array(diagrams.diagrams[start ..< min(start + perRow, diagrams.diagrams.count)])
                }
                VStack(alignment: .leading, spacing: block.spacing) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: block.spacing) {
                            ForEach(rows[index]) { diagram in
                                PrintDiagramView(
                                    diagram: diagram,
                                    instrument: diagrams.instrument,
                                    tuning: diagrams.tuning,
                                )
                                .frame(
                                    width: block.cell.width,
                                    height: block.cell.height,
                                    alignment: .top,
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /// One printed diagram: the compact guitar or piano diagram, or the chord's name alone.
    struct PrintDiagramView: View {
        let diagram: RenderDiagram
        let instrument: Instrument
        let tuning: Tuning

        var body: some View {
            switch (instrument, diagram.guitar, diagram.piano) {
            case let (.guitar, guitar?, _):
                GuitarDiagramView(
                    name: diagram.name,
                    shape: guitar.shape,
                    tuning: tuning,
                    capoFret: diagram.capoFret,
                    size: .compact,
                )
            case let (.piano, _, piano?):
                PianoDiagramView(name: diagram.concertName, voicing: piano, size: .compact)
            default:
                DiagramNameLabel(name: diagram.name, metrics: .forSize(.compact))
            }
        }
    }

    // MARK: - Set list page (R187: "taped")

    private struct PrintSetListPage: View {
        let page: SetListPage
        let paper: PrintPaper

        private typealias Metrics = SetListMetrics

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                head
                ForEach(page.rows.indices, id: \.self) { index in
                    row(page.rows[index])
                        .frame(height: page.rows[index].height, alignment: .top)
                }
            }
        }

        private var head: some View {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Theme.color.cue)
                    .frame(width: 64, height: Metrics.tapeHeight)
                    .padding(.bottom, Metrics.tapeBottom)
                    .accessibilityHidden(true)
                let size = page.head.isContinuation ? Metrics.continuationTitleSize : Metrics
                    .titleSize
                printText(page.head.title, .extraBold, size, Theme.color.ink)
                    .tracking(Theme.tracking.display * size)
                    .line(page.head.isContinuation ? Metrics.continuationTitleLine : Metrics
                        .titleLine)
                    .accessibilityAddTraits(.isHeader)
                if let line = page.head.line {
                    printText(line, .medium, 10.5, Theme.color.muted)
                        .line(Metrics.headLine, top: Metrics.headLineGap)
                }
            }
            .padding(.bottom, Metrics.headBottom)
        }

        @ViewBuilder
        private func row(_ placed: PlacedSetListRow) -> some View {
            switch placed.row {
            case let .song(song):
                songRow(
                    number: song.number,
                    title: song.title,
                    credits: song.credits,
                    key: song.key,
                    time: song.time,
                    page: placed.target.map { $0 + 1 },
                )
            case let .missing(number):
                songRow(
                    number: number,
                    title: "Song not in library",
                    credits: nil,
                    key: nil,
                    time: nil,
                    page: nil,
                    missing: true,
                )
            case let .breakHeading(title, total, interval):
                VStack(alignment: .leading, spacing: 0) {
                    if let interval {
                        printText(interval, .semiBold, 9.5, Theme.color.muted)
                            .padding(.leading, numberColumn + numberGap)
                            .line(Metrics.intervalLine, top: Metrics.intervalTop)
                            .padding(.bottom, Metrics.intervalBottom)
                    }
                    HStack(alignment: .center, spacing: 10) {
                        printText(title, .extraBold, 13, Theme.color.ink).fixedSize()
                        Rectangle().fill(Theme.color.ink).frame(height: 1.5)
                        if let total, page.showsTimes {
                            printText(total, .bold, 10, Theme.color.muted).fixedSize()
                        }
                    }
                    .line(Metrics.headingLine, top: Metrics.headingTop)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
        }

        private let numberColumn = 36.0
        private let numberGap = 10.0
        private let keyColumn = 96.0
        private let timeColumn = 52.0
        private let pageColumn = 32.0

        // swiftlint:disable:next function_parameter_count
        private func songRow(
            number: String,
            title: String,
            credits: String?,
            key: String?,
            time: String?,
            page target: Int?,
            missing: Bool = false,
        ) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                printText(number, .extraBold, 16, missing ? Theme.color.muted : Theme.color.ink)
                    .frame(width: numberColumn, alignment: .trailing)
                    .padding(.trailing, numberGap)
                VStack(alignment: .leading, spacing: 0) {
                    printText(
                        title,
                        missing ? .semiBold : .extraBold,
                        missing ? 13 : 16,
                        missing ? Theme.color.muted : Theme.color.ink,
                    )
                    .tracking(missing ? 0 : -0.2)
                    .truncationMode(.tail)
                    .frame(height: Metrics.rowTitleLine, alignment: .leading)
                    if let credits {
                        printText(credits, .medium, 8.5, Theme.color.muted)
                            .truncationMode(.tail)
                            .frame(height: Metrics.rowCreditsLine, alignment: .leading)
                    }
                }
                Spacer(minLength: 8)
                printText(key ?? "", .bold, 12.5, Theme.color.cueText)
                    .truncationMode(.tail)
                    .frame(width: keyColumn, alignment: .leading)
                if page.showsTimes {
                    printText(time ?? "", .medium, 9.5, Theme.color.muted)
                        .frame(width: timeColumn, alignment: .trailing)
                }
                printText(target.map { "p.\($0)" } ?? "", .medium, 8.5, Theme.color.muted)
                    .frame(width: pageColumn, alignment: .trailing)
            }
            .padding(.vertical, Metrics.rowPadding)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Footer

    /// "Friday Set" left, "Page 7 of 31" right, baselines 20 pt above the paper's edge.
    private struct PrintFooterView: View {
        let footer: PrintFooter
        let paper: PrintPaper

        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                if let left = footer.left {
                    printText(left, .medium, 8.5, Theme.color.muted)
                }
                Spacer()
                printText(footer.right, .medium, 8.5, Theme.color.muted)
            }
            .padding(.horizontal, PrintPageMetrics.side)
            .alignmentGuide(.bottom) { $0[.firstTextBaseline] }
            .frame(
                width: paper.size.width,
                height: paper.size.height - PrintPageMetrics.footerBaseline,
                alignment: .bottom,
            )
        }
    }

    extension LayoutPlan {
        /// The print style at this plan's size (the plan carries its size; the style's
        /// gutter and gap values are the same at every size).
        var printStyle: LayoutStyle {
            .print(lyricSize: lyricSize)
        }
    }
#endif
