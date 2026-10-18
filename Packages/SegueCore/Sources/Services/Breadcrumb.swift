import Foundation

/// A crash-report breadcrumb (spec 3.6). Only two sources exist: an `AnalyticsEvent`
/// (category `segue`, message = the signal name, data = the same allowlisted params) and the
/// fixed app lifecycle crumbs. There is no public initialiser, so nothing else can become one.
public struct Breadcrumb: Sendable, Hashable {
    /// Always `segue`; the scrubber drops anything else.
    public let category: String
    public let message: String
    public let data: [String: String]

    public static let category = "segue"

    init(message: String, data: [String: String]) {
        category = Self.category
        self.message = message
        self.data = data
    }

    /// The breadcrumb matching an analytics event.
    public init(_ event: AnalyticsEvent) {
        let signal = event.render()
        self.init(message: signal.name, data: signal.params)
    }

    /// A lifecycle breadcrumb.
    public init(_ lifecycle: LifecycleCrumb) {
        self.init(message: lifecycle.rawValue, data: [:])
    }
}

/// App lifecycle moments recorded as breadcrumbs (never sent as analytics).
public enum LifecycleCrumb: String, Sendable, CaseIterable {
    case appLaunched = "app.launched"
    case appWillTerminate = "app.willTerminate"
    case stageEntered = "show.stage.entered"
    case stageExited = "show.stage.exited"
}
