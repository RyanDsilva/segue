#if os(macOS)
    import AppKit
    import Foundation
    import Observation
    import PDFKit
    import Printing
    import Services

    /// The remembered export options (spec 6.2), stored under `export.pdf.options`.
    enum PDFExportSettings {
        static let defaultsKey = "export.pdf.options"

        static func load(
            from defaults: UserDefaults = .standard,
            locale: Locale = .current,
        ) -> RememberedPrintOptions {
            let paper = PrintPaper.locale(usesUSMeasurement: locale.measurementSystem == .us)
            guard let data = defaults.data(forKey: defaultsKey),
                  var stored = try? JSONDecoder().decode(RememberedPrintOptions.self, from: data)
            else { return .defaults(paper: paper) }
            if (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["paper"] == nil {
                stored.paper = paper
            }
            return stored
        }

        static func save(_ options: RememberedPrintOptions, to defaults: UserDefaults = .standard) {
            var options = options
            // The sheet knows only the modelled options: keep the keys it does not (R196).
            if options.unknown.isEmpty,
               let data = defaults.data(forKey: defaultsKey),
               let stored = try? JSONDecoder().decode(RememberedPrintOptions.self, from: data)
            {
                options.unknown = stored.unknown
            }
            if let data = try? JSONEncoder().encode(options) {
                defaults.set(data, forKey: defaultsKey)
            }
        }

        /// Reset All Settings: back to the defaults (paper from the locale).
        static func reset(in defaults: UserDefaults = .standard) {
            defaults.removeObject(forKey: defaultsKey)
        }
    }

    /// The PDF preview sheet's state (spec 6.2): the snapshot it prints, the options, the
    /// current PDF and what the user did with it. Every option change re-renders and cancels
    /// the render in flight; the actions wait for the PDF of the options shown.
    @MainActor
    @Observable
    final class PDFPreviewModel: Identifiable {
        enum Phase: Equatable {
            /// The first render.
            case making
            /// A re-render, the previous pages still shown.
            case updating
            case ready
            case failed(String)
        }

        struct Environment {
            var defaults: UserDefaults = .standard
            var record: @MainActor (AnalyticsEvent) -> Void = { _ in }
            /// `-SegueExportPath`: Save PDF writes here without a panel.
            var exportPath: URL?
        }

        let id = UUID()
        let snapshot: PDFSnapshot
        /// Opened from File > Print...: the Print button starts focused.
        let opensForPrint: Bool
        private let environment: Environment

        var options: PrintOptions {
            didSet {
                guard options != oldValue else { return }
                optionChanges += 1
                PDFExportSettings.save(options.remembered, to: environment.defaults)
                render()
            }
        }

        private(set) var phase: Phase = .making
        private(set) var pdf: PDFDocument?
        private(set) var document: PrintDocument?
        /// The current PDF in the temporary folder under its file name, for Share.
        private(set) var shareURL: URL?
        /// "Saved Harbour Lights.pdf", shown briefly after a save.
        var flash: String?
        /// The page the viewer shows, 0-based.
        var currentPage = 0

        private(set) var saved = false
        private(set) var printed = false
        private(set) var shared = false
        private(set) var optionChanges = 0
        private(set) var firstRenderTime: Duration?
        private var renderTask: Task<Void, Never>?
        private var hasRecordedSummary = false

        init(
            snapshot: PDFSnapshot,
            opensForPrint: Bool = false,
            environment: Environment = Environment(),
        ) {
            self.snapshot = snapshot
            self.opensForPrint = opensForPrint
            self.environment = environment
            let remembered = PDFExportSettings.load(from: environment.defaults)
            options = PrintOptions(
                remembered: remembered,
                part: snapshot.profile.bassNotes ? .bass : .chords,
                fillsAsTab: snapshot.profile.fillsAsTab,
            )
        }

        // MARK: Rendering

        /// Renders the current options; a render already running is cancelled first.
        func render() {
            renderTask?.cancel()
            phase = pdf == nil ? .making : .updating
            let options = options
            let snapshot = snapshot
            let started = ContinuousClock.now
            renderTask = Task { [weak self] in
                do {
                    let output = try await PDFExport.make(snapshot, options: options)
                    try Task.checkCancellation()
                    guard let self, self.options == options else { return }
                    pdf = output.pdf
                    document = output.document
                    shareURL = shareFile()
                    currentPage = min(currentPage, max(output.pdf.pageCount - 1, 0))
                    phase = .ready
                    if firstRenderTime == nil {
                        firstRenderTime = ContinuousClock.now - started
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, self.options == options else { return }
                    phase = .failed(UserMessage.describe(error))
                    environment.record(.errorOccurred(.pdfExport))
                }
            }
        }

        /// The sheet's first render, unless one already ran or is running.
        func start() {
            guard renderTask == nil else { return }
            render()
        }

        /// Waits for the render in flight (tests).
        func settle() async {
            await renderTask?.value
        }

        /// Save, Share and Print act only on the PDF of the options shown.
        var isReady: Bool {
            phase == .ready && pdf != nil
        }

        // MARK: Presentation

        var title: String {
            snapshot.title
        }

        /// "Song PDF · 2 pages", "Slot PDF · Friday Set, slot 4 · 2 pages", "Songbook PDF ·
        /// 18 songs · 31 pages"; the part when it is not Chords.
        var subtitle: String {
            var parts: [String] = []
            switch snapshot.content {
            case .song: parts.append("Song PDF")
            case let .slot(slot):
                parts += ["Slot PDF", "\(slot.setlist.name), slot \(slot.number)"]
            case let .setlist(setlist, _):
                let songs = setlist.songCount
                parts += ["Songbook PDF", songs == 1 ? "1 song" : "\(songs) songs"]
            case let .selection(records):
                parts += ["Songbook PDF", "\(records.count) songs"]
            }
            switch options.part {
            case .chords: break
            case .bass: parts.append("Bass notes")
            case .lyrics: parts.append("Lyrics")
            }
            if let pages = pdf?.pageCount {
                parts.append(pages == 1 ? "1 page" : "\(pages) pages")
            }
            return parts.joined(separator: " \u{00B7} ")
        }

        /// "Page 3 of 31".
        var pageIndicator: String {
            guard let count = pdf?.pageCount, count > 0 else { return "" }
            return "Page \(min(currentPage, count - 1) + 1) of \(count)"
        }

        var isSongbook: Bool {
            switch snapshot.content {
            case .selection, .setlist: true
            case .slot, .song: false
            }
        }

        /// Fit on one page's caption when it could not fit (spec 5.9).
        var fitCaption: String? {
            guard options.fitOnePage, document?.fitFailed == true, let pages = pdf?.pageCount else {
                return nil
            }
            return "Doesn't fit at 9 pt: printing \(pages) pages"
        }

        var fileName: String {
            document?.fileName ?? PrintFileName.name(title: snapshot.title, part: options.part)
        }

        // MARK: Actions

        /// The PDF written to the app's temporary folder under its file name, for Share.
        private func shareFile() -> URL? {
            guard let pdf, let data = pdf.dataRepresentation() else { return nil }
            let folder = FileManager.default.temporaryDirectory
                .appending(path: "Segue PDF \(id.uuidString)", directoryHint: .isDirectory)
            let url = folder.appending(path: fileName)
            do {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true,
                )
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }

        func noteShared() {
            shared = true
        }

        /// The sheet's Help button opened the guide's Print and PDF page (R181).
        func noteHelpOpened() {
            environment.record(.helpOpened(.pdf))
        }

        /// Writes the PDF to `url` atomically: nothing lands there on failure.
        func write(to url: URL) -> Bool {
            guard isReady, let data = pdf?.dataRepresentation() else { return false }
            do {
                try data.write(to: url, options: .atomic)
                saved = true
                flash = "Saved \(url.lastPathComponent)"
                return true
            } catch {
                phase = .failed(UserMessage.describe(error))
                environment.record(.errorOccurred(.pdfExport))
                return false
            }
        }

        /// Save PDF...: the save panel (or the test path), then the write.
        func save(in window: NSWindow?) async {
            guard isReady else { return }
            if let path = environment.exportPath {
                _ = write(to: path)
                return
            }
            let panel = NSSavePanel()
            panel.title = "Save PDF"
            panel.prompt = "Save"
            panel.nameFieldStringValue = fileName
            panel.allowedContentTypes = [.pdf]
            panel.canCreateDirectories = true
            let response: NSApplication.ModalResponse = if let window {
                await panel.beginSheetModal(for: window)
            } else {
                panel.runModal()
            }
            if response == .OK, let url = panel.url {
                _ = write(to: url)
            }
        }

        /// The system print panel for the PDF, on `window`: the chosen paper, no margins (the
        /// pages carry their own), no scaling.
        func print(in window: NSWindow?) {
            guard isReady, let pdf else { return }
            let info = NSPrintInfo()
            let size = options.paper.size
            info.paperSize = NSSize(width: size.width, height: size.height)
            info.orientation = .portrait
            info.topMargin = 0
            info.bottomMargin = 0
            info.leftMargin = 0
            info.rightMargin = 0
            info.horizontalPagination = .fit
            info.verticalPagination = .fit
            info.jobDisposition = .spool
            guard let operation = pdf.printOperation(
                for: info,
                scalingMode: .pageScaleNone,
                autoRotate: false,
            ) else { return }
            operation.jobTitle = fileName
            let delegate = PrintDelegate { [weak self] success in
                if success {
                    self?.printed = true
                }
            }
            if let window {
                operation.runModal(
                    for: window,
                    delegate: delegate,
                    didRun: #selector(PrintDelegate.printOperationDidRun(_:success:contextInfo:)),
                    contextInfo: nil,
                )
                PrintDelegate.retain(delegate)
            } else if operation.run() {
                printed = true
            }
        }

        // MARK: Analytics

        /// The summary sent once when the sheet closes (spec 11, row 31).
        var summary: PDFExportSummary {
            PDFExportSummary(
                target: PDFExportTarget(snapshot.target),
                part: PDFExportPart(options.part),
                paper: options.paper == .a4 ? .a4 : .letter,
                size: PDFExportSize(options.textSize),
                columns: PDFExportColumns(options.columns),
                repeats: options.repeats == .compact ? .compact : .full,
                fitOnePage: options.fitOnePage,
                sectionMap: options.sectionMap,
                stageNotes: options.stageNotes,
                diagrams: options
                    .part == .chords ? PDFExportDiagrams(options.diagrams) : .notApplicable,
                fills: fills,
                saved: saved,
                printed: printed,
                shared: shared,
                songs: SmallBucket(document?.songPageCounts.count ?? 0),
                pages: SmallBucket(pdf?.pageCount ?? 0),
                medleys: SmallBucket(snapshot.medleyCount),
                optionChanges: SmallBucket(optionChanges),
                renderTime: RenderTimeBucket(firstRenderTime ?? .zero),
            )
        }

        /// What the PDF drew for fills: none, note names or tabs.
        private var fills: PDFExportFills {
            guard options.part == .bass, snapshot.hasFills else { return .noFills }
            return options.fillsAsTab ? .tab : .names
        }

        /// Records the summary (once) and stops any render.
        func close() {
            renderTask?.cancel()
            guard !hasRecordedSummary else { return }
            hasRecordedSummary = true
            environment.record(.pdfExported(summary))
        }
    }

    // MARK: - Analytics values from the print options

    extension PDFExportTarget {
        init(_ target: PrintJob.Target) {
            switch target {
            case .song: self = .song
            case .slot: self = .slot
            case .setlist: self = .setlist
            case .selection: self = .selection
            }
        }
    }

    extension PDFExportPart {
        init(_ part: PrintPart) {
            switch part {
            case .chords: self = .chords
            case .bass: self = .bass
            case .lyrics: self = .lyrics
            }
        }
    }

    extension PDFExportSize {
        init(_ size: PrintTextSize) {
            switch size {
            case .small: self = .small
            case .medium: self = .medium
            case .large: self = .large
            }
        }
    }

    extension PDFExportColumns {
        init(_ columns: PrintColumns) {
            switch columns {
            case .auto: self = .auto
            case .one: self = .one
            case .two: self = .two
            }
        }
    }

    extension PDFExportDiagrams {
        init(_ diagrams: PrintDiagrams) {
            switch diagrams {
            case .asSong: self = .asSong
            case .all: self = .all
            case .off: self = .noDiagrams
            }
        }
    }

    /// Receives `NSPrintOperation`'s sheet result.
    private final class PrintDelegate: NSObject {
        private let done: @MainActor (Bool) -> Void
        @MainActor private static var running: Set<PrintDelegate> = []

        init(done: @escaping @MainActor (Bool) -> Void) {
            self.done = done
        }

        @MainActor
        static func retain(_ delegate: PrintDelegate) {
            running.insert(delegate)
        }

        @MainActor @objc
        func printOperationDidRun(
            _: NSPrintOperation,
            success: Bool,
            contextInfo _: UnsafeMutableRawPointer?,
        ) {
            done(success)
            Self.running.remove(self)
        }
    }
#endif
