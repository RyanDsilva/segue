// R35 probe (docs/release/specs/WS1-release-pipeline.md 4.10, section 5 step 8).
//
// Usage: ShortcutsEventsProbe <shortcut name> <event|permission>
//   permission: only AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true).
//   event:      the production Path SE send (4.8d): a non-prompting permission check, then
//               the Shortcuts Events `run` Apple event sent with NSAppleEventDescriptor.sendEvent.
// Prints exactly one JSON line. Launch through run.sh (LaunchServices) so TCC attributes the
// Automation request to this app rather than to Terminal.

import AppKit
import Foundation

let shortcutsEventsBundleID = "com.apple.shortcuts.events"

func fourCharCode(_ string: String) -> FourCharCode {
    string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
}

func frontmostBundleID() -> Any {
    // The process has no NSApplication run loop, so give NSWorkspace a moment to observe
    // activation changes before reading it.
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? NSNull()
}

func emit(_ fields: [String: Any]) {
    let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    print(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"error\":\"json\"}")
    fflush(stdout)
}

let arguments = CommandLine.arguments
guard arguments.count == 3, ["event", "permission"].contains(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: ShortcutsEventsProbe <name> <event|permission>\n".utf8))
    exit(2)
}
let name = arguments[1]
let mode = arguments[2]

let target = NSAppleEventDescriptor(bundleIdentifier: shortcutsEventsBundleID)

func determinePermission(askUserIfNeeded: Bool) -> OSStatus {
    guard let address = target.aeDesc else { return OSStatus(paramErr) }
    return AEDeterminePermissionToAutomateTarget(
        address, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUserIfNeeded
    )
}

/// `shortcut "<name>"`: an object specifier of class `srct`, form `name`, null container.
func shortcutSpecifier(named name: String) -> NSAppleEventDescriptor? {
    let record = NSAppleEventDescriptor.record()
    record.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharCode("srct")), forKeyword: AEKeyword(keyAEDesiredClass))
    record.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formName)), forKeyword: AEKeyword(keyAEKeyForm))
    record.setDescriptor(NSAppleEventDescriptor(string: name), forKeyword: AEKeyword(keyAEKeyData))
    record.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
    return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))
}

var fields: [String: Any] = [
    "name": name,
    "mode": mode,
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "errorNumber": NSNull(),
    "errorMessage": NSNull(),
    "result": NSNull(),
]
fields["frontmostBefore"] = frontmostBundleID()
let start = ContinuousClock.now

if mode == "permission" {
    let status = determinePermission(askUserIfNeeded: true)
    fields["permission"] = Int(status)
} else {
    // Path SE: during a show the app checks without prompting and fails fast if not granted.
    let status = determinePermission(askUserIfNeeded: false)
    fields["permission"] = Int(status)
    if status != noErr {
        fields["errorMessage"] = "not sent: permission check returned \(status) (production maps this to .failed)"
    } else if let specifier = shortcutSpecifier(named: name) {
        let event = NSAppleEventDescriptor(
            eventClass: fourCharCode("srct"),
            eventID: fourCharCode("run "),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(specifier, forKeyword: AEKeyword(keyDirectObject))
        do {
            let reply = try event.sendEvent(options: [.waitForReply], timeout: 60)
            // sendEvent normally throws for an error reply; read the reply's error keys too so
            // a failure reported only in the reply is not mistaken for success.
            if let number = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)) {
                fields["errorNumber"] = Int(number.int32Value)
                fields["errorMessage"] = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue ?? NSNull()
            }
            if let result = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) {
                fields["result"] = result.stringValue ?? result.description
            }
        } catch let error as NSError {
            fields["errorNumber"] = error.code
            fields["errorMessage"] = "\(error.domain): \(error.localizedDescription) \(error.userInfo)"
        }
    } else {
        fields["errorMessage"] = "could not build the object specifier"
    }
}

let elapsed = ContinuousClock.now - start
fields["seconds"] = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
fields["frontmostAfter"] = frontmostBundleID()
emit(fields)
