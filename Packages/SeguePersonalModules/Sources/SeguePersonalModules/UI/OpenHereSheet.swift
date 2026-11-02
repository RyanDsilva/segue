import AppKit
import SegueUI
import SwiftUI
import WebKit

/// Open Here (spec 8.6, R183, R198 direction A): the hidden view, shown at full sheet size
/// with its page as it is, so the owner completes the check himself. When the check clears
/// the sheet closes and the import or search goes on by itself; the clearance lands in the
/// persistent store, so later hidden loads reuse it. The app never clicks, solves or injects
/// into the check.
struct OpenHereSheet: View {
    let url: URL
    /// The hidden view's loader; nil when none can show a page (tests, fixtures).
    let source: (any ChallengeViewSource)?
    /// True when the check cleared, false when cancelled.
    let finish: (Bool) -> Void

    @State private var view: WKWebView?
    @Environment(\.openURL) private var openURL

    private var host: String {
        WebAddress.siteHost(url)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "\(host) wants to check you're a person")
                    .font(SchibstedGrotesk.bold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            Group {
                if let view {
                    ChallengeWebView(view: view)
                } else if source == nil {
                    ContentUnavailableView(
                        "The page isn't loaded here",
                        systemImage: "globe",
                        description: Text(verbatim: "Open it in Safari instead."),
                    )
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Check from \(host)")
            Divider()
            HStack(spacing: 10) {
                Text(
                    verbatim: "Complete the check yourself. Segue goes on when it passes.",
                )
                .font(SchibstedGrotesk.medium.font(size: 12.5))
                .foregroundStyle(Theme.color.muted)
                Spacer(minLength: 12)
                Button("Open in Safari") { openURL(url) }
                    .buttonStyle(.segueSecondary)
                Button("Cancel") { finish(false) }
                    .buttonStyle(.segueSecondary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 680)
        .background(Theme.color.ground)
        .accessibilityIdentifier(AccessibilityID.openHereSheet)
        .task {
            guard let source else { return }
            view = await source.presentChallenge(for: url)
            if await source.waitUntilCleared() {
                finish(true)
            }
        }
        .onDisappear { source?.endPresentation() }
    }
}

/// The hidden `WKWebView` placed in the sheet as it is: it is reused (same store, same
/// session), so it is never recreated here, only re-parented.
private struct ChallengeWebView: NSViewRepresentable {
    let view: WKWebView

    func makeNSView(context _: Context) -> NSView {
        let container = NSView()
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_: NSView, context _: Context) {}

    static func dismantleNSView(_ container: NSView, coordinator _: ()) {
        for subview in container.subviews {
            subview.removeFromSuperview()
        }
    }
}
