import SwiftUI

/// Opens Settings on the Instrument pane (the editor's "Bass, BEADG" menu, P8-4 6.5); set by
/// the root view, which owns the selected pane.
struct OpenInstrumentSettingsAction {
    let open: @MainActor () -> Void

    @MainActor
    func callAsFunction() {
        open()
    }
}

extension EnvironmentValues {
    @Entry var openInstrumentSettings: OpenInstrumentSettingsAction?
}
