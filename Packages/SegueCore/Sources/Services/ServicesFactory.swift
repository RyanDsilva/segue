import Foundation

/// Builds vendor adapters. `ServicesHub` calls a method only once the matching consent is
/// granted, so with consent undecided or declined no vendor code is ever touched.
public protocol ServicesFactory: Sendable {
    func makeAnalytics() -> any AnalyticsSink
    func makeCrashReporter() -> any CrashReporter
}
