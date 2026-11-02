import Foundation
@testable import SeguePersonalModules
import Testing

/// Spec 8.1: only public http(s) pages; private hosts refused before any request.
struct WebAddressTests {
    @Test(arguments: [
        "https://tabs.ultimate-guitar.com/tab/x/y-chords-1", "http://example.com/song",
        "https://www.e-chords.com/chords/a/b", "https://8.8.8.8/x",
    ])
    func `public pages are accepted`(text: String) throws {
        #expect(try WebAddress.validated(#require(URL(string: text))) != nil)
    }

    @Test(arguments: [
        "file:///etc/hosts", "ftp://example.com/a", "javascript:alert(1)", "https://localhost/a",
        "http://intranet/a", "http://10.0.0.5/a", "http://192.168.1.1/", "http://172.16.0.1/",
        "http://127.0.0.1:8080/", "http://169.254.1.1/", "http://[::1]/", "https://printer.local/",
        "http://100.64.0.1/", "http://0.0.0.0/",
    ])
    func `other addresses are refused`(text: String) {
        #expect(URL(string: text).flatMap(WebAddress.validated) == nil)
    }

    @Test
    func `a typed address without a scheme gets https`() {
        #expect(WebAddress.parse("  www.chordie.com/chord.pere/x  ")?.absoluteString
            == "https://www.chordie.com/chord.pere/x")
        #expect(WebAddress.parse("two words") == nil)
        #expect(WebAddress.parse("") == nil)
    }

    @Test
    func `redirects never downgrade to http`() throws {
        let https = try #require(URL(string: "https://a.com/x"))
        #expect(try WebAddress.allowsRedirect(
            from: https,
            to: #require(URL(string: "https://b.com/")),
        ))
        #expect(try !WebAddress.allowsRedirect(
            from: https,
            to: #require(URL(string: "http://a.com/x")),
        ))
        #expect(try WebAddress.allowsRedirect(
            from: #require(URL(string: "http://a.com")),
            to: https,
        ))
        #expect(try !WebAddress.allowsRedirect(
            from: https,
            to: #require(URL(string: "https://10.0.0.1/")),
        ))
    }

    @Test
    func `site hosts and suffix matching`() throws {
        #expect(try WebAddress
            .siteHost(#require(URL(string: "https://www.E-Chords.com/x"))) == "e-chords.com")
        #expect(WebAddress.host("tabs.ultimate-guitar.com", isWithin: "ultimate-guitar.com"))
        #expect(!WebAddress.host("notultimate-guitar.com", isWithin: "ultimate-guitar.com"))
    }
}
