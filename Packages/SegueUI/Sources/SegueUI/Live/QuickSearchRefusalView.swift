#if os(macOS)
    import Shows
    import SwiftUI

    /// R102 in the search overlay: the song is already in the show. Says why, and for an
    /// upcoming song offers "Move to Next" (Return). Esc goes back to the results. It lives
    /// inside the overlay the performer opened, so the stage and the show never stop.
    struct QuickSearchRefusalView: View {
        let session: LiveSession
        let refusal: SearchRefusal

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.color.cueText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(refusal.heading)
                            .font(Theme.font.label)
                            .foregroundStyle(Theme.color.cueText)
                        Text(refusal.title)
                            .font(SchibstedGrotesk.semiBold.font(size: 22))
                            .foregroundStyle(Theme.color.ink)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(refusal.accessibilityLabel)
                .accessibilityIdentifier(AccessibilityID.liveSearchRefusal)
                Rectangle().fill(Theme.color.line).frame(height: 1)
                actions
            }
        }

        private var symbol: String {
            switch refusal.refusal {
            case .alreadyPlayed: "checkmark.circle"
            case .playingNow: "play.circle"
            case .requested, .upcoming: "list.bullet"
            }
        }

        private var actions: some View {
            HStack(spacing: 10) {
                Text(refusal.hint)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                Spacer()
                if refusal.refusal.moveToNext != nil {
                    Button("Back  Esc") { session.cancelRefusal() }
                        .buttonStyle(.segueSecondary)
                        .accessibilityIdentifier(AccessibilityID.liveSearchRefusalBack)
                    Button("Move to Next  ↩") { session.confirmRefusal() }
                        .buttonStyle(.seguePrimary)
                        .accessibilityIdentifier(AccessibilityID.liveSearchMoveToNext)
                } else {
                    Button("Back  ↩") { session.cancelRefusal() }
                        .buttonStyle(.seguePrimary)
                        .accessibilityIdentifier(AccessibilityID.liveSearchRefusalBack)
                }
            }
            .controlSize(.regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// The search result badge for where a song stands in the show (R102), and what
    /// VoiceOver says for it.
    enum StandingBadge {
        static func text(_ standing: SongStanding) -> String? {
            switch standing {
            case .free: nil
            case .played: "Played"
            case .current: "Playing"
            case let .upcoming(_, isNext): isNext ? "Up next" : "In set"
            case .requested: "Requested"
            case .skipped: "Skipped"
            }
        }

        static func spoken(_ standing: SongStanding) -> String? {
            switch standing {
            case .free: nil
            case .played: "Already played"
            case .current: "Playing now"
            case .upcoming(_, isNext: true): "Up next in the set"
            case .upcoming: "Still to come in the set"
            case .requested: "Already requested"
            case .skipped: "Skipped, can be added back"
            }
        }
    }
#endif
