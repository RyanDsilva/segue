#if os(macOS)
    import Services
    import SwiftUI

    extension EnvironmentValues {
        /// Where a shared control sits, for `featureUsed` rows recorded inside it (the song
        /// card: library by default, the editor's strip says otherwise).
        @Entry var analyticsContext: FeatureContext = .library
    }
#endif
