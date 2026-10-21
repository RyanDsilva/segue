import AppKit
import Editing
import Foundation
import Library
@testable import SegueUI
import Services
import Support
import SwiftUI
import Testing

/// Section notes (P3-13) in process, over a temp library and the real parser, store and
/// editor: the library pane's toggle writes the `.cho` and the sidecar together and one
/// Undo restores both; the editor's toggle is one step on its own undo stack; the section
/// band's badge counts both kinds and opens the sheet on its section; the sheet renders.
@MainActor
struct SectionNotesUITests {
    private static let songID = "01JC0000000000000000000N01"
    private static let file = "songs/harbor-lights.cho"
    private static let sidecarFile = "songs/harbor-lights.segue.json"
    static let source = """
    {title: Harbor Lights}

    {start_of_verse}
    [G]Boats come home at [C]evening
    {end_of_verse}

    {start_of_chorus}
    {comment: Everyone sings}
    [C]Harbor [G]lights
    {end_of_chorus}

    """

    private struct Fixture {
        let env: TestEnvironment
        let model: LibraryViewModel
        let id: SongID
    }

    private func library(cues: String = "[]") async throws -> Fixture {
        let env = try TestEnvironment()
        try FileManager.default.createDirectory(
            at: env.libraryURL.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        try env.write(Self.source, to: Self.file)
        try env.write(
            #"{"schemaVersion": 3, "id": "\#(Self.songID)", "cues": \#(cues), "#
                + #""createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-01T10:00:00Z"}"#,
            to: Self.sidecarFile,
        )
        let model = try await env.openLibrary()
        let id = try SongID(#require(ULID(string: Self.songID)))
        return Fixture(env: env, model: model, id: id)
    }

    private func cues(_ env: TestEnvironment) throws -> [[String: Any]] {
        let data = try Data(env.read(Self.sidecarFile).utf8)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return json["cues"] as? [[String: Any]] ?? []
    }

    @Test
    func `the library toggle moves a note into the sidecar and one undo moves it back`(
    ) async throws {
        let fixture = try await library()
        let (env, model, id) = (fixture.env, fixture.model, fixture.id)
        let manager = UndoManager()
        manager.groupsByEvent = false
        model.undoManager = manager
        let note = try #require(SectionNotesHost.library(model, id: id).notes().all.first)
        #expect(!note.isStageOnly)

        manager.beginUndoGrouping()
        #expect(await model.editSectionNotes(id: id, .setStageOnly(note.id, true)) != nil)
        manager.endUndoGrouping()
        #expect(manager.undoActionName == "Show on Stage Only")
        #expect(try env.read(Self.file)
            == Self.source.replacingOccurrences(of: "{comment: Everyone sings}\n", with: ""))
        #expect(try cues(env).first?["text"] as? String == "Everyone sings")
        #expect(try cues(env).first?["section"] as? String == "Chorus")

        manager.undo()
        try await env.waitFor { (try? env.read(Self.file)) == Self.source ? true : nil }
        try await env.waitFor { (try? cues(env).isEmpty) == true ? true : nil }
    }

    private func editor(cues: [SongCue]) -> SongEditorViewModel {
        let id = SongID(ULID(
            timestamp: Date(timeIntervalSince1970: 0),
            randomness: Array(repeating: 1, count: 10),
        ))
        return SongEditorViewModel(
            mode: .edit(id),
            source: Self.source,
            cues: cues,
            persistCues: { _, _ in throw CancellationError() },
            save: { _ in throw CancellationError() },
        )
    }

    @Test
    func `the editor toggle is one step on its undo stack`() throws {
        let soft = SongCue(section: "Verse", text: "Soft")
        let model = editor(cues: [soft])
        _ = model.sourceEditor
        let manager = model.sourceEditor.undoManager
        manager.groupsByEvent = false
        let stage = try #require(model.sectionNotes.all.first { $0.isStageOnly })

        #expect(model.editSectionNotes(.setStageOnly(stage.id, false)) != nil)
        #expect(model.source.contains("{start_of_verse}\n{comment: Soft}\n[G]Boats"))
        #expect(model.cues.isEmpty)
        #expect(manager.undoActionName == "Show on Chart")

        manager.undo()
        #expect(model.source == Self.source)
        #expect(model.cues == [soft])
        manager.redo()
        #expect(model.cues.isEmpty)
        #expect(model.source.contains("{comment: Soft}"))
    }

    @Test
    func `the band badge counts chart and stage notes and opens the sheet on its section`() throws {
        #expect(Theme.registerFonts())
        let model = editor(cues: [SongCue(section: "Chorus", text: "Lights down")])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        _ = model.sourceEditor
        model.setEditorMode(.visual)
        let canvas = model.visualEditor
        canvas.container.frame = window.contentLayoutRect
        window.contentView = canvas.container
        window.layoutIfNeeded()
        canvas.didAttach()

        let chorusBand = try #require(canvas.bands.bands.firstIndex { $0.title == "Chorus" })
        let chorus = try #require(canvas.bands.bands[chorusBand].sectionPath)
        let verse = try #require(canvas.bands.bands.first { $0.title == "Verse" }?.sectionPath)
        #expect(canvas.sectionNoteCount(chorus) == 2)
        #expect(canvas.sectionNoteCount(verse) == 0)
        #expect(canvas.sectionNotesValue(forSectionAt: chorus) == ", 2 notes")

        // A click on the badge (the cap's trailing end) opens the sheet on the chorus.
        let frame = try #require(canvas.bandFrame(chorusBand))
        let badge = CGPoint(x: frame.rect.maxX - 12, y: frame.rect.minY + 8)
        #expect(canvas.noteBadgeHit(badge, band: chorusBand) == chorus)
        #expect(canvas.noteBadgeHit(
            CGPoint(x: frame.rect.minX + 4, y: badge.y),
            band: chorusBand,
        ) == nil)
        model.showSectionNotes(forSectionAt: chorus, entry: .badge)
        #expect(model.sectionNotesRequest?.group == "section:chorus")
        #expect(model.sectionNotesRequest?.entry == .badge)
        // The chorus occurs once: no placement, and the menu item names just the label.
        #expect(model.sectionNotesRequest?.placement == nil)
        #expect(model.addNoteTitle(forSectionAt: chorus) == "Add Note to Chorus...")
    }

    /// Chorus #1, Chorus #2 and a `{chorus}` repeat.
    static let repeated = """
    {title: Tide}

    {start_of_chorus}
    [C]Tide comes in
    {end_of_chorus}

    {start_of_chorus}
    [C]Tide goes out
    {end_of_chorus}

    {chorus}

    """

    @Test
    func `a band request presets its instance and the menu item names it`() throws {
        let model = SongEditorViewModel(
            mode: .edit(SongID(ULID(milliseconds: 0, randomness: Array(repeating: 2, count: 10)))),
            source: Self.repeated,
            cues: [],
            persistCues: { _, _ in throw CancellationError() },
            save: { _ in throw CancellationError() },
        )
        let group = try #require(model.sectionNotes.groups.first)
        let second = group.headers[1]
        #expect(model.addNoteTitle(forSectionAt: second) == "Add Note to Chorus #2...")
        model.showSectionNotes(forSectionAt: second, entry: .bandMenu, addNote: true)
        let request = try #require(model.sectionNotesRequest)
        #expect(request.group == group.id)
        #expect(request.placement == .instance(2))
        #expect(request.addsNote && request.entry == .bandMenu)
        // Without a band: Every time (R145 question 3), applied by the sheet's default.
        model.showSectionNotes(forSectionAt: nil)
        #expect(model.sectionNotesRequest?.placement == nil)
        #expect(group.defaultPlacement == .everyTime)

        // A note added with the request's placement lands in the second chorus.
        let change = try #require(model.editSectionNotes(
            .add(group: group.id, text: "Build", stageOnly: false, placement: request.placement),
            context: SectionNoteEditContext(entry: .bandMenu),
        ))
        #expect(model.source.contains("{start_of_chorus}\n{comment: Build}\n[C]Tide goes out"))
        #expect(try model.sectionNotes.note(#require(change.resultID))?.placement == .instance(2))
    }

    @Test
    func `note edits are recorded with their entry and a stale edit as an error code`(
    ) async throws {
        let fixture = try await library()
        let (env, model, id) = (fixture.env, fixture.model, fixture.id)
        let recording = RecordingLog(url: env.scratch.appending(path: "services.jsonl"))
        model.services = ServicesHub(
            factory: RecordingServicesFactory(log: recording),
            consent: ConsentState(analytics: .granted(.now), crashReports: .declined(.now)),
            throttle: AnalyticsThrottle(suiteName: env.suiteName, clock: env.clock),
        )
        let note = try #require(SectionNotesHost.library(model, id: id).notes().all.first)
        #expect(await model.editSectionNotes(id: id, .setStageOnly(note.id, true)) != nil)
        let signal = try #require(recording.entries().first {
            $0["name"] as? String == "Segue.Notes.edited"
        })
        let params = try #require(signal["params"] as? [String: String])
        #expect(params == [
            "segue.action": "toggle", "segue.kind": "stage", "segue.placement": "single",
            "segue.entry": "library", "segue.repeatHint": "false",
        ])
        // The chart note is gone now: an edit naming it fails and is counted.
        #expect(await model.editSectionNotes(id: id, .delete(note.id)) == nil)
        #expect(recording.entries().contains {
            $0["name"] as? String == "Segue.Error.occurred"
                && ($0["params"] as? [String: String])?["segue.code"] == "sectionNoteGone"
        })
    }

    @Test
    func `the sheet lists every group with its notes`() async throws {
        let fixture = try await library(cues: #"[{"section": "Bridge", "text": "Key change"}]"#)
        let host = SectionNotesHost.library(fixture.model, id: fixture.id)
        #expect(host.notes().groups.map(\.title) == ["Verse", "Chorus", "Bridge"])
        let view = NSHostingView(rootView: SectionNotesSheet(host: host, focus: "section:chorus"))
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 540)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width > 0)
    }
}
