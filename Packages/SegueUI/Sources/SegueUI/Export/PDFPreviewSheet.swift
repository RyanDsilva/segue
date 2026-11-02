#if os(macOS)
    import PDFKit
    import Printing
    import SwiftUI

    /// The PDF preview (P9-1 spec 6, R187 direction A): the title row, the options in a
    /// grouped column on the left, the pages on the right, and the page indicator with Share,
    /// Save PDF..., Print... and Done along the bottom. The chrome follows the app's
    /// appearance; the pages are always light paper.
    struct PDFPreviewSheet: View {
        @Bindable var model: PDFPreviewModel
        var windowSize: CGSize?
        let onDone: () -> Void
        @State private var pdfView = PDFViewHandle()
        @FocusState private var focusesPrint: Bool

        static func size(in window: CGSize?) -> CGSize {
            guard let window else { return CGSize(width: 1180, height: 820) }
            return CGSize(width: max(900, window.width - 48), height: max(640, window.height - 40))
        }

        var body: some View {
            let size = Self.size(in: windowSize)
            VStack(spacing: 0) {
                titleRow
                Rule()
                HStack(spacing: 0) {
                    PDFOptionsColumn(model: model)
                        .frame(width: 360)
                    Rule(axis: .vertical)
                    pages
                }
                Rule()
                bottomBar
            }
            .frame(width: size.width, height: size.height)
            .background(Theme.color.ground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.pdfSheet)
            .onAppear {
                model.start()
                focusesPrint = model.opensForPrint
            }
            .onDisappear { model.close() }
            .onExitCommand(perform: onDone)
            .background { zoomShortcuts }
        }

        private var titleRow: some View {
            HStack(alignment: .center, spacing: 12) {
                titles
                GuideHelpButton(.pdf) { model.noteHelpOpened() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }

        private var titles: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(SchibstedGrotesk.bold.font(size: 18))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(model.subtitle)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                    .accessibilityIdentifier(AccessibilityID.pdfSubtitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var pages: some View {
            ZStack {
                Theme.color.surfaceAlt
                PDFKitView(document: model.pdf, currentPage: $model.currentPage, handle: pdfView)
                    .opacity(model.pdf == nil ? 0 : 1)
                if model.pdf == nil, model.phase == .making {
                    ProgressView("Making the PDF\u{2026}")
                        .controlSize(.small)
                        .accessibilityIdentifier(AccessibilityID.pdfProgress)
                }
                if case let .failed(reason) = model.phase {
                    PDFErrorBanner(reason: reason) { model.render() }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var bottomBar: some View {
            HStack(spacing: 8) {
                indicator
                Spacer(minLength: 16)
                share
                Button("Save PDF\u{2026}") {
                    Task { await model.save(in: NSApp.keyWindow) }
                }
                .buttonStyle(.segueSecondary)
                .keyboardShortcut("s")
                .disabled(!model.isReady)
                .accessibilityIdentifier(AccessibilityID.pdfSave)
                Button("Print\u{2026}") { model.print(in: NSApp.keyWindow) }
                    .buttonStyle(.segueSecondary)
                    .keyboardShortcut("p")
                    .disabled(!model.isReady)
                    .focused($focusesPrint)
                    .accessibilityIdentifier(AccessibilityID.pdfPrint)
                Button("Done", action: onDone)
                    .buttonStyle(.seguePrimary)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AccessibilityID.pdfDone)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }

        @ViewBuilder private var share: some View {
            if model.isReady, let url = model.shareURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.segueSecondary)
                .simultaneousGesture(TapGesture().onEnded { model.noteShared() })
                .accessibilityIdentifier(AccessibilityID.pdfShare)
            } else {
                Button {} label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.segueSecondary)
                .disabled(true)
                .accessibilityIdentifier(AccessibilityID.pdfShare)
            }
        }

        private var indicator: some View {
            HStack(spacing: 8) {
                if let flash = model.flash {
                    Text(flash)
                        .foregroundStyle(Theme.color.ink)
                        .task(id: flash) {
                            try? await Task.sleep(for: .seconds(2.5))
                            if model.flash == flash {
                                model.flash = nil
                            }
                        }
                } else {
                    Text(model.pageIndicator)
                        .monospacedDigit()
                        .accessibilityIdentifier(AccessibilityID.pdfPageIndicator)
                        .accessibilityAddTraits(.updatesFrequently)
                    if model.phase == .updating {
                        ProgressView().controlSize(.mini)
                        Text("Updating\u{2026}")
                    }
                }
            }
            .font(SchibstedGrotesk.medium.font(size: 12.5))
            .foregroundStyle(Theme.color.muted)
            .lineLimit(1)
        }

        /// ⌘+ and ⌘- zoom the pages (spec 6.3).
        private var zoomShortcuts: some View {
            HStack {
                Button("Zoom In") { pdfView.zoomIn() }.keyboardShortcut("+")
                Button("Zoom In") { pdfView.zoomIn() }.keyboardShortcut("=")
                Button("Zoom Out") { pdfView.zoomOut() }.keyboardShortcut("-")
            }
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    /// The live `PDFView`, for the zoom shortcuts.
    @MainActor
    final class PDFViewHandle {
        weak var view: PDFView?

        func zoomIn() {
            (view as? PDFKitView.PreviewPDFView)?.userZoomed = true
            view?.zoomIn(nil)
        }

        func zoomOut() {
            (view as? PDFKitView.PreviewPDFView)?.userZoomed = true
            view?.zoomOut(nil)
        }
    }

    /// "Segue could not make this PDF (reason). Try again" with Try Again (spec 6.2).
    private struct PDFErrorBanner: View {
        let reason: String
        let retry: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.color.cueText)
                    .accessibilityHidden(true)
                Text("Segue could not make this PDF (\(reason)). Try again")
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Try Again", action: retry)
                    .buttonStyle(.segueSecondary)
                    .accessibilityIdentifier(AccessibilityID.pdfTryAgain)
            }
            .padding(12)
            .background(
                Theme.color.ground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.pdfError)
        }
    }

    /// The options (spec 6.2's table), each a native control re-rendering on change.
    private struct PDFOptionsColumn: View {
        @Bindable var model: PDFPreviewModel

        var body: some View {
            Form {
                Section {
                    Picker("Chart", selection: $model.options.part) {
                        Text("Chords").tag(PrintPart.chords)
                        Text("Bass notes").tag(PrintPart.bass)
                        Text("Lyrics").tag(PrintPart.lyrics)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(AccessibilityID.pdfOption("part"))
                }
                Section("Page") {
                    Picker("Paper", selection: $model.options.paper) {
                        Text("A4").tag(PrintPaper.a4)
                        Text("US Letter").tag(PrintPaper.letter)
                    }
                    .accessibilityIdentifier(AccessibilityID.pdfOption("paper"))
                    Picker("Text size", selection: $model.options.textSize) {
                        Text("Small").tag(PrintTextSize.small)
                        Text("Medium").tag(PrintTextSize.medium)
                        Text("Large").tag(PrintTextSize.large)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(AccessibilityID.pdfOption("size"))
                    Picker("Columns", selection: $model.options.columns) {
                        Text("Auto").tag(PrintColumns.auto)
                        Text("1").tag(PrintColumns.one)
                        Text("2").tag(PrintColumns.two)
                    }
                    .accessibilityIdentifier(AccessibilityID.pdfOption("columns"))
                    fitOnePage
                }
                Section("Content") {
                    Picker("Repeats", selection: $model.options.repeats) {
                        Text("Written out").tag(PrintRepeats.writtenOut)
                        Text("Compact").tag(PrintRepeats.compact)
                    }
                    .accessibilityIdentifier(AccessibilityID.pdfOption("repeats"))
                    Toggle("Section map", isOn: $model.options.sectionMap)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier(AccessibilityID.pdfOption("sectionMap"))
                    diagrams
                    if model.options.part == .bass, model.snapshot.hasFills {
                        Toggle("Fills as tab", isOn: $model.options.fillsAsTab)
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier(AccessibilityID.pdfOption("fillsAsTab"))
                    }
                    Toggle("Stage notes and cues", isOn: $model.options.stageNotes)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier(AccessibilityID.pdfOption("stageNotes"))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }

        @ViewBuilder private var fitOnePage: some View {
            let songbook = model.isSongbook
            Toggle(isOn: $model.options.fitOnePage) {
                OptionLabel(
                    "Fit on one page",
                    caption: songbook ? "Songbooks always paginate" : model.fitCaption,
                )
            }
            .toggleStyle(.checkbox)
            .disabled(songbook)
            .help(songbook ? "Songbooks always paginate" : "")
            .accessibilityIdentifier(AccessibilityID.pdfOption("fitOnePage"))
        }

        @ViewBuilder private var diagrams: some View {
            let caption: String? = switch model.options.part {
            case .chords: nil
            case .bass: "Bass charts print no chord diagrams"
            case .lyrics: "Lyric sheets print no chord diagrams"
            }
            Group {
                if model.isSongbook {
                    Picker(selection: $model.options.diagrams) {
                        Text("As each song").tag(PrintDiagrams.asSong)
                        Text("All songs").tag(PrintDiagrams.all)
                        Text("None").tag(PrintDiagrams.off)
                    } label: {
                        OptionLabel("Chord diagrams", caption: caption)
                    }
                } else {
                    Toggle(isOn: singleSongDiagrams) {
                        OptionLabel("Chord diagrams", caption: caption)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .disabled(caption != nil)
            .help(caption ?? "")
            .accessibilityIdentifier(AccessibilityID.pdfOption("diagrams"))
        }

        /// One song: the checkbox shows what prints (its own toggle until changed).
        private var singleSongDiagrams: Binding<Bool> {
            Binding(
                get: {
                    guard model.options.part == .chords else { return false }
                    return model.snapshot.records.first.map {
                        PrintRequests.showsDiagrams($0, options: model.options)
                    } ?? false
                },
                set: { model.options.diagrams = $0 ? .all : .off },
            )
        }
    }

    /// An option's label with its help line under it.
    private struct OptionLabel: View {
        let title: String
        let caption: String?

        init(_ title: String, caption: String?) {
            self.title = title
            self.caption = caption
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
#endif
