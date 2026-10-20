#if os(macOS)
    import Services
    import SwiftUI

    extension EnvironmentValues {
        /// Where a shared control sits, for `featureUsed` rows recorded inside it (the song
        /// card's Time it: library by default, the editor's strip and the builder's
        /// missing-lengths list say otherwise).
        @Entry var analyticsContext: FeatureContext = .library
    }
#endif
