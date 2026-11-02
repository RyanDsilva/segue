#if os(macOS)
    import SetAssistant
    import Setlists
    import SwiftUI

    extension SetEntriesList {
        /// Row `entry`'s score, open state and lock toggle.
        func assistantCells(
            for entry: SetlistEntry,
            shown: Binding<SetlistItemID?>,
        ) -> EntryAssistant {
            EntryAssistant(
                breakdown: breakdowns[entry.itemId],
                isBreakdownShown: Self.breakdownShown(entry.itemId, shown: shown),
                isLocked: entry.locked,
                onToggleLock: setlist.readOnly != nil || entry.isBreak ? nil : {
                    Task { await model.toggleLock(entry.itemId, in: setlist.id) }
                },
            )
        }

        /// Whether row `item`'s score breakdown is open (one at a time).
        static func breakdownShown(
            _ item: SetlistItemID,
            shown: Binding<SetlistItemID?>,
        ) -> Binding<Bool> {
            Binding(
                get: { shown.wrappedValue == item },
                set: { isShown in
                    if isShown {
                        shown.wrappedValue = item
                    } else if shown.wrappedValue == item {
                        shown.wrappedValue = nil
                    }
                },
            )
        }

        /// Space opens (or closes) the focused row's score breakdown.
        func toggleFocusedBreakdown(_ shown: Binding<SetlistItemID?>) -> KeyPress.Result {
            guard let focus = model.arrangeSelection.focus, breakdowns[focus] != nil else {
                return .ignored
            }
            shown.wrappedValue = shown.wrappedValue == focus ? nil : focus
            return .handled
        }
    }

    /// What a set row shows of the assistant: its score (after a build) and its lock.
    struct EntryAssistant {
        var breakdown: ScoreBreakdown?
        var isBreakdownShown: Binding<Bool> = .constant(false)
        var isLocked = false
        /// Nil when the setlist is read-only.
        var onToggleLock: (() -> Void)?
        /// Replaces the lock's help (a medley's lock is on and disabled, P9-3 11).
        var lockHelp: String?
    }

    /// The score cell (after a build) and the lock button of a set row.
    struct EntryAssistantCells: View {
        let assistant: EntryAssistant
        let title: String
        let isHovered: Bool

        var body: some View {
            HStack(spacing: 8) {
                if let breakdown = assistant.breakdown {
                    EntryScoreCell(
                        title: title,
                        breakdown: breakdown,
                        isShown: assistant.isBreakdownShown,
                    )
                }
                EntryLockButton(
                    title: title,
                    isLocked: assistant.isLocked,
                    isHovered: isHovered,
                    onToggle: assistant.onToggleLock,
                    help: assistant.lockHelp,
                )
            }
        }
    }

    extension View {
        /// VoiceOver's Lock / Unlock and Show score breakdown on a set row.
        func entryAssistantActions(_ assistant: EntryAssistant) -> some View {
            accessibilityActions {
                if let toggle = assistant.onToggleLock {
                    Button(
                        assistant.isLocked ? uiString("Unlock") : uiString("Lock"),
                        action: toggle,
                    )
                }
                if assistant.breakdown != nil {
                    Button(uiString("Show score breakdown")) {
                        assistant.isBreakdownShown.wrappedValue = true
                    }
                }
            }
        }
    }

    /// A set row's score (P3-7): "2.95", dotted-underlined; hover, a click, Space on the
    /// selected row or VoiceOver's "Show score breakdown" opens the breakdown.
    struct EntryScoreCell: View {
        let title: String
        let breakdown: ScoreBreakdown
        @Binding var isShown: Bool

        var body: some View {
            Text(ScoreBreakdownView.format(breakdown.total, signed: false))
                .font(SchibstedGrotesk.semiBold.font(size: 13))
                .foregroundStyle(Theme.color.muted)
                .underline(true, pattern: .dot, color: Theme.color.lineStrong)
                .frame(width: 48, alignment: .trailing)
                .contentShape(Rectangle())
                .onHover { isShown = $0 }
                .onTapGesture { isShown.toggle() }
                .popover(isPresented: $isShown, arrowEdge: .leading) {
                    ScoreBreakdownView(title: title, breakdown: breakdown)
                }
                .help(uiString("Why this song: hover, or press Space on the selected row"))
                .accessibilityLabel(ScoreBreakdownView.spoken(breakdown))
                .accessibilityIdentifier(AccessibilityID.entryScore)
        }
    }

    /// The Rebuild lock of a set row (R115): shown on hover, always when locked.
    struct EntryLockButton: View {
        let title: String
        let isLocked: Bool
        let isHovered: Bool
        /// Nil when the setlist is read-only.
        let onToggle: (() -> Void)?
        var help: String?

        var body: some View {
            Button {
                onToggle?()
            } label: {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isLocked ? Theme.color.ink : Theme.color.muted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isLocked || (isHovered && onToggle != nil) ? 1 : 0)
            .disabled(onToggle == nil)
            .help(help ?? (isLocked ? uiString("Unlock: Rebuild may replace this song")
                    : "Lock: Rebuild keeps this song here"))
            .accessibilityLabel(isLocked ? uiString("Unlock \(title)") : uiString("Lock \(title)"))
            .accessibilityValue(isLocked ? uiString("Locked") : uiString("Unlocked"))
            .accessibilityIdentifier(AccessibilityID.entryLock)
        }
    }
#endif
