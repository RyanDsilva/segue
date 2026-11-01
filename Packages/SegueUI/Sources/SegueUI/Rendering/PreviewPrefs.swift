#if os(macOS)
    import Foundation
    import Observation
    import Services

    /// The library and editor previews' own singer toggle (P9-2 section 7, R178): one
    /// remembered per-machine value shared by both, separate from the stage's
    /// `LiveSettings.singerView`, so previewing a song for a singer never turns the owner's
    /// stage into singer view. Never synced, never in the library folder.
    @MainActor
    @Observable
    public final class PreviewPrefs {
        /// The UserDefaults key of `singer`.
        public static let singerKey = "segue.preview.singer"

        /// Whether the previews draw lyrics only (`SingerView`).
        public private(set) var singer: Bool {
            didSet {
                defaults.set(singer, forKey: Self.singerKey)
            }
        }

        /// Records analytics events (WS3 spec 5); the app hands over its hub.
        @ObservationIgnored public var services: ServicesHub = .disabled
        @ObservationIgnored private let defaults: UserDefaults

        public init(defaults: UserDefaults) {
            self.defaults = defaults
            singer = defaults.bool(forKey: Self.singerKey)
        }

        /// The Chords / Singer control or Song > Singer Preview, from the library or the
        /// editor: switching on counts as that context's use of singer view.
        public func setSinger(_ on: Bool, from context: FeatureContext) {
            guard on != singer else { return }
            singer = on
            if on {
                services.record(.featureUsed(.singerView, context))
            }
        }
    }
#endif
