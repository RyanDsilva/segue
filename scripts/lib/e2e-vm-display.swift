// Runs INSIDE the E2E guest VM: switches the main display to the HiDPI (2x) mode of
// <width>x<height> points, so captures come out Retina. scripts/e2e-vm.sh compiles it on the
// host and stages it as products/display-mode when E2E_VM_HIDPI is set; guest-run.sh calls it
// before the tests.
//
// Why a mode switch: Tart's `--display WxHpt` gives the guest a WxH pt display backed by 2x
// pixels, but macOS boots it at 1024x768 pt (2048x1536 px); the WxH pt 2x mode is listed and
// has to be chosen. `--display ...px` has no 2x modes at all (it is a 72 ppi panel).
//
// Usage: display-mode <width> <height>    exit 0 when the mode is current, 1 otherwise

import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let width = Int(arguments[1]), let height = Int(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: display-mode <width> <height>\n".utf8))
    exit(2)
}

let display = CGMainDisplayID()
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("display-mode: \(message)\n".utf8))
    exit(1)
}

func describe(_ mode: CGDisplayMode?) -> String {
    guard let mode else { return "none" }
    return "\(mode.width)x\(mode.height) pt, \(mode.pixelWidth)x\(mode.pixelHeight) px"
}

func isWanted(_ mode: CGDisplayMode) -> Bool {
    mode.width == width && mode.height == height && mode.pixelWidth == 2 * width
        && mode.pixelHeight == 2 * height
}

if let current = CGDisplayCopyDisplayMode(display), isWanted(current) {
    print("display-mode: already \(describe(current))")
    exit(0)
}

let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
guard let mode = modes.first(where: isWanted) else {
    let listed = modes.map(describe).joined(separator: "; ")
    fail("no \(width)x\(height) pt 2x mode (the clone needs --display \(width)x\(height)pt and "
        + "a Retina host screen); modes: \(listed)")
}

var config: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&config) == .success,
      CGConfigureDisplayWithDisplayMode(config, display, mode, nil) == .success,
      CGCompleteDisplayConfiguration(config, .permanently) == .success,
      let now = CGDisplayCopyDisplayMode(display), isWanted(now)
else {
    let now = describe(CGDisplayCopyDisplayMode(display))
    fail("switching to \(width)x\(height) pt 2x failed (now \(now))")
}

print("display-mode: \(describe(now))")
