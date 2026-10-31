#if os(macOS)
    import Library
    import SwiftUI

    extension EnvironmentValues {
        /// The library's smart filters, for the set assistant's "from <filter>" chips. The
        /// root view supplies it; previews and tests leave it empty.
        @Entry var smartFilterList: [SmartFilter] = []
        /// The library's artists and Movie / Album values (most songs first), for the
        /// editor strip's suggestions (P8-8 section 3.3); empty outside the library.
        @Entry var libraryNames = LexiconCredits()
    }
#endif
