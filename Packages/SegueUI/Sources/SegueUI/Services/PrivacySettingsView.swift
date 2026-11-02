#if os(macOS)
    import AppKit
    import Services
    import SwiftUI

    /// Settings > Privacy (WS3 spec 4.3; WS2b's Settings host shows it unchanged): the two
    /// consent toggles with their "What's sent" lists, what turning one off did and how to
    /// request deletion, and the policy links.
    public struct PrivacySettingsView: View {
        @Bindable var store: ConsentStore
        let workspace: any WorkspaceActions

        public init(store: ConsentStore, workspace: any WorkspaceActions) {
            self.store = store
            self.workspace = workspace
        }

        public var body: some View {
            Form {
                if store.isAvailable {
                    toggleSection(.analytics) {
                        if store.revokedThisSession.contains(.analytics) {
                            caption(Self.analyticsStopped, id: AccessibilityID.privacyCaption(
                                .analytics,
                            ))
                        }
                    }
                    toggleSection(.crashReports) {
                        crashCaptions
                    }
                } else {
                    Section {
                        Text(uiString("Analytics and crash reporting are not part of this build."))
                            .foregroundStyle(Theme.color.muted)
                            .accessibilityIdentifier(AccessibilityID.privacyUnavailable)
                    }
                }
                Section {
                    Text(Self.bugReportsNote)
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        PolicyLink(workspace: workspace)
                        PolicyLink(
                            workspace: workspace,
                            title: uiString("What Segue collects"),
                            url: SegueLinks.privacyUsage,
                        )
                    }
                }
                SettingsGuideHelp(page: .privacySettings)
            }
            .formStyle(.grouped)
            .settingsPaneHeight(minimum: 520)
        }

        private func toggleSection(
            _ toggle: ConsentStore.Toggle,
            @ViewBuilder captions: () -> some View,
        ) -> some View {
            let question: ConsentQuestion = toggle == .analytics ? .analytics : .crashReports
            return Section {
                Toggle(isOn: binding(toggle)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(question.title)
                        Text(question.detail)
                            .font(.callout)
                            .foregroundStyle(Theme.color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.privacyToggle(toggle))
                WhatsSentDisclosure(items: question.whatsSent, toggle: toggle)
                captions()
            }
        }

        @ViewBuilder private var crashCaptions: some View {
            if store.revokedThisSession.contains(.crashReports) {
                VStack(alignment: .leading, spacing: 8) {
                    caption(
                        Self.crashStopped(hasID: store.revokedDiagnosticsID != nil),
                        id: AccessibilityID.privacyCaption(.crashReports),
                    )
                    if let id = store.revokedDiagnosticsID {
                        HStack(spacing: 8) {
                            Text(id)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .accessibilityLabel(uiString("Diagnostics ID \(id)"))
                                .accessibilityIdentifier(AccessibilityID.privacyDiagnosticsID)
                            Button(uiString("Copy")) { Self.copy(id) }
                                .buttonStyle(.segueSecondary)
                                .controlSize(.small)
                                .accessibilityIdentifier(AccessibilityID.privacyCopyID)
                        }
                    }
                }
            } else if store.crashStartsAtNextLaunch {
                caption(
                    "Crash reporting starts the next time you open Segue.",
                    id: AccessibilityID.privacyRestartCaption,
                )
            }
        }

        private func caption(_ text: String, id: String) -> some View {
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id)
        }

        private func binding(_ toggle: ConsentStore.Toggle) -> Binding<Bool> {
            Binding(
                get: { store.isGranted(toggle) },
                set: { store.set($0, for: toggle, source: .settings) },
            )
        }

        private static func copy(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        // MARK: Copy (spec 4.3, A4, R32)

        static let analyticsStopped = "Segue has stopped sending usage analytics and deleted "
            + "anything waiting to be sent. Analytics already sent are anonymous and "
            + "TelemetryDeck keeps them with no fixed deletion date. The install identifier is "
            + "hashed on this Mac and again by TelemetryDeck, so they cannot be traced back to "
            + "you or singled out for deletion. Questions: \(SegueLinks.supportAddress)."

        static func crashStopped(hasID: Bool) -> String {
            let base = "Segue has stopped sending crash reports and deleted any waiting to be "
                + "sent. Reports already sent are kept by Sentry for 30 days. To have them "
                + "deleted sooner, email \(SegueLinks.supportAddress)"
            return hasID ? base + " with your Diagnostics ID:" : base + "."
        }

        static let bugReportsNote = "Bug reports are sent only when you press Send, and you "
            + "see everything first."
    }
#endif
