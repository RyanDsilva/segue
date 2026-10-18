#if os(macOS)
    import Foundation
    import MetricKit
    import Services

    /// Keeps the newest MetricKit diagnostic payload on this Mac for bug reports (WS3 spec
    /// 8.5). Subscribed at launch whatever the consent: MetricKit delivery is local and
    /// storing it is not collection. Sentry's own MetricKit integration is a separate
    /// subscriber and runs only with crash-report consent.
    public final class MetricKitCollector: NSObject, MXMetricManagerSubscriber, Sendable {
        private let store: DiagnosticStore

        public init(store: DiagnosticStore) {
            self.store = store
            super.init()
        }

        /// Starts receiving payloads.
        public func subscribe() {
            MXMetricManager.shared.add(self)
        }

        /// Called on a MetricKit queue with the payloads delivered since the last call.
        public func didReceive(_ payloads: [MXDiagnosticPayload]) {
            guard let newest = payloads.max(by: { $0.timeStampEnd < $1.timeStampEnd }) else {
                return
            }
            let json = newest.jsonRepresentation()
            let store = store
            Task { await store.store(json) }
        }
    }
#endif
