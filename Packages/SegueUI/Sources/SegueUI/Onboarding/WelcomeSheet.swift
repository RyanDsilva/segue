#if os(macOS)
    import Services
    import SwiftUI

    /// The Welcome sheet (WS2b 4.1), direction A "Native" (R52): left-aligned, a small
    /// "Step n of m" over a 28 pt title, grouped surfaces, the actions at the bottom right.
    /// Pages: the library folder, the Welcome songs, then WS3's consent choice hosted as is.
    /// It cannot be dismissed except by finishing (revisit mode closes with Done or Esc).
    struct WelcomeSheet: View {
        let app: AppModel
        @Bindable var model: OnboardingModel
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        static let width: CGFloat = 560
        /// One height for every page, so Continue never jumps (page 3 grows if it must).
        static let minHeight: CGFloat = 540

        var body: some View {
            ZStack(alignment: .topLeading) {
                page
                    .id(model.page)
                    .transition(pageTransition)
            }
            .animation(reduceMotion ? nil : .linear(duration: 0.15), value: model.page)
            .frame(width: Self.width)
            .frame(minHeight: model.mode == .flow ? Self.minHeight : nil, alignment: .top)
            .background(Theme.color.ground)
            .interactiveDismissDisabled(model.mode == .flow)
            // Esc never answers for the user; in revisit mode it closes.
            .onExitCommand {
                if model.mode == .revisit {
                    app.closeWelcomeRevisit()
                }
            }
        }

        /// The old page fades out, then the new one fades in (150 ms in all, brand.md
        /// section 8), so two layouts never show on top of each other. None with Reduce
        /// Motion.
        private var pageTransition: AnyTransition {
            guard !reduceMotion else { return .identity }
            return .asymmetric(
                insertion: .opacity.animation(.easeOut(duration: 0.08).delay(0.07)),
                removal: .opacity.animation(.easeIn(duration: 0.07)),
            )
        }

        @ViewBuilder private var page: some View {
            switch model.page {
            case .library:
                WelcomeLibraryPage(app: app, model: model)
            case .welcomeSongs:
                WelcomeSongsPage(app: app, model: model)
            case .consent:
                WelcomeConsentPage(app: app, model: model)
            }
        }
    }

    // MARK: - Shared page chrome

    /// Step label, title, content, then the footer pinned to the bottom.
    private struct WelcomePage<Content: View, Footer: View>: View {
        let step: String?
        /// The flow's fixed page height; revisit mode fits its content.
        var minHeight: CGFloat? = WelcomeSheet.minHeight
        let title: String
        @ViewBuilder let content: Content
        @ViewBuilder let footer: Footer

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let step {
                    Text(step)
                        .font(SchibstedGrotesk.bold.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier(AccessibilityID.welcomeStep)
                        // VoiceOver reads the title first, then the step.
                        .accessibilitySortPriority(1)
                }
                Text(title)
                    .font(Theme.font.title)
                    .tracking(Theme.tracking.title * 28)
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.welcomeTitle)
                    .accessibilitySortPriority(2)
                content
                Spacer(minLength: 0)
                footer
                    .padding(.top, 20)
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        }
    }

    /// The muted lead paragraph under a title.
    private struct WelcomeLead: View {
        let text: String

        var body: some View {
            Text(text)
                .font(Theme.font.body)
                .foregroundStyle(Theme.color.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The grouped surface: `surfaceAlt`, radius 12.
    struct WelcomeGroup: ViewModifier {
        var padding: CGFloat = 14

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.color.surfaceAlt),
                )
        }
    }

    // MARK: - Page 1: library

    private struct WelcomeLibraryPage: View {
        let app: AppModel
        let model: OnboardingModel

        var body: some View {
            WelcomePage(step: model.stepLabel, title: uiString("Where should your songs live?")) {
                WelcomeLead(text: "Segue keeps every song as a plain ChordPro file in a folder "
                    + "you choose. We suggest a Segue folder in Music.")
                suggestion
                    .padding(.top, 22)
                Text("Songs are plain ChordPro files you can open in any editor.", bundle: #bundle)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.top, 12)
            } footer: {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 10) {
                        Spacer()
                        Button(uiString("Choose Existing Folder…")) {
                            Task { await app.onboardingChooseLibrary(create: false) }
                        }
                        .buttonStyle(.segueSecondary)
                        .accessibilityIdentifier(AccessibilityID.chooserOpen)
                        Button(uiString("Create Library in Music…")) {
                            Task { await app.onboardingChooseLibrary(create: true) }
                        }
                        .buttonStyle(.seguePrimary)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.chooserCreate)
                    }
                    .disabled(model.isChoosingFolder)
                    if let error = model.libraryError {
                        WelcomeError(text: error)
                            .accessibilityIdentifier(AccessibilityID.welcomeLibraryError)
                    }
                }
            }
        }

        /// Where the library goes by default.
        private var suggestion: some View {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Segue", bundle: #bundle)
                        .font(SchibstedGrotesk.bold.font(size: 15))
                        .foregroundStyle(Theme.color.ink)
                    Text("~/Music/Segue", bundle: #bundle)
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                }
                Spacer()
                Text("Suggested", bundle: #bundle)
                    .font(SchibstedGrotesk.bold.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Theme.color.controlBorder, lineWidth: 1))
            }
            .modifier(WelcomeGroup())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(uiString("Suggested folder: Segue, in Music"))
        }
    }

    /// An inline problem: icon plus text (never colour alone).
    private struct WelcomeError: View {
        let text: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.color.cueText)
                    .accessibilityHidden(true)
                Text(text)
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Page 2: Welcome songs (also revisit mode)

    private struct WelcomeSongsPage: View {
        let app: AppModel
        @Bindable var model: OnboardingModel

        var body: some View {
            WelcomePage(
                step: model.stepLabel,
                minHeight: model.mode == .revisit ? nil : WelcomeSheet.minHeight,
                title: uiString("Welcome to Segue"),
            ) {
                WelcomeCards()
                    .padding(.top, 12)
                if model.mode == .revisit {
                    WelcomePasteCard(app: app)
                        .padding(.top, 10)
                    revisitContent
                        .padding(.top, 20)
                } else {
                    Toggle(isOn: $model.addsWelcomeSongs) {
                        Text("Add 4 songs and a setlist written for Segue "
                            + "(you can delete them anytime)")
                            .font(SchibstedGrotesk.medium.font(size: 14))
                            .foregroundStyle(Theme.color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.segueCheckbox)
                    .disabled(model.seedState == .seeding)
                    .accessibilityIdentifier(AccessibilityID.welcomeAddSongs)
                    .padding(.top, 20)
                }
                if case let .failed(reason) = model.seedState {
                    WelcomeError(text: "Segue could not add the Welcome songs (\(reason)).")
                        .accessibilityIdentifier(AccessibilityID.welcomeSeedError)
                        .padding(.top, 14)
                }
            } footer: {
                HStack(spacing: 10) {
                    Spacer()
                    if model.seedState == .seeding {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(uiString("Adding the Welcome songs"))
                    }
                    footerButtons
                }
            }
        }

        @ViewBuilder private var footerButtons: some View {
            if model.mode == .revisit {
                // Esc closes revisit mode (it answers nothing).
                Button(uiString("Close")) { app.closeWelcomeRevisit() }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
                Button {
                    app.closeWelcomeRevisit()
                } label: {
                    Text("Done", bundle: #bundle).frame(minWidth: 76)
                }
                .buttonStyle(.seguePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(model.seedState == .seeding)
                .accessibilityIdentifier(AccessibilityID.welcomeDone)
            } else if case .failed = model.seedState {
                Button(uiString("Skip")) { app.onboardingSkipWelcomeSongs() }
                    .buttonStyle(.segueSecondary)
                    .accessibilityIdentifier(AccessibilityID.welcomeSkip)
                Button(uiString("Try Again")) {
                    Task { await app.onboardingContinueFromWelcomeSongs() }
                }
                .buttonStyle(.seguePrimary)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AccessibilityID.welcomeRetry)
            } else {
                Button {
                    Task { await app.onboardingContinueFromWelcomeSongs() }
                } label: {
                    Text("Continue", bundle: #bundle).frame(minWidth: 76)
                }
                .buttonStyle(.seguePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(model.seedState == .seeding)
                .accessibilityIdentifier(AccessibilityID.welcomeContinue)
            }
        }

        @ViewBuilder private var revisitContent: some View {
            if model.hasWelcomeSongs {
                Text("The Welcome songs are in your library (tag: Welcome).", bundle: #bundle)
                    .font(SchibstedGrotesk.medium.font(size: 14))
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityIdentifier(AccessibilityID.welcomeInLibrary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add 4 songs and a setlist written for Segue to this library. "
                        + "You can delete them anytime.")
                        .font(SchibstedGrotesk.medium.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(uiString("Add Welcome Songs")) {
                        Task { await app.onboardingAddWelcomeSongs() }
                    }
                    .buttonStyle(.segueSecondary)
                    .disabled(model.seedState == .seeding)
                    .accessibilityIdentifier(AccessibilityID.welcomeAddButton)
                }
            }
        }
    }

    /// What Segue does, in three compact cards.
    private struct WelcomeCards: View {
        private struct Card: Identifiable {
            let symbol: String
            let title: String
            let detail: String

            var id: String {
                title
            }
        }

        private static let cards = [
            Card(
                symbol: "square.and.pencil",
                title: uiString("Write or drop in songs"),
                detail: uiString("ChordPro or plain text"),
            ),
            Card(
                symbol: "list.number",
                title: uiString("Build a setlist"),
                detail: uiString("Drag songs, see the running time"),
            ),
            Card(
                symbol: "music.mic",
                title: uiString("Play on stage"),
                detail: uiString("Full screen, keys and pedals; press ? for every key"),
            ),
        ]

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Self.cards) { card in
                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: card.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.color.ink)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Theme.color.ground),
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Theme.color.controlBorder, lineWidth: 1),
                            )
                            .padding(.bottom, 14)
                            .accessibilityHidden(true)
                        Text(card.title)
                            .font(SchibstedGrotesk.bold.font(size: 14))
                            .foregroundStyle(Theme.color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)
                        Text(card.detail)
                            .font(SchibstedGrotesk.medium.font(size: 13))
                            .foregroundStyle(Theme.color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .modifier(WelcomeGroup())
                    .accessibilityElement(children: .combine)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Page 3: consent (WS3's view, hosted unchanged)

    private struct WelcomeConsentPage: View {
        let app: AppModel
        let model: OnboardingModel

        var body: some View {
            let choice = ConsentChoiceView(store: app.dependencies.consent, source: .welcome)
            WelcomePage(step: model.stepLabel, title: uiString("Help improve Segue?")) {
                WelcomeLead(text: ConsentSheet.intro)
                choice
                    .modifier(WelcomeGroup(padding: 16))
                    .padding(.top, 18)
                Text(ConsentCopy.bugReportsNote)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            } footer: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    PolicyLink(workspace: app.dependencies.workspace)
                    Spacer()
                    // Not the default button until both rows are answered, so Return never
                    // answers for the user.
                    Button {
                        choice.commit()
                        app.onboardingFinishConsent()
                    } label: {
                        Text("Continue", bundle: #bundle).frame(minWidth: 76)
                    }
                    .buttonStyle(.seguePrimary)
                    .keyboardShortcut(choice.isComplete ? .defaultAction : nil)
                    .disabled(!choice.isComplete)
                    .accessibilityIdentifier(AccessibilityID.welcomeContinue)
                }
            }
        }
    }
#endif
