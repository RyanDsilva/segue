import AppKit
import Plugins
import SegueUI
import SwiftUI
import UniformTypeIdentifiers

/// The New Song sheet's web address field (spec 11.3, R198 direction A): a single-line field
/// above the paste area with Import and a help button; while reading, a spinner with Cancel;
/// a failure's message and actions under it (spec 8.7). Autocorrect off.
struct WebImportField: View {
    @Bindable var model: WebImportModel
    let host: ImportHost
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(
                    "Web address",
                    text: $model.address,
                    prompt: Text(verbatim: "Or paste a page address (https://…)"),
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($focused)
                .disabled(model.isReading)
                .onSubmit { model.importAddress() }
                .accessibilityLabel("Web page address")
                .accessibilityIdentifier(AccessibilityID.pasteWebField)
                if model.isReading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Reading the page")
                    Button("Cancel") { model.cancel() }
                        .buttonStyle(.segueSecondary)
                } else {
                    Button("Import") { model.importAddress() }
                        .buttonStyle(.seguePrimary)
                        .disabled(!model.canImport)
                        .accessibilityIdentifier(AccessibilityID.pasteWebImport)
                }
                ImportHelpButton(topic: .webPage)
                    .accessibilityIdentifier(AccessibilityID.pasteWebHelp)
            }
            if case let .failed(message) = model.state, !message.text.isEmpty {
                ImportMessageView(message: message) { action in
                    Task { await model.perform(action, chooseFile: SavedPagePanel.choose) }
                }
                .accessibilityIdentifier(AccessibilityID.pasteWebMessage)
            }
        }
        .onAppear {
            model.attach(host)
            focused = host.review.focusesWebField
            model.readPending()
        }
        .onChange(of: host.review.pendingWebInput) { _, input in
            if input != nil {
                model.readPending()
            }
        }
        .onDisappear { model.cancel() }
        .sheet(item: $model.openHere) { request in
            OpenHereSheet(url: request.url, source: model.challenges) { cleared in
                model.openHereFinished(cleared: cleared)
            }
        }
    }
}

/// A page Open Here shows.
struct OpenHereRequest: Identifiable, Equatable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

/// A failure's message and its actions (spec 6.8, 8.7): announced to VoiceOver.
struct ImportMessageView: View {
    let message: ImportCopy.Message
    let perform: (ImportCopy.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.color.muted)
                Text(verbatim: message.text)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(SchibstedGrotesk.medium.font(size: 12.5))
            .foregroundStyle(Theme.color.ink)
            if !message.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.actions, id: \.self) { action in
                        Button(action.title) { perform(action) }
                            .buttonStyle(.segueSecondary)
                            .controlSize(.small)
                            .accessibilityIdentifier(action == .openHere
                                ? AccessibilityID.webOpenHere : AccessibilityID.pasteWebAction)
                    }
                }
            }
        }
        .onAppear {
            AccessibilityNotification.Announcement(message.text).post()
        }
    }
}

/// Import a Saved Page… (spec 8.1, 8.6): an open panel for `.html`, `.htm` and
/// `.webarchive` files.
enum SavedPagePanel {
    static let extensions = ["html", "htm", "webarchive"]

    @MainActor
    static func choose() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import a Saved Page"
        panel.prompt = "Import"
        panel.message = "Save the page in Safari with File > Save As, then choose it here."
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.url : nil
    }
}
