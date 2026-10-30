import Observation

/// Whether a gig is running (P8-6 section 9). While it is on, no `SoundPlayer` can be made
/// and every sound control outside the stage is disabled ("Sound is off during a show").
@MainActor
@Observable
public final class SoundGate {
    public internal(set) var gigRunning = false

    /// The help a disabled sound control shows.
    public static let offHelp = "Sound is off during a show"

    public init() {}
}
