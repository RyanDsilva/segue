#if os(macOS)
    import AppKit
    import ChordPro
    import Editing
    import SwiftUI

    public extension AccessibilityID {
        /// A section band in the visual editor's lane (label = the section's label).
        static let sectionBand = "segue.editor.sectionBand"
        /// Lines outside any section (an empty slot in the lane).
        static let sectionBandSlot = "segue.editor.sectionBand.slot"
        /// A `{chorus}` repeat outside any section.
        static let sectionBandRepeat = "segue.editor.sectionBand.repeat"
        /// The floating chip bar shown while lines are selected, and its chips
        /// (`segue.editor.sectionBand.chip.verse`, ...).
        static let sectionBandChipBar = "segue.editor.sectionBand.chipBar"
        static let sectionBandChip = "segue.editor.sectionBand.chip"
        static let sectionBandRenameField = "segue.editor.sectionBand.renameField"
        static let sectionBandCustomField = "segue.editor.sectionBand.customField"
    }

    /// A kind the band can make: its key (quick chips only), name and `SectionKind`.
    struct SectionChip: Identifiable, Equatable {
        var key: String
        var title: String
        var kind: SectionKind

        var id: String {
            title
        }

        /// V / C / B / I: the keys and the first chips.
        static let quick = [
            Self(key: "v", title: "Verse", kind: .verse),
            Self(key: "c", title: "Chorus", kind: .chorus),
            Self(key: "b", title: "Bridge", kind: .bridge),
            Self(key: "i", title: "Intro", kind: .custom("intro")),
        ]

        /// Every chip kind (Tab lives in the section menu only).
        static let outro = Self(key: "", title: "Outro", kind: .custom("outro"))
        static let all = quick + [outro]

        /// The kind for a typed name: a built-in kind when it names one, else a custom kind
        /// spelled as a directive (`Pre-Chorus` -> `start_of_pre-chorus`).
        static func kind(named name: String) -> SectionKind {
            let spelled = name.lowercased()
                .split(whereSeparator: \.isWhitespace).joined(separator: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            switch spelled {
            case "verse": return .verse
            case "chorus": return .chorus
            case "bridge": return .bridge
            case "tab": return .tab
            default: return .custom(spelled.isEmpty ? "section" : spelled)
            }
        }
    }

    /// The chip bar: "4 lines", V Verse, C Chorus, B Bridge, I Intro | Outro, Custom...
    struct SectionChipBar: View {
        var lines: Int
        var apply: (SectionKind) -> Void
        var custom: () -> Void

        var body: some View {
            HStack(spacing: 6) {
                Text("\(lines) \(lines == 1 ? "line" : "lines")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                ForEach(SectionChip.quick) { chip in
                    chipButton(chip, showsKey: true)
                }
                Divider().frame(height: 18)
                chipButton(SectionChip.outro, showsKey: false)
                Button("Custom...", action: custom)
                    .buttonStyle(SectionChipStyle(color: nil))
                    .accessibilityIdentifier("\(AccessibilityID.sectionBandChip).custom")
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor)),
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.sectionBandChipBar)
            .accessibilityLabel("Make a section")
        }

        private func chipButton(_ chip: SectionChip, showsKey: Bool) -> some View {
            Button {
                apply(chip.kind)
            } label: {
                HStack(spacing: 5) {
                    if showsKey {
                        Text(chip.key.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Color(nsColor: .separatorColor)),
                            )
                    }
                    Text(chip.title)
                }
            }
            .buttonStyle(SectionChipStyle(color: Color(nsColor: SectionBandStyle
                    .color(for: chip.kind))))
            .accessibilityIdentifier(
                "\(AccessibilityID.sectionBandChip).\(chip.title.lowercased())",
            )
            .accessibilityLabel(chip.title)
            .accessibilityHint(showsKey ? "Shortcut \(chip.key.uppercased())" : "")
        }
    }

    /// A chip: a kind-coloured square, then the label, in an outlined capsule.
    private struct SectionChipStyle: ButtonStyle {
        var color: Color?

        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) {
                if let color {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                }
                configuration.label
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color == nil ? .secondary : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor)
                        .opacity(configuration.isPressed ? 0.6 : 1)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)),
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    /// The chip bar's host view, placed by the canvas under the selected lines.
    @MainActor
    final class SectionChipBarHost {
        private weak var controller: VisualEditorController?
        private var host: NSHostingView<SectionChipBar>?

        init(controller: VisualEditorController) {
            self.controller = controller
        }

        /// Shows the bar for `lines` selected lines with its top-left at `origin` (container
        /// coordinates, flipped), or hides it.
        func show(lines: Int?, at origin: CGPoint, in container: NSView) {
            guard let lines, let controller else {
                host?.isHidden = true
                return
            }
            let bar = SectionChipBar(
                lines: lines,
                apply: { [weak controller] kind in controller?.applySection(kind) },
                custom: { [weak controller] in controller?.applyCustomSection() },
            )
            let view: NSHostingView<SectionChipBar>
            if let host {
                view = host
                view.rootView = bar
            } else {
                view = NSHostingView(rootView: bar)
                container.addSubview(view)
                host = view
            }
            view.isHidden = false
            let size = view.fittingSize
            // The container is not flipped: convert from the flipped top-left origin.
            let y = container.isFlipped ? origin.y : container.bounds.height - origin.y - size
                .height
            view.frame = CGRect(x: origin.x, y: y, width: size.width, height: size.height)
        }
    }

    /// The rename popover: one field, Return commits, Esc cancels.
    struct SectionRenameView: View {
        @State private var text: String
        @FocusState private var focused: Bool
        var onFinish: (String?) -> Void

        init(initial: String, onFinish: @escaping (String?) -> Void) {
            _text = State(initialValue: initial)
            self.onFinish = onFinish
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rename Section").font(.headline)
                TextField("Section label", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { onFinish(text) }
                    .accessibilityIdentifier(AccessibilityID.sectionBandRenameField)
            }
            .padding(12)
            .onAppear { focused = true }
            .onExitCommand { onFinish(nil) }
        }
    }

    // MARK: - Placement

    extension VisualEditorController {
        /// Shows the chip bar under the selected lines (above them near the bottom of the
        /// view), or hides it when nothing is selected.
        func updateChipBar() {
            guard let selection = activeLineSelection, bandGesture == nil,
                  let rows = rowsFrame(selection)
            else {
                chipBar.show(lines: nil, at: .zero, in: container)
                return
            }
            let lines = selection.count(where: { projection.paragraphs[$0].isLyrics })
            let below = textView.convert(
                CGPoint(x: laneX.lowerBound - 8, y: rows.maxY + 10),
                to: container.overlay,
            )
            let above = textView.convert(
                CGPoint(x: laneX.lowerBound - 8, y: rows.minY - 50),
                to: container.overlay,
            )
            let origin = below.y + 44 > container.overlay.bounds.height ? above : below
            chipBar.show(lines: max(lines, 1), at: origin, in: container)
        }
    }
#endif
