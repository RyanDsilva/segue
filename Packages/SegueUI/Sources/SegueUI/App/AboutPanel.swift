#if os(macOS)
    import AppKit

    /// Segue > About Segue (WS2a 3.6): the standard panel with the icon, "Version 0.5 (12)"
    /// and the copyright from Info.plist (WS1 sets them, R5, R30), plus credits: the site's
    /// links and the open-source software Segue is built with. The credits link the web
    /// Acknowledgements page; the in-app window is Help > Acknowledgements.
    enum AboutPanel {
        @MainActor
        static func show() {
            NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
            NSApp.activate()
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

        /// Two centred paragraphs in the brand face, muted: the links, then the credits.
        static func credits() -> NSAttributedString {
            let font = NSFont(name: SchibstedGrotesk.medium.rawValue, size: 11)
                ?? NSFont.systemFont(ofSize: 11)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.paragraphSpacing = 6
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
            let separator = " · "
            append(SegueLinks.site.host() ?? "", link: SegueLinks.site)
            append(separator)
            append("Help", link: SegueLinks.help)
            append(separator)
            append("Support", link: SegueLinks.support)
            append(separator)
            // No-break spaces keep each name on one line when the panel wraps.
            append("Privacy\u{00A0}Policy", link: SegueLinks.privacy)
            append("\n")
            append("Built with open-source software: Schibsted\u{00A0}Grotesk "
                + "(SIL\u{00A0}OFL\u{00A0}1.1), GRDB\u{00A0}(MIT), Tonic\u{00A0}(MIT). ")
            append("Acknowledgements", link: SegueLinks.acknowledgements)
            return text
        }
    }
#endif
