// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.1, 12.8). The
// span in a preview: chord units in it tinted `cue` with an underline, the "Create Bass
// Fill..." capsule under the landing, the same item in the units' context menu, and
// VoiceOver's "Start fill here" / "End fill here" actions.

import Editing
import Library
import SwiftUI

/// What a preview's chord units can do with a span, injected by its owner (the editor, the
/// library). The stage never injects one.
struct ChordSpanActions {
    let selection: ChordSpanSelection
    /// Makes the selection's lookup follow the chart as rendered now (before a click).
    let refresh: @MainActor () -> Void
    /// False during a gig: nothing opens.
    let isEnabled: Bool
    /// Set for a song that cannot take a fill yet (unsaved, or from a newer Segue).
    let disabledHelp: String?
    /// Opens the fill editor on a span.
    let open: @MainActor (ClosedRange<Int>) -> Void

    /// The timeline index of a chord unit.
    @MainActor
    func index(line: BlockPath, chord: RenderChord) -> Int? {
        refresh()
        return selection.index(line: line, offset: chord.offset)
    }

    /// A click on a unit: shift extends the span silently (returns true), a plain click
    /// anchors it (the caller still plays the chord).
    @MainActor
    @discardableResult
    func click(line: BlockPath, chord: RenderChord, extending: Bool) -> Bool {
        guard let index = index(line: line, chord: chord) else { return false }
        if extending {
            selection.extend(to: index)
            return true
        }
        selection.setAnchor(index)
        return false
    }

    /// Opens the editor on the span, when it can take a fill.
    @MainActor
    func openSpan() {
        guard isEnabled, disabledHelp == nil, let span = selection.span,
              selection.problem == nil
        else { return }
        open(span)
    }
}

extension EnvironmentValues {
    @Entry var chordSpan: ChordSpanActions?
}

/// A chord unit inside the span: a `cue` tint, an underline joining the run, and the
/// context menu item; the landing also carries the capsule below its line.
struct ChordUnitSpanMark: ViewModifier {
    let index: Int?
    @Environment(\.chordSpan) private var span

    func body(content: Content) -> some View {
        if let span, let index, let place = span.selection.place(of: index) {
            content
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.color.cue.opacity(0.16))
                        .padding(.horizontal, -3)
                        .padding(.vertical, -1),
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.color.cue)
                        .frame(height: 1.5)
                        .padding(.horizontal, -3)
                        .offset(y: 2)
                        .accessibilityHidden(true)
                }
                .contextMenu {
                    Button(span.selection.actionTitle) { span.openSpan() }
                        .disabled(!span.isEnabled || span.disabledHelp != nil
                            || span.selection.problem != nil)
                    Button("Clear Selection") { span.selection.clear() }
                }
                .accessibilityIdentifier(
                    place.place == 1 ? AccessibilityID.fillSpanUnit : "",
                )
        } else {
            content
        }
    }
}

/// The capsule's row under the landing's line in a preview.
struct FillSpanCapsuleRow: View {
    @Environment(\.chordSpan) private var span

    var body: some View {
        if let span {
            FillSpanCapsule(actions: span)
                .padding(.bottom, 4)
        }
    }
}

/// The floating "Create Bass Fill..." capsule (`segue.fill.create`), or the reason the span
/// cannot take a fill.
struct FillSpanCapsule: View {
    let actions: ChordSpanActions

    var body: some View {
        let selection = actions.selection
        Group {
            if let problem = selection.problem {
                Text(problem.reason)
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(capsule)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(problem.reason)
            } else {
                Button(action: actions.openSpan) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 11, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(selection.actionTitle)
                            .font(SchibstedGrotesk.bold.font(size: 12))
                    }
                    .foregroundStyle(Theme.color.ground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.color.ink))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!actions.isEnabled || actions.disabledHelp != nil)
                .opacity(actions.isEnabled && actions.disabledHelp == nil ? 1 : 0.5)
                .help(actions.disabledHelp ?? (actions.isEnabled
                        ? "Make a bass fill over these chords (\u{2325}\u{2318}F)"
                        : SoundGate.offHelp))
                .accessibilityLabel(spoken)
            }
        }
        .fixedSize()
        .accessibilityIdentifier(AccessibilityID.fillCreate)
    }

    private var capsule: some View {
        ZStack {
            Capsule().fill(Theme.color.surfaceAlt)
            Capsule().inset(by: 0.5).stroke(Theme.color.line, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }

    /// "Create bass fill from E to A".
    private var spoken: String {
        let selection = actions.selection
        guard let span = selection.span else { return "Create bass fill" }
        let verb = selection.existing == nil ? "Create" : "Edit"
        return "\(verb) bass fill from \(selection.name(of: span.lowerBound)) to "
            + selection.name(of: span.upperBound)
    }
}

/// VoiceOver's span selection on a line: "Start fill at G" and "End fill at C" per chord
/// in the actions rotor, so shift-click is never required.
struct ChordSpanActionsModifier: ViewModifier {
    let line: BlockPath
    let tokens: [LyricToken]
    @Environment(\.chordSpan) private var span

    func body(content: Content) -> some View {
        let chords = tokens.compactMap { token -> SpanChord? in
            guard let source = token.source, source.kind == .chord, let text = token.chord
            else { return nil }
            return SpanChord(
                id: token.id,
                spoken: LyricLineView.spokenChord(text, detail: token.detail),
                chord: source,
            )
        }
        if let span, !chords.isEmpty {
            content.accessibilityActions {
                ForEach(chords) { item in
                    let spoken = item.spoken
                    let chord = item.chord
                    Button("Start fill at \(spoken)") {
                        if let index = span.index(line: line, chord: chord) {
                            span.selection.start(at: index)
                        }
                    }
                    Button("End fill at \(spoken)") {
                        if let index = span.index(line: line, chord: chord) {
                            span.selection.finish(at: index)
                            AccessibilityNotification.Announcement(
                                span.selection.problem?.reason
                                    ?? "Fill span selected. \(span.selection.actionTitle)",
                            ).post()
                        }
                    }
                }
                if span.selection.span != nil, span.selection.problem == nil {
                    Button(span.selection.actionTitle) { span.openSpan() }
                }
            }
        } else {
            content
        }
    }
}

/// Esc clears the fill span while one is selected.
/// A click on empty space around the chart clears it too (a click on lyrics or chords goes to
/// them, never here).
struct SpanEscape: View {
    let selection: ChordSpanSelection

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
            .overlay {
                if selection.span != nil, !selection.sourceHasFocus {
                    Button("Clear Fill Span") { selection.clear() }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct SpanChord: Identifiable {
    var id: Int
    var spoken: String
    var chord: RenderChord
}

extension LyricLineView {
    /// `token`'s chord in the song's timeline, for the fill span.
    func spanIndex(_ token: LyricToken) -> Int? {
        guard let span, let source = token.source, source.kind == .chord else { return nil }
        return span.selection.index(line: line.path, offset: source.offset)
    }

    /// "in fill span, 2 of 3" for a chord inside the span.
    func spanPlace(_ token: LyricToken) -> String? {
        guard let span, let index = spanIndex(token),
              let place = span.selection.place(of: index)
        else { return nil }
        return "in fill span, \(place.place) of \(place.count)"
    }
}

extension SongSheetView {
    /// The line holding the span's landing chord.
    var capsuleLine: BlockPath? {
        guard let span, let landing = span.selection.span?.upperBound,
              span.selection.timeline.chords.indices.contains(landing)
        else { return nil }
        return span.selection.timeline.chords[landing].line
    }
}
