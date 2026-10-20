import ChordPro
import Editing
import Foundation
import Library
import Services
import Setlists

// The song card's Length row (R91, spec 16.0.1): an `m:ss` field plus "Time it". P3-10
// embeds it in the card and P3-12 in the missing-lengths popover; both commit through
// `EditOperation.setLength` (one undoable `{duration}` edit).

public extension AccessibilityID {
    /// The song card's Length field.
    static let songCardLength = "segue.songCard.length"
    /// The Length row's Time it / Stop button.
    static let songCardTimeIt = "segue.songCard.timeIt"
}

public extension EditOperation {
    /// Writes a song length as `{duration: m:ss}` (`h:mm:ss` from an hour); nil, or a length
    /// that rounds to zero, removes the directive.
    static func setLength(_ seconds: TimeInterval?) -> EditOperation {
        .setDirective(name: "duration", value: seconds.flatMap(LengthValue.init(seconds:))?.text)
    }
}

/// What committing the Length field's text does.
enum LengthCommit: Equatable {
    /// The text says what the song already has: no edit (and no undo step).
    case unchanged
    /// Write this length; nil clears it.
    case write(TimeInterval?)
    /// Not a length: the field shows the message and nothing reaches the file.
    case rejected(String)

    /// The commit for `text` on a song whose current length is `current`.
    static func of(_ text: String, current: TimeInterval?) -> Self {
        let typed: LengthValue?
        do {
            typed = try LengthValue.parse(text)
        } catch {
            return .rejected(error.message)
        }
        let known = current.flatMap(LengthValue.init(seconds:))
        guard typed != known else { return .unchanged }
        return .write(typed?.interval)
    }

    /// The commit for a Time it run that lasted `seconds` (rounded).
    static func timed(_ seconds: Int, current: TimeInterval?) -> Self {
        guard let value = LengthValue(seconds: TimeInterval(seconds)) else {
            return .rejected(LengthValue.Problem.zero.message)
        }
        return value == current.flatMap(LengthValue.init(seconds:)) ? .unchanged
            : .write(value.interval)
    }
}

#if os(macOS)
    import SwiftUI

    /// The Length field and its Time it control. Return, focus leaving the field, and Stop
    /// commit; Esc cancels a run (or reverts typing). `onCommit` receives the new length in
    /// whole seconds, or nil to clear; hosts write it with `EditOperation.setLength`. Give
    /// the view `.id(songID)` when one card is reused across songs.
    public struct LengthField: View {
        let songID: SongID
        let length: TimeInterval?
        let timeIt: TimeItModel
        let externalFocus: FocusState<Bool>.Binding?
        let onCommit: (TimeInterval?) -> Void

        @State private var text: String
        @State private var problem: String?
        @FocusState private var ownFocus: Bool
        /// Where the card sits, for the Time it analytics row (library by default).
        @Environment(\.analyticsContext) private var analyticsContext

        /// - Parameters:
        ///   - songID: the song whose length this is (Time it runs are keyed to it).
        ///   - length: the song's current `{duration}` in seconds, nil when unknown.
        ///   - timeIt: the app-wide timer (tests inject their own).
        ///   - focus: an outside focus binding (the card's `focus(.length)` seam), if any.
        ///   - onCommit: called with the new length, or nil to clear it.
        public init(
            songID: SongID,
            length: TimeInterval?,
            timeIt: TimeItModel = .shared,
            focus: FocusState<Bool>.Binding? = nil,
            onCommit: @escaping (TimeInterval?) -> Void,
        ) {
            self.songID = songID
            self.length = length
            self.timeIt = timeIt
            externalFocus = focus
            self.onCommit = onCommit
            _text = State(initialValue: Self.text(for: length))
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    field
                    timeItButton
                }
                if let problem {
                    Text(problem)
                        .font(SchibstedGrotesk.medium.font(size: 11))
                        .foregroundStyle(Theme.color.cueText)
                        .accessibilityIdentifier(AccessibilityID.songCardLength + ".problem")
                }
            }
            .onExitCommand(perform: escape)
            .onChange(of: length) { _, new in
                guard !isFocused else { return }
                text = Self.text(for: new)
                problem = nil
            }
            .onChange(of: songID) { _, _ in
                text = Self.text(for: length)
                problem = nil
            }
        }

        private var focusBinding: FocusState<Bool>.Binding {
            externalFocus ?? $ownFocus
        }

        private var isFocused: Bool {
            focusBinding.wrappedValue
        }

        private var isTiming: Bool {
            timeIt.isTiming(songID)
        }

        private var field: some View {
            TextField("Length", text: $text, prompt: Text("m:ss"))
                .textFieldStyle(.roundedBorder)
                .font(SchibstedGrotesk.medium.font(size: 13).monospacedDigit())
                .frame(width: 72)
                .focused(focusBinding)
                .onSubmit(commitText)
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        commitText()
                    }
                }
                .onChange(of: text) { _, _ in problem = nil }
                .disabled(isTiming)
                .accessibilityLabel("Length")
                .accessibilityHint("Minutes and seconds, like 4:05")
                .accessibilityIdentifier(AccessibilityID.songCardLength)
        }

        @ViewBuilder private var timeItButton: some View {
            if isTiming, let run = timeIt.run {
                Button(action: stop) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(SetlistTiming.format(timeIt.elapsed().rounded(.down)))
                                .monospacedDigit()
                        }
                    }
                }
                .buttonStyle(.segueSecondary)
                .help("Stop and use the time as the length (Esc cancels)")
                .accessibilityLabel("Stop timing")
                .accessibilityValue(Self.spoken(timeIt.elapsed()))
                .accessibilityIdentifier(AccessibilityID.songCardTimeIt)
                .id(run.startedAt)
            } else {
                Button("Time It", systemImage: "stopwatch", action: start)
                    .buttonStyle(.segueSecondary)
                    .disabled(timeIt.isTimingOther(than: songID))
                    .help(timeIt.isTimingOther(than: songID)
                        ? "Another song is being timed: stop it first"
                        : "Time the song as you play it; Stop fills in the length")
                    .accessibilityIdentifier(AccessibilityID.songCardTimeIt)
            }
        }

        private func start() {
            guard timeIt.start(songID) else { return }
            problem = nil
            Self.announce("Timing started")
        }

        private func stop() {
            guard let seconds = timeIt.stop(songID) else { return }
            timeIt.recordTimed(in: analyticsContext)
            apply(LengthCommit.timed(seconds, current: length))
        }

        private func escape() {
            if isTiming {
                timeIt.cancel(songID)
                Self.announce("Timing cancelled")
            } else {
                text = Self.text(for: length)
                problem = nil
            }
        }

        private func commitText() {
            apply(LengthCommit.of(text, current: length))
        }

        private func apply(_ commit: LengthCommit) {
            switch commit {
            case .unchanged:
                text = Self.text(for: length)
                problem = nil
            case let .write(seconds):
                text = Self.text(for: seconds)
                problem = nil
                onCommit(seconds)
                Self.announce(seconds.map { "Length set to \(Self.spoken($0))" }
                    ?? "Length cleared")
            case let .rejected(message):
                problem = message
                Self.announce(message)
            }
        }

        static func text(for length: TimeInterval?) -> String {
            length.flatMap(LengthValue.init(seconds:))?.text ?? ""
        }

        /// "4 minutes, 5 seconds" for VoiceOver.
        static func spoken(_ seconds: TimeInterval) -> String {
            Duration.seconds(Int(seconds.rounded(.down)))
                .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        }

        private static func announce(_ message: String) {
            AccessibilityNotification.Announcement(message).post()
        }
    }
#endif
