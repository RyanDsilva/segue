// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 12.3, P8-6 section
// 9). Hearing the fill sheet's rows on the shared engine: once or looping, A/B at the next
// phrase start, edits swapped in while looping, never during a gig.

import Playback
import SwiftUI

extension FillEditorModel {
    /// Sound works now (never during a gig).
    var canPlay: Bool {
        audition != nil && host.sound?.isAvailable == true
    }

    func isOurs(_ player: SoundPlayer) -> Bool {
        generation == player.generation
    }

    /// Whether `row` is sounding now.
    func isSounding(_ row: Row) -> Bool {
        guard sounding == row, let player = audition?.current(), player.isPlaying else {
            return false
        }
        return isOurs(player)
    }

    /// The audition of a row's draft (its edits included).
    func phrase(for row: Row) -> FillAuditionPhrase? {
        guard let audition else { return nil }
        return PhraseBuilder.fill(
            span: song.timeline,
            chords: span,
            notes: resolved(draft(for: row).events),
            voices: audition.voices(),
            transform: song.transform,
            click: click,
            factor: tempoFactor,
        )
    }

    /// ▶ or Space: plays `row` (once, or looping), or stops it when it sounds; playing
    /// another row stops the last at once. Playing never saves.
    func toggle(_ row: Row) {
        guard let audition, canPlay else { return }
        if isSounding(row) {
            stop()
            return
        }
        guard let player = audition.player(), let phrase = phrase(for: row) else { return }
        player.stop()
        if looping {
            player.loop(phrase.phrase)
        } else {
            player.play(phrase.phrase)
        }
        generation = player.generation
        playing = phrase
        sounding = row
        audition.played()
    }

    /// Space: the selected row.
    func togglePlay() {
        toggle(selected)
    }

    /// The Loop switch: on restarts the sounding row looping, off stops it.
    func setLooping(_ isOn: Bool) {
        guard isOn != looping else { return }
        looping = isOn
        guard let sounding, isSounding(sounding) else { return }
        self.sounding = nil
        audition?.current()?.stop()
        if isOn {
            toggle(sounding)
        }
    }

    /// Click or tempo changed: a sounding loop takes it from the next pass.
    func soundSettingsChanged() {
        guard let sounding, isSounding(sounding), let phrase = phrase(for: sounding) else {
            return
        }
        audition?.current()?.swapAtNextWrap(phrase.phrase)
        playing = phrase
    }

    /// Stops what this sheet started.
    func stop() {
        guard sounding != nil else { return }
        if let player = audition?.current(), player.isPlaying, isOurs(player) {
            player.stop()
        }
        sounding = nil
        playing = nil
    }

    /// The playhead's tick on the song's timeline while this sheet plays.
    var playheadTick: Int? {
        guard let sounding, isSounding(sounding), let playing,
              let player = audition?.current()
        else { return nil }
        return playing.tick(atSeconds: player.position)
    }

    /// An edit while the edited row loops swaps it in at the next wrap.
    func draftChanged(_ draft: FillDraft) {
        guard drafts[selected] === draft, sounding == selected, isSounding(selected), looping,
              let phrase = phrase(for: selected)
        else { return }
        audition?.current()?.swapAtNextWrap(phrase.phrase)
        playing = phrase
    }
}
