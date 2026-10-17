import SwiftUI

public extension EnvironmentValues {
    /// True inside a selected list row (on the accent highlight): marks and chips draw in
    /// white instead of their token colours, which would not read there.
    @Entry var onHighlight = false
}
