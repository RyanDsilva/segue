import SegueUI
import SwiftUI

/// The "?" beside the web field and in Find Lyrics (spec 11.7): the owner's in-product
/// guide. There is no public guide page for these features (R179).
struct ImportHelpButton: View {
    enum Topic {
        case webPage
        case search
    }

    let topic: Topic
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.color.muted)
        }
        .buttonStyle(.plain)
        .help("How this works")
        .accessibilityLabel("Help")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, text in
                        Text(verbatim: text)
                            .font(index == 0 ? SchibstedGrotesk.bold.font(size: 14)
                                : SchibstedGrotesk.medium.font(size: 13))
                            .foregroundStyle(index == 0 ? Theme.color.ink : Theme.color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
            }
            .frame(width: 360, height: 360)
        }
    }

    private var paragraphs: [String] {
        let shared = [
            "Results are a starting point: check the chords and words against the recording "
                + "before you rely on them. Nothing is kept unless you press Accept in the review.",
            "A page that asks for a human check can be opened here with Open Here: complete "
                + "the check yourself and Segue goes on. A page that blocks apps can be opened "
                + "in Safari, saved with File > Save As and imported, or copied and pasted.",
            "This exists only in your personal build of Segue.",
        ]
        switch topic {
        case .webPage:
            return [
                "Import a web page",
                "Paste the address of a chord page (or drop a link from Safari) and Segue reads "
                    + "that one page: Ultimate Guitar, E-Chords and Chordie each have their own "
                    + "reader, any other page the general reader. You review it like a paste.",
            ] + shared
        case .search:
            return [
                "Find Lyrics",
                "One search, on Return, across Ultimate Guitar, E-Chords and LRCLIB, grouped in "
                    + "that order. A song's versions nest under it, best rated first; pick one "
                    + "to see its preview, then Review. LRCLIB gives plain lyrics, already in "
                    + "sections where the repeats show; Hindi in Devanagari arrives romanized.",
            ] + shared
        }
    }
}
