#if os(macOS)
    import AppKit
    import Editing

    /// The section band's note badge (P3-13): a click on it opens the section notes sheet on
    /// that section; VoiceOver hears the count and gets a "Section Notes" action.
    extension VisualEditorController {
        /// The section header whose note badge is under `point`, if any (text view
        /// coordinates). The badge is drawn only with notes, at the cap's trailing end.
        func noteBadgeHit(_ point: CGPoint, band index: Int) -> BlockPath? {
            guard bands.bands.indices.contains(index),
                  let path = bands.bands[index].sectionPath,
                  let frame = bandFrame(index), frame.topVisible
            else { return nil }
            let count = sectionNoteCount(path)
            guard count > 0 else { return nil }
            let width = ("\(count)" as NSString)
                .size(withAttributes: [.font: SectionBandStyle.capFont]).width + 18
            let badge = CGRect(
                x: frame.rect.maxX - 8 - width,
                y: frame.rect.minY,
                width: width + 8,
                height: SectionBandStyle.capHeight + 2,
            )
            return badge.contains(point) ? path : nil
        }

        /// ", 2 notes" for the band's accessibility value; empty without notes.
        func sectionNotesValue(forSectionAt path: BlockPath) -> String {
            let count = sectionNoteCount(path)
            return switch count {
            case 0: ""
            case 1: ", 1 note"
            default: ", \(count) notes"
            }
        }

        func sectionNotesAction(_ path: BlockPath) -> NSAccessibilityCustomAction {
            NSAccessibilityCustomAction(name: "Section Notes") { [weak self] in
                self?.model.showSectionNotes(forSectionAt: path)
                return self != nil
            }
        }
    }
#endif
