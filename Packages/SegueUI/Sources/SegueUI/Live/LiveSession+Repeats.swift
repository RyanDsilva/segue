#if os(macOS)
    import Foundation
    import Library
    import Shows

    /// A search action refused because the song is already in the show (R102): what the
    /// overlay says and the one-step alternative it offers.
    public struct SearchRefusal: Equatable, Sendable {
        public let songId: SongID
        public let title: String
        public let refusal: RepeatRefusal
        /// Whether the show is a rehearsal ("in this rehearsal" rather than "tonight").
        let isRehearsal: Bool

        /// The heading: "Already played tonight", "Already in the set"...
        var heading: String {
            switch refusal {
            case .alreadyPlayed:
                isRehearsal ? "Already played in this rehearsal" : "Already played tonight"
            case .playingNow:
                "Playing now"
            case let .upcoming(_, isNext):
                isNext ? "Already up next" : "Already in the set"
            case let .requested(_, isNext):
                isNext ? "Already the next request" : "Already requested"
            }
        }

        /// The key hint line under the song.
        var hint: String {
            refusal.moveToNext == nil ? "↩ or Esc goes back to the results"
                : "↩ moves it to next  ·  Esc goes back"
        }

        /// Read by VoiceOver for the whole message.
        var accessibilityLabel: String {
            "\(heading): \(title)"
        }
    }

    public extension LiveSession {
        /// Where `song` stands in this show (the search results' badges).
        func standing(of song: SongID) -> SongStanding {
            state.record.standing(of: song)
        }

        /// R102: shows the refusal in the overlay instead of acting when `action` would add
        /// `song` a second time. Returns true when it refused.
        internal func refuseRepeat(_ action: SearchAction, song: SongID) -> Bool {
            let showAction: ShowAction = switch action {
            case .playNow: .playNow(song)
            case .addRequest: .addRequest(song, note: nil)
            case .insertNext: .insertNext(song)
            }
            guard let refusal = state.record.repeatRefusal(for: showAction) else { return false }
            let title = search.results.first { $0.id == song }.map(SongSummary.title)
                ?? state.record.items.first { $0.songId == song }?.title
                ?? state.record.queuedRequests.first { $0.songId == song }?.title
                ?? "This song"
            search.refusal = SearchRefusal(
                songId: song,
                title: title,
                refusal: refusal,
                isRehearsal: kind == .rehearsal,
            )
            return true
        }

        /// Return on the refusal: "Move to Next" when it offers it (and the overlay closes),
        /// otherwise back to the results.
        func confirmRefusal() {
            guard let refusal = search.refusal else { return }
            search.refusal = nil
            guard let move = refusal.refusal.moveToNext else { return }
            overlay = nil
            perform(move)
        }

        /// Esc on the refusal: back to the results, nothing changed.
        func cancelRefusal() {
            search.refusal = nil
        }
    }
#endif
