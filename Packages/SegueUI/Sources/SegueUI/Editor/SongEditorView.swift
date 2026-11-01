#if os(macOS)
    import Diagrams
    import Editing
    import SwiftUI
    import TipKit

    /// The song editor (docs/decisions.md, "Key screen layouts": layout b). Visual canvas with
    /// chord pills over syllables and a chord palette, or text mode (ChordPro source beside
    /// a live preview); a display bar for transpose / capo / Nashville / diagrams; a status
    /// bar. Both modes edit one source with one undo stack.
    struct SongEditorView: View {
        @Environment(\.openGuide) private var openGuide
        @Bindable var model: SongEditorViewModel
        /// "Done": save now and close the editor.
        var onDone: () -> Void
        @State private var customizing: ShapeCustomization?

        var body: some View {
            VStack(spacing: 0) {
                EditorTopBar(model: model)
                EditorSongStrip(model: model)
                if !model.flaggedDefines.isEmpty {
                    FlaggedDefinesBanner(model: model)
                }
                if model.editorMode == .visual {
                    ChordPaletteBar(model: model)
                    TipView(MoveChordTip()) { action in
                        GuideTipAction.handle(
                            action,
                            page: MoveChordTip.guidePage,
                            openGuide: openGuide,
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let playAlong = model.playAlong, playAlong.isOpen {
                    PlayAlongBar(model: playAlong)
                }
                EditorStatusBar(model: model)
            }
            .background(Theme.color.ground)
            .navigationTitle(model.title)
            .navigationSubtitle(model.saveState.text)
            // The window's edited dot shows a change still waiting for its autosave.
            .background(WindowDocumentEdited(isEdited: model.hasUnsavedChanges))
            .overlay(alignment: .topLeading) {
                if UITesting.isActive {
                    // The subtitle for the E2E suite only (VoiceOver reads the window's own
                    // subtitle). SwiftUI drops the value of an empty element; the label
                    // carries it.
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(model.saveState.text)
                        .accessibilityIdentifier(AccessibilityID.editorSaveStatus)
                }
            }
            .toolbar { toolbar }
            .sheet(item: $customizing) { target in
                ShapeEditorView(
                    chordName: target.chordName,
                    instrument: target.instrument,
                    tuning: model.tuning,
                    initialGuitar: target.diagram.guitar?.shape,
                    initialPiano: target.diagram.piano,
                    onSave: { definition in
                        customizing = nil
                        model.saveDefine(definition)
                    },
                    onCancel: { customizing = nil },
                )
            }
            .sectionNotesSheet(for: model)
            .fillEditorSheet(
                model.fillEditor,
                set: { model.fillEditor = $0 },
                closed: { sheet, forGig in model.fillEditorClosed(sheet, forGig: forGig) },
                note: Binding(get: { model.fillNote }, set: { model.fillNote = $0 }),
            )
            .onChange(of: model.renderModel) { feedPlayAlong() }
            .onChange(of: model.playAlong?.isOpen) { feedPlayAlong() }
            // Closing the editor (or switching song) stops play-along.
            .onDisappear { model.playAlong?.stop() }
        }

        /// The open bar follows the song as rendered (an edit, a timing write, the options).
        private func feedPlayAlong() {
            guard let playAlong = model.playAlong, playAlong.isOpen else { return }
            playAlong.update(model.playAlongSource)
        }

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                EditorModePicker(model: model)
            }
            .sharedBackgroundVisibility(.hidden)
            // The detail column's toolbar packs items at its leading edge; the flexible
            // spacer pushes the actions to the trailing end, where macOS puts them.
            ToolbarSpacer(.flexible)
            if let playAlong = model.playAlong {
                ToolbarItem(placement: .automatic) {
                    PlayAlongToggle(model: playAlong)
                }
            }
            ToolbarItem(placement: .automatic) {
                // Edits save themselves (R17); Done only closes the editor after a last
                // save. No Esc shortcut: Esc belongs to the editor (completion, chord
                // selection, palette).
                Button("Done", action: onDone)
                    .buttonStyle(.seguePrimary)
                    .controlSize(.regular)
                    .help("Save and close the editor")
                    .accessibilityIdentifier(AccessibilityID.editorDone)
                    // Without the shared glass capsule the toolbar gives no trailing inset.
                    .padding(.trailing, 6)
            }
            .sharedBackgroundVisibility(.hidden)
        }

        @ViewBuilder private var content: some View {
            switch model.editorMode {
            case .text:
                GeometryReader { proxy in
                    if proxy.size.width >= 860 {
                        HStack(spacing: 0) {
                            source
                            Rectangle().fill(Theme.color.line).frame(width: 1)
                            preview
                        }
                    } else {
                        VStack(spacing: 0) {
                            source
                            Hairline()
                            preview
                        }
                    }
                }
            case .visual:
                VStack(spacing: 0) {
                    VisualEditorRepresentable(controller: model.visualEditor)
                    // Diagrams exist only with the song's strip or the bassist's fretboard
                    // (P8-4b section 7.2) on.
                    if !model.diagrams.isEmpty {
                        diagramStrip(model.diagrams)
                    }
                }
            }
        }

        private var source: some View {
            ZStack(alignment: .topLeading) {
                SourceEditorRepresentable(controller: model.sourceEditor)
                if model.isEmpty {
                    Text(SongEditorViewModel.placeholder)
                        .font(.system(size: 14, design: .monospaced))
                        .lineSpacing(EditorStyle.sourceLineHeight - 17)
                        .foregroundStyle(Theme.color.muted.opacity(0.6))
                        // Matches the text origin: gutter + line fragment padding, top inset.
                        .padding(.leading, SourceTextView.gutterWidth + 5)
                        .padding(.top, 23)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(Theme.color.surfaceAlt.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var preview: some View {
            // Its own view, so only the preview depends on `renderModel`.
            // The strip is pinned under the scrolling page, so it stays in view whatever
            // the pane's height (the controls above leave a short one at the default size).
            VStack(spacing: 0) {
                EditorPreview(model: model, onCustomize: customize)
                    .environment(\.walkUpPicking, model.walkUpPicking)
                    .environment(\.walkUpAudition, model.walkUpAudition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.diagrams.isEmpty {
                    diagramStrip(model.diagrams)
                }
            }
            .background(Theme.color.ground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.editorPreview)
        }

        private func diagramStrip(_ diagrams: [RenderDiagram]) -> some View {
            ScrollView(.horizontal) {
                DiagramStrip(
                    diagrams: diagrams,
                    instrument: model.options.instrument,
                    tuning: model.tuning,
                    size: .compact,
                    onCustomize: customize,
                )
                .environment(\.chordHearing, model.chordHearing)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Hairline() }
        }

        private func customize(_ diagram: RenderDiagram) {
            guard let name = model.sourceChordName(forDiagram: diagram) else {
                model.errorMessage = "Set the view back to +0 (Shapes) to draw a custom shape "
                    + "for a chord as written."
                return
            }
            customizing = ShapeCustomization(
                chordName: name,
                instrument: model.options.instrument,
                diagram: diagram,
            )
        }
    }

    /// The live preview beside the source (text mode).
    private struct EditorPreview: View {
        let model: SongEditorViewModel
        let onCustomize: (RenderDiagram) -> Void

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    if let renderModel = model.renderModel {
                        SongPageView(
                            model: renderModel,
                            selectable: false,
                            onCustomize: onCustomize,
                            keyChanges: model.keyChangeSuggestions(renderModel),
                            showsDiagrams: false,
                        )
                        .environment(\.chordHearing, model.chordHearing)
                        .environment(\.chordSpan, model.chordSpanActions)
                        .environment(\.chartDirectives, ChartDirectiveActions(model: model))
                        .environment(\.playAlongCue, model.playAlong?.cue)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 24)
                        // A click off the chords (or Esc) clears a fill span (P8-7 12.1).
                        .background(SpanEscape(selection: model.spanSelection))
                    }
                }
                .followsPlayAlong(model.playAlong?.cue, proxy: proxy)
            }
        }
    }

    /// The Text / Visual switch (mockup: `surfaceAlt` track, 14 / 600).
    private struct EditorModePicker: View {
        let model: SongEditorViewModel

        var body: some View {
            SegmentedGroup {
                SegmentButton(
                    title: "Text",
                    isOn: model.editorMode == .text,
                    fontSize: 14,
                    horizontalPadding: 14,
                    verticalPadding: 5,
                ) { model.setEditorMode(.text) }
                    .accessibilityIdentifier(AccessibilityID.editorModeText)
                    .help("Edit the ChordPro source")
                SegmentButton(
                    title: "Visual",
                    isOn: model.editorMode == .visual,
                    fontSize: 14,
                    horizontalPadding: 14,
                    verticalPadding: 5,
                ) { model.setEditorMode(.visual) }
                    .accessibilityIdentifier(AccessibilityID.editorModeVisual)
                    .help("Place chords over the lyrics")
            }
            .fixedSize()
        }
    }

    /// A diagram being customised in the shape editor.
    private struct ShapeCustomization: Identifiable {
        var chordName: String
        var instrument: Instrument
        var diagram: RenderDiagram

        var id: String {
            chordName
        }
    }
#endif
