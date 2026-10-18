#if os(macOS)
    import Services
    import SwiftUI

    /// The two consent questions (WS3 spec 4.2 step 3), each with two equal-weight choices:
    /// same style and size, neither default, neither preselected, neither in an accent colour.
    /// No window chrome and no Continue button: `ConsentSheet` wraps it for upgraders, and
    /// WS2b's Welcome flow shows it as its last page (contract in spec 4.4).
    ///
    /// Answers go to `store.draft` and only become decisions on `commit()` (Continue), so
    /// quitting before Continue leaves both undecided.
    public struct ConsentChoiceView: View {
        @Bindable var store: ConsentStore
        /// Where the answers are given; it becomes the `segue.source` of
        /// `Segue.Privacy.analyticsEnabled` when analytics are granted.
        let source: ConsentSource

        public init(store: ConsentStore, source: ConsentSource) {
            self.store = store
            self.source = source
        }

        /// Both rows are answered: the host's Continue may be enabled.
        public var isComplete: Bool {
            store.draft.isComplete
        }

        /// Records the answers as decisions (the host's Continue).
        public func commit() {
            store.commitDraft(source: source)
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ConsentQuestionRow(
                    question: .analytics,
                    answer: $store.draft.analytics,
                )
                Rectangle()
                    .fill(Theme.color.line)
                    .frame(height: 1)
                    .padding(.vertical, 16)
                    .accessibilityHidden(true)
                ConsentQuestionRow(
                    question: .crashReports,
                    answer: $store.draft.crashReports,
                )
            }
        }
    }

    /// The fixed copy of each question (spec 4.2, final) and its "What's sent" list.
    struct ConsentQuestion: Sendable {
        let toggle: ConsentStore.Toggle
        let title: String
        let detail: String
        let decline: String
        let accept: String
        let whatsSent: [String]

        static let analytics = Self(
            toggle: .analytics,
            title: "Share usage analytics",
            detail: "Anonymous counts of which features you use, your app and macOS version "
                + "and your country. Never your songs, lyrics, titles, setlists or file names.",
            decline: "Don’t Share",
            accept: "Share",
            whatsSent: [
                "Which features you use, counted at most once a day (transpose, setlists, "
                    + "stage tools and the like)",
                "Launches and days since you first opened Segue, as ranges",
                "Library size as ranges, for example 50-99 songs",
                "Shows started and ended: gig or rehearsal, length and set size as ranges",
                "Whether a search found songs through a spelling variant, never what you "
                    + "searched for",
                "Errors as fixed codes, never messages",
                "App version, macOS version and the country set on your Mac",
                "A random install identifier, hashed on this Mac",
            ],
        )

        static let crashReports = Self(
            toggle: .crashReports,
            title: "Send crash reports",
            detail: "If Segue crashes or freezes, send the technical report (code locations, "
                + "Mac model, macOS version) to help fix it. Never your songs or files.",
            decline: "Don’t Send",
            accept: "Send",
            whatsSent: [
                "Where in Segue’s code the crash or freeze happened",
                "Mac model, macOS version, processor type, memory and language",
                "App version and build",
                "The last few steps in Segue as fixed names, for example “show started”",
                "A random Diagnostics ID for this install",
            ],
        )
    }

    /// One question: title, one plain sentence, the two choices and "What's sent".
    private struct ConsentQuestionRow: View {
        let question: ConsentQuestion
        @Binding var answer: Bool?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(question.title)
                    .font(SchibstedGrotesk.semiBold.font(size: 15))
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(question.detail)
                    .font(.callout)
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    choice(question.decline, value: false, id: AccessibilityID.consentDecline)
                    choice(question.accept, value: true, id: AccessibilityID.consentAccept)
                }
                .padding(.top, 4)
                WhatsSentDisclosure(items: question.whatsSent, toggle: question.toggle)
            }
        }

        private func choice(_ title: String, value: Bool, id: (ConsentStore.Toggle) -> String)
            -> some View
        {
            let isSelected = answer == value
            return Button {
                answer = value
            } label: {
                Text(title)
            }
            .buttonStyle(ConsentOptionStyle(isSelected: isSelected))
            .accessibilityIdentifier(id(question.toggle))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityValue(isSelected ? "selected" : "not selected")
        }
    }

    /// "What's sent", collapsed by default.
    struct WhatsSentDisclosure: View {
        let items: [String]
        let toggle: ConsentStore.Toggle
        @State private var isExpanded = false

        var body: some View {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                                .accessibilityHidden(true)
                            Text(item)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(Theme.color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                Text("What’s sent")
                    .font(.callout)
                    .foregroundStyle(Theme.color.ink)
            }
            .accessibilityIdentifier(AccessibilityID.consentWhatsSent(toggle))
        }
    }

    /// A consent choice: both choices of a question look the same until one is picked, and
    /// the picked one gets an ink outline and a check mark (never the accent colour, never a
    /// fill that reads as "recommended"). Fixed width, so both have equal frames.
    struct ConsentOptionStyle: ButtonStyle {
        static let width: CGFloat = 148

        let isSelected: Bool

        func makeBody(configuration: Configuration) -> some View {
            ConsentOptionBody(configuration: configuration, isSelected: isSelected)
        }
    }

    private struct ConsentOptionBody: View {
        let configuration: ButtonStyle.Configuration
        let isSelected: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                configuration.label
                // Balances the check mark so the title stays centred.
                Color.clear.frame(width: 11, height: 1)
            }
            .font(SchibstedGrotesk.semiBold.font(size: 13))
            .lineLimit(1)
            .foregroundStyle(Theme.color.ink)
            .frame(width: ConsentOptionStyle.width)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    shape.fill(Theme.color.ground)
                    shape.fill(Theme.color.ink.opacity(feedbackOpacity))
                    shape.strokeBorder(
                        isSelected ? Theme.color.ink : Theme.color.controlBorder,
                        lineWidth: isSelected ? 1.5 : 1,
                    )
                }
            }
            .contentShape(shape)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isSelected)
        }

        private var feedbackOpacity: Double {
            if configuration.isPressed {
                return 0.1
            }
            return isHovered ? 0.06 : 0
        }
    }
#endif
