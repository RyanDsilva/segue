#if os(macOS)
    import AppKit

    /// Segue > About Segue (WS2a 3.6, R103 variant A): the standard panel with the icon,
    /// "Version 0.5 (12)" and the copyright from Info.plist (WS1 sets them, R5, R30), plus
    /// credits: one row of links, Website, Help, Support and Privacy Policy. Third-party notices
    /// are not shown in the app: they ship in the bundle
    /// (THIRD_PARTY_NOTICES.md, licence texts) and on the website, linked from its legal pages.
    enum AboutPanel {
        @MainActor
        static func show() {
            let credits = credits()
            NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
            styleLinks(showing: credits)
            NSApp.activate()
        }

        /// The app's link style (as in the editor): `cueText`, with the pointing hand. The
        /// standard panel's text view draws links in system blue through its own
        /// `linkTextAttributes`, which override the string's, so they are set on it here.
        /// Only the separators keep the panel's dimmed secondary colour: the links measure
        /// 6.2:1 on the dark panel and 4.7:1 on the light one (R103, WCAG AA).
        @MainActor
        private static func styleLinks(showing credits: NSAttributedString) {
            let cueText = NSColor(named: "cueText", bundle: Theme.bundle) ?? .linkColor
            for window in NSApp.windows {
                guard let textView = textView(in: window.contentView, showing: credits.string)
                else { continue }
                textView.linkTextAttributes = [
                    .foregroundColor: cueText,
                    .cursor: NSCursor.pointingHand,
                ]
                textView.needsDisplay = true
            }
        }

        @MainActor
        private static func textView(in view: NSView?, showing string: String) -> NSTextView? {
            guard let view else {
                return nil
            }
            if let textView = view as? NSTextView, textView.string == string {
                return textView
            }
            for subview in view.subviews {
                if let found = textView(in: subview, showing: string) {
                    return found
                }
            }
            return nil
        }

        /// "Version 0.5 (12)", as the panel shows it, from `bundle`'s Info.plist.
        static func versionText(bundle: Bundle = .main) -> String {
            let info = bundle.infoDictionary ?? [:]
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            let build = info["CFBundleVersion"] as? String ?? "?"
            return "Version \(version) (\(build))"
        }

        /// The copyright line the panel shows, from `bundle`'s Info.plist.
        static func copyright(bundle: Bundle = .main) -> String? {
            bundle.infoDictionary?["NSHumanReadableCopyright"] as? String
        }

        /// One centred row of links in the brand face: Website · Help · Support · Privacy
        /// Policy (R103).
        static func credits() -> NSAttributedString {
            let font = NSFont(name: SchibstedGrotesk.medium.rawValue, size: 11)
                ?? NSFont.systemFont(ofSize: 11)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let base: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
            let text = NSMutableAttributedString()
            func append(_ string: String, link: URL? = nil) {
                var attributes = base
                if let link {
                    attributes[.link] = link
                }
                text.append(NSAttributedString(string: string, attributes: attributes))
            }
            // No-break spaces keep every name whole if the row ever has to wrap.
            let links = [
                ("Website", SegueLinks.site),
                ("Help", SegueLinks.help),
                ("Support", SegueLinks.support),
                ("Privacy\u{00A0}Policy", SegueLinks.privacy),
            ]
            for (index, (label, url)) in links.enumerated() {
                if index > 0 {
                    append(" · ")
                }
                append(label, link: url)
            }
            return text
        }
    }
#endif
