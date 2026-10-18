#if os(macOS)
    import Services
    import SwiftUI

    /// The report exactly as it will be sent (WS3 spec 8.3): the description, the email,
    /// every system-info field, and each attachment's name, size and full text. Nothing is
    /// summarised or elided; the frozen payload's bytes are what Send posts.
    struct ReportPreviewView: View {
        let payload: FeedbackPayload
        let trimmedLogs: Bool
        let workspace: any WorkspaceActions

        private var report: FeedbackReport {
            payload.report
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if trimmedLogs {
                        note("The logs were shortened to their newest lines to keep the report "
                            + "under 5 MB.")
                    }
                    block("What happened?") {
                        Text(report.message)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    block("Reply to") {
                        Text(report.email ?? "No email address")
                            .foregroundStyle(report.email == nil ? Theme.color.muted : Theme.color
                                .ink)
                            .textSelection(.enabled)
                    }
                    block("System info") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            ForEach(report.systemInfo.fields, id: \.key) { field in
                                GridRow {
                                    Text(field.label)
                                        .foregroundStyle(Theme.color.muted)
                                    Text(field.value)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    block(report.attachments.isEmpty
                        ? "No attachments"
                        : "Attachments (\(report.attachments.count))")
                    {
                        ForEach(Array(report.attachments.enumerated()), id: \.offset) { _, item in
                            AttachmentPreview(file: item.file)
                        }
                    }
                    footer
                }
                .font(.callout)
                .foregroundStyle(Theme.color.ink)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier(AccessibilityID.reportPreview)
            .overlay(alignment: .bottomTrailing) { hashMarker }
        }

        private func block(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityAddTraits(.isHeader)
                content()
            }
        }

        private func note(_ text: String) -> some View {
            Text(text)
                .foregroundStyle(Theme.color.muted)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.color.surfaceAlt, in: RoundedRectangle(cornerRadius: 8))
        }

        private var footer: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sent to Sentry (\(SegueLinks.bugReportServiceHost), United States), "
                    + "Segue’s crash and bug-report service. Kept for 30 days.")
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                PolicyLink(workspace: workspace)
            }
            .padding(.top, 4)
        }

        /// UI testing only: the payload's hash, so E2E can prove the sent bytes are these.
        @ViewBuilder private var hashMarker: some View {
            if UITesting.isActive {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(payload.sha256)
                    .accessibilityIdentifier(AccessibilityID.reportPreviewHash)
            }
        }
    }

    /// One attachment: name and size, and its full text when expanded.
    private struct AttachmentPreview: View {
        let file: DiagnosticFile
        @State private var isExpanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(Theme.color.muted)
                            .frame(width: 12)
                        Text(file.name)
                            .font(.callout.monospaced())
                        Spacer()
                        Text(file.data.count.formatted(.byteCount(style: .file)))
                            .foregroundStyle(Theme.color.muted)
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(file.name)
                .accessibilityValue(isExpanded ? "expanded" : "collapsed")
                .accessibilityHint("Shows the file's full text")
                .accessibilityIdentifier(AccessibilityID.reportPreviewAttachment)
                if isExpanded {
                    ScrollView([.vertical, .horizontal]) {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(height: 220)
                    .background(Theme.color.surfaceAlt, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }

        private var text: String {
            String(bytes: file.data, encoding: .utf8)
                ?? "This file is not UTF-8 text. It is sent exactly as it is on disk."
        }
    }
#endif
