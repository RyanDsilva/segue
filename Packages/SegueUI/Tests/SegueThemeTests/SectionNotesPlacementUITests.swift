import AppKit
import Editing
import Foundation
import Library
@testable import SegueUI
import Support
import SwiftUI
import Testing

/// The section notes sheet's placement controls (P3-17, R146 direction A): the "Shows on"
/// choices per note kind, the `{chorus}` repeat hint and confirmation, and the sheet itself
/// rendered in light and dark into `.build/screenshots/section-notes/` for the visual check.
@MainActor
struct SectionNotesPlacementUITests {
    /// Chorus #1, Verse, Chorus #2 and a `{chorus}` repeat of #2.
    static let twice = """
    {title: Tide}

    {start_of_chorus}
    {comment: Everyone sings}
    [C]Tide comes in
    {end_of_chorus}

    {start_of_verse}
    [G]Boats come home
    {end_of_verse}

    {start_of_chorus}
    {comment: Everyone sings}
    {comment: Hold back, let the vocal breathe}
    [C]Tide goes out
    {end_of_chorus}

    {chorus}

    """

    /// One written-out chorus and a repeat of it.
    static let once = """
    {start_of_chorus}
    [C]Tide comes in
    {end_of_chorus}

    {chorus}

    """

    private static func chorus(_ source: String) throws -> SectionNoteGroup {
        let notes = SectionNotes(document: SourceSnapshot(text: source).document, cues: [])
        return try #require(notes.groups.first { $0.title == "Chorus" })
    }

    @Test
    func `the pop-up offers every instance and names repeats`() throws {
        let group = try Self.chorus(Self.twice)
        let chart = SectionNotesPlacement.choices(in: group, chart: true)
        #expect(chart.map(\.title) == [
            "Every time", "Chorus #1", "Chorus #2", "Chorus #3 (repeat)",
        ])
        #expect(SectionNotesPlacement.choices(in: group, chart: false) == chart)
        let hint = try #require(SectionNotesPlacement.repeatHint(for: .instance(3), in: group))
        #expect(hint.action == "Put it in Chorus #2 instead")
        #expect(hint.chartPlacement == .instance(2))
        #expect(SectionNotesPlacement.repeatHint(for: .instance(2), in: group) == nil)
        // The linked every-time note reads as one row.
        let linked = try #require(group.notes.first)
        #expect(linked.isLinked && linked.instances == [1, 2])
    }

    @Test
    func `a chart note on a label written out once cannot pick that instance`() throws {
        let group = try Self.chorus(Self.once)
        #expect(SectionNotesPlacement.choices(in: group, chart: true).map(\.title) == [
            "Every time", "Chorus #2 (repeat)",
        ])
        #expect(SectionNotesPlacement.choices(in: group, chart: false).map(\.title) == [
            "Every time", "Chorus #1", "Chorus #2 (repeat)",
        ])
        let hint = try #require(SectionNotesPlacement.repeatHint(for: .instance(2), in: group))
        #expect(hint.action == "Show it every time instead")
        #expect(hint.chartPlacement == .everyTime)
        let cue = SongCue(section: "Chorus", occurrence: 2, text: "Last time")
        let notes = SectionNotes(document: SourceSnapshot(text: Self.once).document, cues: [cue])
        let note = try #require(notes.note(.stage(cue.id)))
        #expect(SectionNotesPlacement.chartConfirmation(for: note, in: notes.groups[0])
            == "Chorus #2 is a repeat. In the chart this note goes in Chorus #1 and shows "
            + "every time Chorus #1 is played or repeated.")
    }

    private static let songID = "01JC0000000000000000000N02"
    private static let plainID = "01JC0000000000000000000N03"

    /// A library with the notes song (every kind of row) and the same song without notes.
    private func library() async throws -> (env: TestEnvironment, model: LibraryViewModel) {
        let env = try TestEnvironment()
        try FileManager.default.createDirectory(
            at: env.libraryURL.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        try env.write(Self.twice, to: "songs/tide.cho")
        let cues = #"[{"id": "01JC0000000000000000000C01", "section": "Chorus", "occurrence": 2, "#
            + #""fp": "deadbeef", "text": "Big ending"}, {"id": "01JC0000000000000000000C02", "#
            + #""section": "Chorus", "occurrence": 3, "text": "Watch Ravi for the stop"}]"#
        try env.write(Self.sidecar(Self.songID, cues: cues), to: "songs/tide.segue.json")
        try env.write(
            Self.twice.replacingOccurrences(of: "{comment: Everyone sings}\n", with: "")
                .replacingOccurrences(
                    of: "{comment: Hold back, let the vocal breathe}\n",
                    with: "",
                ),
            to: "songs/tide-plain.cho",
        )
        try env.write(Self.sidecar(Self.plainID, cues: "[]"), to: "songs/tide-plain.segue.json")
        return try await (env, env.openLibrary())
    }

    private static func sidecar(_ id: String, cues: String) -> String {
        #"{"schemaVersion": 4, "id": "\#(id)", "cues": \#(cues), "#
            + #""createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-01T10:00:00Z"}"#
    }

    /// The sheet opened from the repeat's band with a new note row, in light and dark.
    private static func render(_ host: SectionNotesHost, as name: String) async throws {
        #expect(Theme.registerFonts())
        for dark in [false, true] {
            let view = NSHostingView(rootView: SectionNotesSheet(
                host: host,
                focus: "section:chorus",
                placement: .instance(3),
                addsNote: true,
            ))
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            view.frame = NSRect(x: 0, y: 0, width: 560, height: 540)
            // Let the sheet load its notes and open the new note's row.
            for _ in 0 ..< 5 {
                view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
            }
            try capture(view, as: "\(name)-\(dark ? "dark" : "light").png")
        }
    }

    @Test
    func `the sheet renders every kind of row in light and dark`() async throws {
        let (env, model) = try await library()
        defer { withExtendedLifetime(env) {} }
        let host = try SectionNotesHost.library(
            model,
            id: SongID(#require(ULID(string: Self.songID))),
        )
        let notes = host.notes()
        #expect(notes.all.map(\.text) == [
            "Everyone sings", "Hold back, let the vocal breathe", "Big ending",
            "Watch Ravi for the stop",
        ])
        #expect(notes.all.map(\.needsPlacementCheck) == [false, false, true, false])
        try await Self.render(host, as: "sheet")
        // A new note opened from the repeat's band: forced stage only, with the hint.
        let plain = try SectionNotesHost.library(
            model,
            id: SongID(#require(ULID(string: Self.plainID))),
        )
        try await Self.render(plain, as: "sheet-new-note")
    }

    private static func capture(_ view: NSView, as name: String) throws {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = try #require(rep.cgImage)
        #expect(image.width >= 560)
        try DiagramSnapshotTests.writePNG(image, to: directory.appending(path: name))
    }

    /// `<repo>/.build/screenshots/section-notes`.
    static var directory: URL {
        DiagramSnapshotTests.screenshotDirectory
            .deletingLastPathComponent()
            .appending(path: "section-notes", directoryHint: .isDirectory)
    }
}
