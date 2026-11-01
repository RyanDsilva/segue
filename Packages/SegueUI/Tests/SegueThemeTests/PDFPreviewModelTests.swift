import AppKit
import Editing
import Foundation
import Library
import PDFKit
import Printing
@testable import SegueUI
import Services
import Setlists
import SwiftUI
import Testing

/// The preview sheet's model (P9-1 spec 6.2, 11, 14.2): renders, re-renders on an option
/// change, remembers options, starts stage notes off, follows the bass view, saves to the
/// test path, and sends one summary.
@MainActor
@Suite(.serialized)
struct PDFPreviewModelTests {
    typealias Support = PDFTestSupport

    final class Recorder {
        var events: [AnalyticsEvent] = []
    }

    static func defaults() -> UserDefaults {
        let name = "PDFPreviewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func model(
        _ snapshot: PDFSnapshot,
        defaults: UserDefaults,
        recorder: Recorder = Recorder(),
        exportPath: URL? = nil,
    ) -> PDFPreviewModel {
        PDFPreviewModel(
            snapshot: snapshot,
            environment: PDFPreviewModel.Environment(
                defaults: defaults,
                record: { recorder.events.append($0) },
                exportPath: exportPath,
            ),
        )
    }

    @Test
    func `an option change re-renders, is remembered, and actions wait for the PDF`() async throws {
        let defaults = Self.defaults()
        let model = Self.model(
            Support.snapshot(.song(Support.record(Support.harbour))),
            defaults: defaults,
        )
        #expect(!model.options.stageNotes)
        #expect(model.options.part == .chords)
        #expect(!model.isReady)
        model.render()
        #expect(model.phase == .making)
        await model.settle()
        #expect(model.isReady)
        let pages = try #require(model.pdf?.pageCount)
        #expect(model.pageIndicator == "Page 1 of \(pages)")
        #expect(model.subtitle == "Song PDF \u{00B7} \(pages) pages")
        model.options.size = .large
        #expect(model.phase == .updating)
        #expect(!model.isReady)
        model.options.columns = .one
        await model.settle()
        #expect(model.isReady)
        #expect(model.optionChanges == 2)
        let remembered = PDFExportSettings.load(from: defaults)
        #expect(remembered.size == .large)
        #expect(remembered.columns == .one)
        // A new sheet starts from the remembered values, stage notes off again.
        model.options.stageNotes = true
        await model.settle()
        let next = Self.model(
            Support.snapshot(.song(Support.record(Support.harbour))),
            defaults: defaults,
        )
        #expect(next.options.size == .large)
        #expect(!next.options.stageNotes)
        PDFExportSettings.reset(in: defaults)
        #expect(PDFExportSettings.load(from: defaults).size == .medium)
    }

    @Test
    func `the part follows the bass view and fills as tab the user's setting`() {
        var profile = InstrumentProfile()
        profile.bassNotes = true
        profile.fillsAsTab = true
        let model = Self.model(
            Support.snapshot(.song(Support.record(Support.harbour)), profile: profile),
            defaults: Self.defaults(),
        )
        #expect(model.options.part == .bass)
        #expect(model.options.fillsAsTab)
    }

    @Test
    func `save writes the PDF to the test path and the summary is sent once`() async throws {
        let recorder = Recorder()
        let folder = FileManager.default.temporaryDirectory
            .appending(
                path: "PDFPreviewModelTests-\(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Out.pdf")
        let (setlist, records) = PDFSongbookTests.friday()
        let model = Self.model(
            Support.snapshot(.setlist(setlist, records)),
            defaults: Self.defaults(),
            recorder: recorder,
            exportPath: path,
        )
        #expect(model.isSongbook)
        model.render()
        await model.settle()
        await model.save(in: nil)
        let saved = try #require(PDFDocument(url: path))
        #expect(saved.pageCount == model.pdf?.pageCount)
        #expect(model.flash == "Saved Out.pdf")
        #expect(model.shareURL?.lastPathComponent == "Friday Set.pdf")
        model.close()
        model.close()
        let summaries = recorder.events.compactMap { event -> PDFExportSummary? in
            if case let .pdfExported(summary) = event {
                return summary
            }
            return nil
        }
        #expect(summaries.count == 1)
        let summary = try #require(summaries.first)
        #expect(summary.target == .setlist)
        #expect(summary.part == .chords)
        #expect(summary.saved)
        #expect(!summary.printed)
        #expect(summary.diagrams == .asSong)
        #expect(summary.fills == .noFills)
        #expect(summary.songs == SmallBucket(3))
        let signal = AnalyticsEvent.pdfExported(summary).render()
        #expect(signal.params.values
            .allSatisfy { !$0.contains("Friday") && !$0.contains("Anchor") })
    }

    @Test
    func `the menu target is the multi-selection, else the song, else the setlist`() {
        // Pure parts of the targeting: the snapshot of a one-song selection is a song.
        let record = Support.record(Support.harbour)
        let snapshot = Support.snapshot(.selection([record]))
        #expect(snapshot.target == .selection)
        #expect(snapshot.title == "Songbook")
        #expect(PDFTarget.selection([record.id]).kind == .selection)
    }
}

/// Screenshots of the sheet (dark and light chrome) and the printed pages for review:
/// `.build/screenshots/p9-1`.
@MainActor
@Suite(.serialized)
struct PDFSheetSnapshotTests {
    typealias Support = PDFTestSupport

    @Test
    func `the sheet renders in dark and light`() async throws {
        #expect(Theme.registerFonts())
        let (setlist, records) = PDFSongbookTests.friday()
        var profile = InstrumentProfile()
        profile.bassNotes = true
        struct Case {
            var name: String
            var snapshot: PDFSnapshot
            var dark: Bool
        }
        let cases = [
            Case(
                name: "sheet-dark-songbook",
                snapshot: Support.snapshot(.setlist(setlist, records)),
                dark: true,
            ),
            Case(
                name: "sheet-light-bass-chart",
                snapshot: Support.snapshot(
                    .song(Support.record(Support.harbour)),
                    profile: profile,
                ),
                dark: false,
            ),
        ]
        for item in cases {
            let (name, snapshot, dark) = (item.name, item.snapshot, item.dark)
            let model = PDFPreviewModelTests.model(
                snapshot,
                defaults: PDFPreviewModelTests.defaults(),
            )
            model.options.paper = .letter
            model.render()
            await model.settle()
            try await Self.capture(model, dark: dark, name: name)
        }
    }

    /// The sheet in a borderless window (AppKit controls draw only in one), cached to a PNG.
    static func capture(_ model: PDFPreviewModel, dark: Bool, name: String) async throws {
        let size = CGSize(width: 1240, height: 820)
        let host = NSHostingView(rootView: PDFPreviewSheet(model: model, windowSize: nil) {}
            .frame(width: size.width, height: size.height))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(
            contentRect: NSRect(origin: CGPoint(x: -20000, y: -20000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(800))
        host.layoutSubtreeIfNeeded()
        host.display()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = try #require(rep.cgImage)
        try Support.writePNG(image, name: name)
        window.orderOut(nil)
        window.close()
    }
}
