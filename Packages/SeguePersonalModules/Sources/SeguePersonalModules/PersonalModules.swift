import Foundation
import Plugins
import SegueUI

/// Entry point of the restricted personal-build plugins. Registered by the app only when
/// `SEGUE_PERSONAL` is defined: the web page importer and the three song search sources
/// (P9-4 spec 6.9, 8; R182's fixed group order is the registry's).
public enum PersonalModules: PluginModule {
    public static func register(into registry: PluginRegistry) {
        let services = WebImportServices.live(userAgent: userAgent)
        registry.register(WebPageImporter(services: services))
        registry.register(UGSearchSource(services: services))
        registry.register(EChordsSearchSource(services: services))
        registry.register(LyricsSearchSource(services: services))
    }

    /// `Segue/<version> (+<the site>)`: requests identify as Segue (R179).
    static var userAgent: String {
        let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Segue/\(version) (+\(SegueLinks.site.absoluteString))"
    }
}
