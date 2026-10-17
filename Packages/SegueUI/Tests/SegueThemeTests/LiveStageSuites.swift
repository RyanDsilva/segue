import Testing

/// Every suite that puts up the stage. `StageWindowController` is process-wide (one stage
/// at a time, like the app), so these suites run one after another, never in parallel.
@Suite(.serialized)
enum StageWindowSuites {}
