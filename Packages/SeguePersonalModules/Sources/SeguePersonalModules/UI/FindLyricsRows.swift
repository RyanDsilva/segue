import Plugins
import SegueUI
import SwiftUI

/// A song: title (bold), "artist - Movie / Album" (muted), the quiet marks, and for a lyrics
/// record its first two lines (spec 6.4). Song content is shown verbatim, never translated.
struct FindLyricsSongRow: View {
    let song: FindLyricsModel.Song
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if song.nests {
                Button(action: toggle) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.color.muted)
                        .frame(width: 12, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide versions" : "Show versions")
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: song.title)
                        .font(SchibstedGrotesk.bold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    if song.inLibrary {
                        mark("In your library")
                    }
                    if song.best.romanized {
                        mark("Converted from Devanagari")
                    }
                    if song.best.isInstrumental {
                        mark("Instrumental")
                    }
                }
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(SchibstedGrotesk.medium.font(size: 12.5))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                }
                if let lines = song.best.firstLines, !song.nests {
                    Text(verbatim: lines)
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityHint(song.nests ? "" : (song.best.firstLines ?? ""))
    }

    private var subtitle: String {
        var parts = [song.artist, song.album].compactMap(\.self).filter { !$0.isEmpty }
            .joined(separator: " - ")
        if song.nests {
            let count = song.versions.count
            parts += (parts.isEmpty ? "" : " · ") + (count == 1 ? "1 version" : "\(count) versions")
        }
        return parts
    }

    private var label: String {
        var text = [song.title, song.artist, song.album].compactMap(\.self).joined(separator: ", ")
        if song.nests {
            text += ". \(song.versions.count) versions"
        }
        if song.inLibrary {
            text += ". In your library"
        }
        return text + "."
    }

    private func mark(_ text: String) -> some View {
        Text(verbatim: text)
            .font(SchibstedGrotesk.medium.font(size: 11))
            .foregroundStyle(Theme.color.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Theme.color.lineStrong))
    }
}

/// "Chords · ver 3 · ★4.8 · 1,204 votes", the best one marked.
struct FindLyricsVersionRow: View {
    let version: SearchCandidate
    let isBest: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: title)
                .font(SchibstedGrotesk.semiBold.font(size: 13))
                .foregroundStyle(Theme.color.ink)
            if isBest {
                Text(verbatim: "Best")
                    .font(SchibstedGrotesk.bold.font(size: 11))
                    .foregroundStyle(Theme.color.cue)
            }
            Spacer(minLength: 8)
            if let rating = version.rating {
                Text(verbatim: "★" + rating.formatted(.number.precision(.fractionLength(1))))
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
            }
            if let votes = version.votes {
                Text(verbatim: votes == 1 ? "1 vote" : "\(votes.formatted()) votes")
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
            }
        }
        .padding(.leading, 18)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var title: String {
        var parts = ["Chords"]
        if let number = version.version {
            parts.append("ver \(number)")
        }
        return parts.joined(separator: " · ")
    }

    private var label: String {
        var text = "Chords"
        if let number = version.version {
            text += ", version \(number)"
        }
        if let rating = version.rating {
            text += ", rated " + rating.formatted(.number.precision(.fractionLength(1)))
            if let votes = version.votes {
                text += " from \(votes.formatted()) votes"
            }
        }
        return text + (isBest ? ". Best." : "")
    }
}
