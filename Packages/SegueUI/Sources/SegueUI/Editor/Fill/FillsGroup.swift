// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 12.1). The Walk-ups
// list's "Fills" group: each saved fill, opened in the fill editor, renamed or deleted.

import Editing
import Library
import MusicTheory
import SwiftUI

/// One saved fill in the Walk-ups list.
struct FillListItem: Identifiable, Equatable {
    var id: PartID
    /// Its name, else "Fill into Chorus 3".
    var title: String
    var hasName: Bool
    /// "Verse 1: C -> Chorus 1: D"; nil when it no longer matches the song.
    var span: String?
    /// "Every time", "Only Chorus #2", "Last time".
    var shows: String

    /// The song's fills, applied ones in written order, then those that no longer match.
    @MainActor
    static func items(_ song: FillSong) -> [Self] {
        let resolved = song.resolved
        var items: [Self] = []
        for applied in resolved.applied {
            guard let span = song.span(of: applied.part.id) else { continue }
            let chords = song.timeline.chords
            let start = "\(song.sectionTitle(ofChord: span.lowerBound)): "
                + song.transform.display(ChordToken(parsing: chords[span.lowerBound].token))
            let end = "\(song.sectionTitle(ofChord: span.upperBound)): "
                + song.transform.display(ChordToken(parsing: chords[span.upperBound].token))
            items.append(Self(
                id: applied.part.id,
                title: applied.part.name
                    ?? "Fill into \(song.sectionTitle(ofChord: span.upperBound))",
                hasName: applied.part.name != nil,
                span: "\(start) \u{2192} \(end)",
                shows: shows(applied.part.passes),
            ))
        }
        for part in resolved.unmatched {
            items.append(Self(
                id: part.id,
                title: part.name ?? "Fill on \(part.span.spanBass.joined(separator: " "))",
                hasName: part.name != nil,
                span: nil,
                shows: shows(part.passes),
            ))
        }
        return items
    }

    static func shows(_ passes: PassFilter) -> String {
        switch passes {
        case .all: "Every time"
        case .last: "Last time"
        case let .only(plays):
            "Only #" + plays.sorted().map(String.init).joined(separator: ", #")
        }
    }
}

/// The Walk-ups list's "Fills" group (P8-7 12.1): each saved fill with its span and "Shows
/// on", opened in the fill editor, renamed in place or deleted; one that no longer matches
/// the song is listed with Remove.
struct FillsGroup: View {
    let source: WalkUpsSource
    @State private var editing: FillEditorModel?
    @State private var renaming: PartID?
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool
    @State private var windowSize: CGSize?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILLS", bundle: #bundle)
                .font(SchibstedGrotesk.bold.font(size: 11))
                .tracking(0.88)
                .foregroundStyle(Theme.color.muted)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(source.fills.enumerated()), id: \.element.id) { index, item in
                row(item)
                    .accessibilityIdentifier(AccessibilityID.walkUpsFill(index))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.walkUpsFills)
        .windowContentSize($windowSize)
        .sheet(item: $editing) { model in
            FillEditorSheet(
                model: model,
                onClose: { forGig in source.fillClosed(model, forGig) },
                windowSize: windowSize,
            )
        }
    }

    private func row(_ item: FillListItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if renaming == item.id {
                    TextField(uiString("Name"), text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit { commitRename(item) }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused {
                                commitRename(item)
                            }
                        }
                        .frame(maxWidth: 240)
                } else {
                    Text(item.title)
                        .font(SchibstedGrotesk.bold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                }
                Text(item.span.map { "\($0) \u{00B7} \(item.shows)" }
                    ?? uiString("No longer matches this song"))
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if item.span != nil {
                Button(uiString("Rename")) {
                    draftName = item.hasName ? item.title : ""
                    renaming = item.id
                    nameFocused = true
                }
                .buttonStyle(.segueSecondary)
                .controlSize(.small)
                .disabled(source.readOnlyHelp != nil)
                Button(uiString("Edit\u{2026}")) { editing = source.openFill(item.id) }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .disabled(source.readOnlyHelp != nil)
                    .accessibilityLabel(uiString("Edit \(item.title)"))
            }
            deleteButton(item)
        }
    }

    /// Remove (a saved fill) or Delete (one placed on a span).
    private func deleteButton(_ item: FillListItem) -> some View {
        Button(item.span == nil ? uiString("Remove") : uiString("Delete")) {
            source.deleteFills([item.id])
        }
        .buttonStyle(.segueSecondary)
        .controlSize(.small)
        .disabled(source.readOnlyHelp != nil)
        .accessibilityLabel(item.span == nil
            ? uiString("Remove \(item.title)") : uiString("Delete \(item.title)"))
    }

    private func commitRename(_ item: FillListItem) {
        guard renaming == item.id else { return }
        renaming = nil
        source.renameFill(item.id, draftName)
    }
}
