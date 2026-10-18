import AppKit
@testable import SegueUI
import Testing

/// The editor text views carry no test-only accessibility help (WS1 4.8b): VoiceOver would
/// read it aloud, and the E2E suite reads the input-settings report from its own
/// UITesting-only element instead. XCUITest on macOS exposes no help attribute, so the real
/// controllers are checked here.
@MainActor
struct EditorAccessibilityHelpTests {
    @Test
    func `source and visual editor text views have no accessibility help`() {
        #expect(Theme.registerFonts())
        let model = SongEditorViewModel(
            mode: .create,
            source: "{title: Help}\n{start_of_verse}\n[C]Dil ki [G]baat\n{end_of_verse}\n",
        ) { _ in throw CancellationError() }
        let source = model.sourceEditor.textView
        #expect(source.accessibilityHelp()?.isEmpty ?? true)
        model.setEditorMode(.visual)
        let visual = model.visualEditor.textView
        #expect(visual.accessibilityHelp()?.isEmpty ?? true)
    }
}
