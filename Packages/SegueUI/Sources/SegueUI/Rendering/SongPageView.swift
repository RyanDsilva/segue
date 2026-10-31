import Diagrams
import Editing
import Library
import SwiftUI

/// A rendered song on paper: title, artist and performance line, then the body, then the
/// diagram strip. Used by the song detail pane and the editor preview; both honour the
/// song's transpose / capo / Nashville / diagram toggles through the `RenderModel`.
struct SongPageView: View {
    let model: RenderModel
    /// Shown when the song has no title yet.
    var fallbackTitle = "Untitled"
    /// Text selection costs a lot on long songs; the live preview turns it off.
    var selectable = true
    /// Called when a diagram is picked to customise (editor only).
    var onCustomize: ((RenderDiagram) -> Void)?
    /// The editor's "Looks like a key change" chips (P8-7 section 6.2).
    var keyChanges: [KeyChangeSuggestion] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.font.title)
                    .tracking(Theme.tracking.title * 28)
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.songTitle)
                let subtitle = SongSummary.subtitle(model)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityIdentifier(AccessibilityID.sheetKey)
                }
            }
            if model.sections.isEmpty {
                Text("No lyrics yet.")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
            } else {
                SongSheetView(sections: model.sections, style: .preview, keyChanges: keyChanges)
            }
            if !model.diagrams.isEmpty {
                StripSnapshot(
                    diagrams: model.diagrams,
                    instrument: model.transform.options.instrument,
                    tuning: model.tuning,
                    onCustomize: onCustomize,
                )
                .equatable()
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SelectableText(isOn: selectable))
    }

    private var title: String {
        let title = model.header.title?.trimmingCharacters(in: .whitespaces) ?? ""
        return title.isEmpty ? fallbackTitle : title
    }
}

/// The diagram strip, redrawn only when its diagrams change (not on every keystroke).
struct StripSnapshot: View, @MainActor Equatable {
    let diagrams: [RenderDiagram]
    let instrument: Instrument
    let tuning: Tuning
    var onCustomize: ((RenderDiagram) -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.diagrams == rhs.diagrams && lhs.instrument == rhs.instrument
            && lhs.tuning == rhs.tuning
    }

    var body: some View {
        DiagramStrip(
            diagrams: diagrams,
            instrument: instrument,
            tuning: tuning,
            size: .compact,
            onCustomize: onCustomize,
        )
    }
}

private struct SelectableText: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}
