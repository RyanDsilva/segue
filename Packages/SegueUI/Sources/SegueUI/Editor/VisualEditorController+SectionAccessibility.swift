#if os(macOS)
    import AppKit
    import ChordPro
    import Editing

    /// The section band for VoiceOver and Voice Control (P3-11): one element per band on
    /// screen, with every band action as a custom action, so nothing needs a drag.
    extension VisualEditorController {
        // MARK: Accessibility

        /// One element per band on screen, with every band action (no drag needed).
        func bandAccessibilityElements(
            parent: Any,
            screenFrame: (CGRect) -> CGRect,
        ) -> [Any] {
            bandFrames(in: textView.visibleRect).map { frame in
                let band = bands.bands[frame.band]
                let element = BandAccessibilityElement()
                element.setAccessibilityRole(.button)
                element.setAccessibilityParent(parent)
                // Only the part on screen, so a click on the element lands on the band.
                let shown = frame.rect.intersection(textView.visibleRect)
                element.setAccessibilityFrame(screenFrame(shown))
                element.press = { [weak self] in
                    guard let self, bands.bands.indices.contains(frame.band) else { return false }
                    lineSelection = bands.bands[frame.band].paragraphs
                    textView.window?.makeFirstResponder(textView)
                    redrawOverlay()
                    return true
                }
                let lines = band.paragraphs.count(where: { projection.paragraphs[$0].isLyrics })
                switch band.kind {
                case let .section(path, kind, _, _):
                    element.setAccessibilityIdentifier(AccessibilityID.sectionBand)
                    element.setAccessibilityLabel(band.title)
                    let count = "\(lines) \(lines == 1 ? "line" : "lines")"
                    element.setAccessibilityValue(
                        "\(SectionLabels.displayName(kind)), \(count)"
                            + sectionNotesValue(forSectionAt: path),
                    )
                    element.setAccessibilityCustomActions(
                        sectionActions(band, path: path) + [sectionNotesAction(path)],
                    )
                case .slot:
                    element.setAccessibilityIdentifier(AccessibilityID.sectionBandSlot)
                    element.setAccessibilityLabel("Lines outside a section")
                    element.setAccessibilityValue("\(lines) \(lines == 1 ? "line" : "lines")")
                    element.setAccessibilityCustomActions(sectionOffers.map { chip in
                        NSAccessibilityCustomAction(name: "Make \(chip.title)") { [weak self] in
                            guard let self else { return false }
                            lineSelection = band.paragraphs
                            return applySection(chip.kind)
                        }
                    })
                case .repeatRef:
                    element.setAccessibilityIdentifier(AccessibilityID.sectionBandRepeat)
                    element.setAccessibilityLabel("Repeat \(band.title)")
                }
                return element
            }
        }

        private func sectionActions(
            _ band: SectionBand,
            path: BlockPath,
        ) -> [NSAccessibilityCustomAction] {
            var actions: [NSAccessibilityCustomAction] = [
                NSAccessibilityCustomAction(name: "Rename") { [weak self] in
                    guard let self,
                          let index = bands.bands.firstIndex(of: band) else { return false }
                    beginRename(band: index)
                    return true
                },
            ]
            actions += sectionOffers.map { chip in
                NSAccessibilityCustomAction(name: "Change to \(chip.title)") { [weak self] in
                    self?.model.perform(.changeSectionKind(path, to: chip.kind)) ?? false
                }
            }
            let edges: [(name: String, move: EdgeMove)] = [
                ("Extend Up One Line", EdgeMove(edge: .top, delta: -1)),
                ("Shrink From Top", EdgeMove(edge: .top, delta: 1)),
                ("Extend Down One Line", EdgeMove(edge: .bottom, delta: 1)),
                ("Shrink From Bottom", EdgeMove(edge: .bottom, delta: -1)),
            ]
            actions += edges.map { name, move in
                NSAccessibilityCustomAction(name: name) { [weak self] in
                    self?.nudgeEdge(of: band, edge: move.edge, by: move.delta) ?? false
                }
            }
            actions.append(NSAccessibilityCustomAction(name: "Unwrap") { [weak self] in
                self?.model.perform(.unwrapSection(path)) ?? false
            })
            let lineCount = bands.paths[band.paragraphs].count(where: { $0?.block == path.block })
            if lineCount > 1 {
                actions.append(NSAccessibilityCustomAction(name: "Split in Half") { [weak self] in
                    guard let self else { return false }
                    let items = band.paragraphs.compactMap { self.bands.paths[$0] }
                        .filter { $0.block == path.block && ($0.item ?? 0) > 0 }
                    guard !items.isEmpty else { return false }
                    return model.perform(.splitSection(path, atLine: items[(items.count - 1) / 2]))
                })
            }
            if let next = bands.sections(after: band).first {
                actions.append(NSAccessibilityCustomAction(name: "Merge with Next") { [weak self] in
                    self?.merge(band, with: next)
                    return true
                })
            }
            return actions
        }

        /// Moves an edge to the next or previous canvas line that has a source line.
        func nudgeEdge(of band: SectionBand, edge: SectionEdge, by delta: Int) -> Bool {
            guard let path = band.sectionPath else { return false }
            var index = edge == .top ? band.paragraphs.lowerBound : band.paragraphs.upperBound
            repeat {
                index += delta
            } while bands.paths.indices.contains(index) && bands.paths[index] == nil
            guard bands.paths.indices.contains(index), let line = bands.paths[index] else {
                return false
            }
            return model.perform(.moveSectionEdge(path, edge: edge, toLine: line))
        }
    }
#endif
