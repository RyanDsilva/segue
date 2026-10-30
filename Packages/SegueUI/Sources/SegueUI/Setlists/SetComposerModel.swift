import Foundation
import Library
import Observation
import Services
import Setlists

/// The set composer's state (P8-5 section 8.3): the line as typed, what it resolves to,
/// which alternative is shown, and the matcher built from the library catalog. The view
/// only renders this; every decision is pure (`SetComposer`, `SongMatcher`).
///
/// Nothing here ever rewrites the typed text: matching normalizes only inside the
/// comparison, so romanized Hindi stays exactly as the user spelled it.
@MainActor
@Observable
public final class SetComposerModel {
    /// The line exactly as typed.
    public private(set) var text = ""
    /// What `text` means against the library.
    public private(set) var resolution = SetComposerResolution.empty
    /// The alternative shown as the ghost (0 = the best match).
    public private(set) var choice = 0
    /// The alternatives list under the row is open (after the first ↓ / Tab).
    public private(set) var showsAlternatives = false
    /// Bumped by Setlist > Add Song by Name (⌘L); the field takes focus when it changes.
    public private(set) var focusRequest = 0
    /// Bumped to put the text field's whole text selected (the duplicate block).
    public private(set) var selectAllRequest = 0
    /// Whether the text field has keyboard focus.
    public private(set) var isFocused = false
    /// The row the duplicate block points at, flashed briefly.
    public internal(set) var highlighted: SetlistItemID?

    @ObservationIgnored private var matcher: SongMatcher?
    @ObservationIgnored private var matcherRevision: Int?
    /// How this focus session started (analytics).
    @ObservationIgnored private(set) var entry = ComposerEntry.click
    @ObservationIgnored private var pendingShortcut = false
    @ObservationIgnored private(set) var sessionSongs = 0
    @ObservationIgnored private(set) var sessionCycles = 0
    @ObservationIgnored private var sessionReturns = 0
    /// The Return in flight: the set write runs after the key handler returns.
    @ObservationIgnored private var acceptInFlight: Task<Void, Never>?

    public init() {}

    /// The candidate the ghost shows, if any.
    public var chosen: SongMatch? {
        resolution.matches.indices.contains(choice) ? resolution.matches[choice] : nil
    }

    // MARK: Text and matching

    /// The user typed: re-resolves against `library` (rebuilding the matcher when the
    /// catalog changed) and resets the cycle to the new best match.
    func setText(_ newText: String, library: LibraryViewModel) {
        text = newText
        choice = 0
        showsAlternatives = false
        resolve(library: library)
    }

    /// Re-resolves the current text (the catalog may have changed).
    func refresh(library: LibraryViewModel) {
        guard matcherRevision != library.catalogRevision else { return }
        resolve(library: library)
        if !resolution.matches.indices.contains(choice) {
            choice = 0
        }
    }

    private func resolve(library: LibraryViewModel) {
        let matcher = ensureMatcher(library: library)
        resolution = SetComposer.resolve(
            SetComposerLine.parse(text),
            rawText: text,
            matcher: matcher,
        )
    }

    /// The matcher over the library catalog, rebuilt when `catalogRevision` changes
    /// (section 6.7): never SQLite per keystroke.
    private func ensureMatcher(library: LibraryViewModel) -> SongMatcher {
        if let matcher, matcherRevision == library.catalogRevision {
            return matcher
        }
        let built = SongMatcher(candidates: library.catalog.map(MatchCandidate.init(record:)))
        matcher = built
        matcherRevision = library.catalogRevision
        return built
    }

    /// The text cleared after an add.
    func clear() {
        text = ""
        resolution = .empty
        choice = 0
        showsAlternatives = false
    }

    // MARK: Keys

    /// ↓ / Tab (+1) or ↑ / ⇧Tab (-1): the next or previous alternative, wrapping, when the
    /// line has two or more. Returns whether the key was used (with text present, Tab is
    /// always swallowed so focus never leaves on Tab).
    func cycle(by delta: Int) -> Bool {
        let count = resolution.matches.count
        guard count >= 2 else { return false }
        choice = ((choice + delta) % count + count) % count
        showsAlternatives = true
        sessionCycles += 1
        return true
    }

    /// Picks alternative `index` (a click in the alternatives list).
    func choose(_ index: Int) {
        guard resolution.matches.indices.contains(index) else { return }
        choice = index
    }

    /// What Escape did.
    enum EscapeResult: Equatable {
        case closedAlternatives
        case cleared
        /// The line was empty: focus goes to the set list.
        case leave
    }

    /// Escape: close the alternatives, else clear the line, else leave.
    func escape() -> EscapeResult {
        if showsAlternatives {
            showsAlternatives = false
            return .closedAlternatives
        }
        if !text.isEmpty {
            clear()
            return .cleared
        }
        return .leave
    }

    // MARK: Focus

    /// ⌘L: focus the composer (the text stays).
    public func requestFocus() {
        pendingShortcut = true
        focusRequest += 1
    }

    func requestSelectAll() {
        selectAllRequest += 1
    }

    /// The field gained or lost keyboard focus. Leaving after at least one Return ends a
    /// composer session and returns its counts for `Segue.Setlist.composerSession`.
    func focusChanged(_ focused: Bool) -> (songs: Int, cycles: Int)? {
        guard focused != isFocused else { return nil }
        isFocused = focused
        if focused {
            entry = pendingShortcut ? .shortcut : .click
            pendingShortcut = false
            sessionSongs = 0
            sessionCycles = 0
            sessionReturns = 0
            return nil
        }
        showsAlternatives = false
        defer {
            sessionSongs = 0
            sessionCycles = 0
            sessionReturns = 0
        }
        return sessionReturns > 0 ? (sessionSongs, sessionCycles) : nil
    }

    /// A Return was handled with `outcome`.
    /// Keeps the Return's write task so it can be awaited.
    func track(accept task: Task<Void, Never>) {
        acceptInFlight = task
    }

    /// Returns once the last Return has been written and applied (tests await this
    /// instead of polling the setlist against a wall-clock deadline).
    func awaitAccept() async {
        await acceptInFlight?.value
    }

    func noteReturn(_ outcome: ComposeOutcome) {
        switch outcome {
        case .added:
            sessionReturns += 1
            sessionSongs += 1
        case .alreadyInSet, .breakAdded, .noMatch:
            sessionReturns += 1
        case .ignored:
            break
        }
    }
}
