#if os(macOS)
    import Services
    import SwiftUI

    /// The standalone consent prompt (WS3 spec 4.2, 4.4): `ConsentChoiceView` with a title,
    /// the intro, the footer and Continue, 480 pt wide. Shown to upgraders and whenever the
    /// Welcome flow does not run. There is no close button and Esc does nothing: it goes away
    /// only once both questions are answered and Continue is pressed.
    public struct ConsentSheet: View {
        let store: ConsentStore
        let workspace: any WorkspaceActions

        public static let width: CGFloat = 480

        public init(store: ConsentStore, workspace: any WorkspaceActions) {
            self.store = store
            self.workspace = workspace
        }

        public var body: some View {
            let choice = ConsentChoiceView(store: store, source: .prompt)
            VStack(alignment: .leading, spacing: 0) {
                Text("Help improve Segue", bundle: #bundle)
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.consentSheet)
                Text(Self.intro)
                    .font(.callout)
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                choice
                    .padding(.top, 20)
                Text(ConsentCopy.bugReportsNote)
                    .font(.callout)
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                HStack(alignment: .firstTextBaseline) {
                    PolicyLink(workspace: workspace)
                    Spacer()
                    Button(uiString("Continue")) { choice.commit() }
                        .buttonStyle(.seguePrimary)
                        .disabled(!choice.isComplete)
                        .accessibilityIdentifier(AccessibilityID.consentContinue)
                }
                .padding(.top, 16)
            }
            .padding(24)
            .frame(width: Self.width)
            .background(Theme.color.ground)
            .interactiveDismissDisabled()
            // Esc must not answer for the user.
            .onExitCommand {}
        }

        static let intro = "Two separate choices. Segue works the same either way, and you "
            + "can change them any time in Settings > Privacy."
    }

    /// Copy shared by the prompt and Settings > Privacy.
    enum ConsentCopy {
        static let bugReportsNote = "Bug reports are separate: they are sent only when you "
            + "press Send, after you see everything."
    }

    /// "Privacy Policy", opened in the browser.
    struct PolicyLink: View {
        let workspace: any WorkspaceActions
        var title = "Privacy Policy"
        var url = SegueLinks.privacy

        var body: some View {
            Button(title) { workspace.open(url) }
                .buttonStyle(.appLink)
                .font(.callout)
                .accessibilityIdentifier(AccessibilityID.privacyPolicyLink(title))
        }
    }
#endif
