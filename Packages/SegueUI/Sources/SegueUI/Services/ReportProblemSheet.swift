#if os(macOS)
    import AppKit
    import Services
    import SwiftUI

    /// Help > Report a Problem (WS3 spec 8.2-8.4): the form, then the full preview of exactly
    /// what is sent, sending, and the email / save-to-folder fallbacks.
    struct ReportProblemSheet: View {
        @Bindable var model: ReportProblemModel
        let workspace: any WorkspaceActions
        let onRequestFeature: () -> Void
        let onClose: () -> Void
        var height: CGFloat = Self.idealHeight

        static let width: CGFloat = 560
        static let idealHeight: CGFloat = 640
        static let minimumHeight: CGFloat = 420

        /// The ideal height, or less in a window too short for it (the content scrolls).
        static func height(fitting host: CGSize) -> CGFloat {
            guard host.height > 0 else { return idealHeight }
            return max(minimumHeight, min(idealHeight, host.height - 48))
        }

        var body: some View {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 12)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(Theme.color.line)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                ReportButtonBar(model: model, onClose: onClose)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            }
            .frame(width: Self.width, height: height)
            .background(Theme.color.ground)
            .task { await model.load() }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.reportSheet)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var title: String {
            switch model.phase {
            case .editing, .sent: "Report a Problem"
            case .failed: "The Report Was Not Sent"
            case .preview, .sending: "Everything This Report Sends"
            }
        }

        private var subtitle: String {
            switch model.phase {
            case .editing:
                "Tell us what happened. You will see everything before it is sent."
            case .failed:
                "Nothing has left your Mac. The report below is kept until you send it."
            case .preview, .sending:
                "Nothing else is sent: no other files, no identifiers, nothing from your library."
            case .sent:
                "Thank you for taking the time."
            }
        }

        @ViewBuilder private var content: some View {
            switch model.phase {
            case .editing:
                ReportForm(model: model, onRequestFeature: onRequestFeature)
            case let .failed(_, payload), let .preview(payload), let .sending(payload):
                ReportPreviewView(
                    payload: payload,
                    trimmedLogs: model.trimmedLogs,
                    workspace: workspace,
                )
            case let .sent(eventID):
                ReportSentView(eventID: eventID)
            }
        }
    }

    /// The form (spec 8.2): description with a counter, optional email, attachments.
    private struct ReportForm: View {
        @Bindable var model: ReportProblemModel
        let onRequestFeature: () -> Void

        var body: some View {
            Form {
                Section(uiString("What happened?")) {
                    PlainTextEditor(
                        text: $model.message,
                        accessibilityIdentifier: AccessibilityID.reportMessage,
                        accessibilityLabel: "What happened?",
                    )
                    .frame(height: 100)
                    HStack(alignment: .firstTextBaseline) {
                        if let problem = model.problem {
                            Text(problem)
                                .foregroundStyle(Theme.color.cueText)
                                .accessibilityIdentifier(AccessibilityID.reportProblem)
                        } else if model.isOverLimit {
                            Text("Shorten the description to 4,096 characters.", bundle: #bundle)
                                .foregroundStyle(Theme.color.cueText)
                        }
                        Spacer()
                        Text(
                            "\(model.messageCount.formatted()) / "
                                + ReportProblemModel.messageLimit.formatted(),
                        )
                        .monospacedDigit()
                        .foregroundStyle(
                            model.isOverLimit ? Theme.color.cueText : Theme.color.muted,
                        )
                        .accessibilityLabel(uiString("""
                        \(model.messageCount) of \(ReportProblemModel.messageLimit) characters
                        """))
                        .accessibilityIdentifier(AccessibilityID.reportCounter)
                    }
                    .font(.callout)
                }
                Section {
                    TextField(
                        uiString("Email (optional)"),
                        text: $model.email,
                        prompt: Text("you@example.com", bundle: #bundle),
                    )
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(AccessibilityID.reportEmail)
                } footer: {
                    Text(model.isEmailValid
                        ? "Only if you want a reply."
                        : "That does not look like an email address.")
                        .font(.callout)
                        .foregroundStyle(model.isEmailValid ? Theme.color.muted : Theme.color
                            .cueText)
                }
                Section(uiString("Attach")) {
                    attachments
                }
                Section {
                    Text(Self.alwaysIncluded)
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(
                        uiString("Have an idea instead? Request a Feature"),
                        action: onRequestFeature,
                    )
                    .buttonStyle(.appLink)
                    .font(.callout)
                    .accessibilityIdentifier(AccessibilityID.reportRequestFeature)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }

        @ViewBuilder private var attachments: some View {
            attachToggle(
                "Recent Segue logs (last 4 launches)",
                isOn: $model.attachLogs,
                unavailable: model.logs.isEmpty ? "No logs yet" : nil,
                id: AccessibilityID.reportAttachLogs,
            )
            attachToggle(
                "Latest crash or hang diagnostics (MetricKit)",
                isOn: $model.attachMetricKit,
                unavailable: model.metricKit == nil ? "None recorded" : nil,
                id: AccessibilityID.reportAttachMetricKit,
            )
            attachToggle(
                model.song.map { "Current song file, “\($0.title)” (includes lyrics)" }
                    ?? "Current song file (includes lyrics)",
                isOn: $model.attachSong,
                unavailable: model.song == nil ? "No song selected" : nil,
                id: AccessibilityID.reportAttachSong,
            )
        }

        private func attachToggle(
            _ title: String,
            isOn: Binding<Bool>,
            unavailable: String?,
            id: String,
        ) -> some View {
            Toggle(isOn: unavailable == nil ? isOn : .constant(false)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let unavailable {
                        Text(unavailable)
                            .font(.callout)
                            .foregroundStyle(Theme.color.muted)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .disabled(unavailable != nil)
            .accessibilityIdentifier(id)
        }

        static let alwaysIncluded = "Always included: app version and build, macOS version, "
            + "Mac model, processor, preferred language, library size as ranges and your "
            + "privacy choices. Preview shows every byte before anything is sent."
    }

    /// "Thanks - report sent." with the copyable report ID.
    private struct ReportSentView: View {
        let eventID: String

        var body: some View {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                Text("Thanks - report sent.", bundle: #bundle)
                    .font(SchibstedGrotesk.semiBold.font(size: 17))
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityIdentifier(AccessibilityID.reportSent)
                Text("If you write to us about it, mention this report ID:", bundle: #bundle)
                    .font(.callout)
                    .foregroundStyle(Theme.color.muted)
                HStack(spacing: 8) {
                    Text(eventID)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    Button(uiString("Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(eventID, forType: .string)
                    }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                }
            }
            .padding(24)
        }
    }

    /// The bottom bar: what can be done in each phase.
    private struct ReportButtonBar: View {
        @Bindable var model: ReportProblemModel
        let onClose: () -> Void

        var body: some View {
            HStack(spacing: 10) {
                switch model.phase {
                case .editing:
                    emailInstead
                    Spacer()
                    cancel
                    Button(uiString("Preview…")) { model.preview() }
                        .buttonStyle(.segueSecondary)
                        .disabled(!model.canSend)
                        .accessibilityIdentifier(AccessibilityID.reportPreviewButton)
                    Button(uiString("Send")) { model.sendFromForm() }
                        .buttonStyle(.seguePrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canSend)
                        .accessibilityIdentifier(AccessibilityID.reportSend)
                case let .preview(payload):
                    back
                    Spacer()
                    cancel
                    Button(uiString("Send")) { model.send(payload) }
                        .buttonStyle(.seguePrimary)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.reportSend)
                case .sending:
                    ProgressView()
                        .controlSize(.small)
                    Text("Sending…", bundle: #bundle)
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                    Spacer()
                case .failed:
                    failure
                case .sent:
                    Spacer()
                    Button(uiString("OK"), action: onClose)
                        .buttonStyle(.seguePrimary)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.reportDone)
                }
            }
        }

        private var failure: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.mailUnavailable
                    ? "Couldn’t send right now, and no email account is set up. Save the "
                    + "report and send it from your browser instead."
                    : "Couldn’t send right now. Email it instead, save it to send later, or "
                    + "try again.")
                    .font(.callout)
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.reportFailure)
                HStack(spacing: 10) {
                    emailInstead
                    Button(uiString("Save Report…")) { Task { await model.saveReport() } }
                        .buttonStyle(.segueSecondary)
                        .accessibilityIdentifier(AccessibilityID.reportSaveReport)
                    Spacer()
                    cancel
                    Button(uiString("Try Again")) { model.tryAgain() }
                        .buttonStyle(.seguePrimary)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.reportTryAgain)
                }
            }
        }

        private var emailInstead: some View {
            Button(uiString("Email Instead")) { model.emailInstead() }
                .buttonStyle(.segueSecondary)
                .accessibilityIdentifier(AccessibilityID.reportEmailInstead)
        }

        private var back: some View {
            Button(uiString("Back")) { model.backToForm() }
                .buttonStyle(.segueSecondary)
                .accessibilityIdentifier(AccessibilityID.reportBack)
        }

        private var cancel: some View {
            Button(uiString("Cancel"), role: .cancel, action: onClose)
                .buttonStyle(.segueSecondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AccessibilityID.reportCancel)
        }
    }
#endif
