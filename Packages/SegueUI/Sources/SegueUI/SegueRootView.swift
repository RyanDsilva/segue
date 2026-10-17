import SwiftUI

/// Root of the app's main window. Phase 0 placeholder: the sidebar (Library, Setlists),
/// editor and live view replace this body.
public struct SegueRootView: View {
    public init() {}

    public var body: some View {
        Text("Segue")
            .font(.largeTitle.weight(.heavy))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(AccessibilityID.rootTitle)
    }
}

/// Accessibility identifiers shared by views and XCUITests.
public enum AccessibilityID {
    /// The placeholder title in `SegueRootView`.
    public static let rootTitle = "segue.root.title"
}

#Preview {
    SegueRootView()
}
