import CoreText
import Foundation

/// Registers the Schibsted Grotesk TTFs shipped in this package's resource bundle.
enum FontRegistration {
    /// Registration runs once per process; later calls return the cached outcome.
    private static let result: Bool = {
        // SwiftPM keeps the `Fonts` folder; tolerate a flattened bundle too.
        let urls = ["Fonts", nil].flatMap { folder in
            Theme.bundle.urls(forResourcesWithExtension: "ttf", subdirectory: folder) ?? []
        }
        guard !urls.isEmpty else { return false }
        var allRegistered = true
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered (by an earlier call or a test host) counts as success.
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    allRegistered = false
                }
            }
        }
        return allRegistered
    }()

    static func registerBundledFonts() -> Bool {
        result
    }
}
