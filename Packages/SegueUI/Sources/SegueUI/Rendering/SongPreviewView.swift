import ChordPro
import Editing
import SwiftUI

/// A `.cho` file as the Quick Look preview shows it (WS2b 4.7, B-20): the song page the app
/// draws (title, key and capo line, sections, chords over lyrics in the brand fonts), from
/// the file alone (Quick Look sees no sidecar), always in the light appearance. Long files
/// show their first `maxLines` lines and "…"; text that has no song body shows as plain text.
public struct SongPreviewView: View {
    /// Lines rendered at most.
    public static let maxLines = 400

    let model: RenderModel?
    let plainText: String

    public init(source: String) {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let text = lines.count > Self.maxLines
            ? lines.prefix(Self.maxLines).joined(separator: "\n") + "\n…"
            : source
        let (document, _) = ChordProParser.parse(text)
        let model = RenderModel(document: document, options: DisplayOptions())
        self.model = model.sections.isEmpty && model.header.title == nil ? nil : model
        plainText = text
    }

    public var body: some View {
        ScrollView {
            page
        }
        .background(Theme.color.ground)
        .environment(\.colorScheme, .light)
    }

    /// The page inside the scroll view (rendered on its own by the snapshot tests).
    var page: some View {
        Group {
            if let model {
                SongPageView(model: model, selectable: false)
            } else {
                Text(plainText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
    }
}

/// ChordPro text drawn as the song page, in the app's appearance, read-only and without the
/// diagram strip: the Personal build's Find Lyrics preview (P9-4 spec 6.4) shows a chart as
/// it will import.
public struct ChordProPageView: View {
    let model: RenderModel

    public init(chordPro: String) {
        let (document, _) = ChordProParser.parse(chordPro)
        model = RenderModel(document: document, options: DisplayOptions())
    }

    public var body: some View {
        SongPageView(model: model, selectable: false, showsDiagrams: false)
    }
}
