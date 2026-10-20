#if os(macOS)
    import Library
    import SwiftUI

    extension EnvironmentValues {
        /// The library's smart filters, for the set assistant's "from <filter>" chips. The
        /// root view supplies it; previews and tests leave it empty.
        @Entry var smartFilterList: [SmartFilter] = []
    }
#endif
