import AppKit
import Foundation

// QA-only logic checks for the parts of Grab Pic that can be verified without screen-recording
// permission, a GUI session, or the owner's real displays. Compile with the app's model,
// storage, and composer sources; this file provides its own entry point.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if condition {
        print("PASS  \(label)")
    } else {
        failures += 1
        let extra = detail()
        print("FAIL  \(label)\(extra.isEmpty ? "" : " — \(extra)")")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    check(actual == expected, label, "expected \(expected), got \(actual)")
}

// MARK: - Helpers

func makeImage(width: Int, height: Int, color: NSColor) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// Four quadrants: red top-left, green top-right, blue bottom-left, yellow bottom-right.
func makeQuadrantImage(width: Int, height: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let halfW = width / 2
    let halfH = height / 2
    context.setFillColor(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: halfH, width: halfW, height: height - halfH))
    context.setFillColor(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1).cgColor)
    context.fill(CGRect(x: halfW, y: halfH, width: width - halfW, height: height - halfH))
    context.setFillColor(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: halfW, height: halfH))
    context.setFillColor(NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1).cgColor)
    context.fill(CGRect(x: halfW, y: 0, width: width - halfW, height: halfH))
    return context.makeImage()!
}

struct RGB: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    var description: String { "rgb(\(r), \(g), \(b))" }
}

func pixel(in image: CGImage, x: Int, y: Int) -> RGB {
    var bytes = [UInt8](repeating: 0, count: 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: &bytes,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.translateBy(x: CGFloat(-x), y: CGFloat(y - (image.height - 1)))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return RGB(r: bytes[0], g: bytes[1], b: bytes[2])
}

let red = RGB(r: 255, g: 0, b: 0)
let green = RGB(r: 0, g: 255, b: 0)
let blue = RGB(r: 0, g: 0, b: 255)
let yellow = RGB(r: 255, g: 255, b: 0)
let gap = RGB(r: 0x10, g: 0x11, b: 0x17)

func near(_ a: RGB, _ b: RGB, tolerance: Int = 2) -> Bool {
    abs(Int(a.r) - Int(b.r)) <= tolerance &&
        abs(Int(a.g) - Int(b.g)) <= tolerance &&
        abs(Int(a.b) - Int(b.b)) <= tolerance
}

// MARK: - Date folders

let sampleDate = DateComponents(
    calendar: Calendar(identifier: .gregorian),
    timeZone: TimeZone(identifier: "UTC"),
    year: 2026, month: 10, day: 28, hour: 14, minute: 32
).date!

checkEqual(DateFolder.name(for: sampleDate, organization: 0), "2026-10-28", "daily folder name")
checkEqual(DateFolder.name(for: sampleDate, organization: 1), "2026-W44", "ISO week folder name")
checkEqual(DateFolder.name(for: sampleDate, organization: 2), "2026-10", "monthly folder name")

// MARK: - Saving

let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("grabpic-logic-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: temporary) }

let settings = CaptureSettings(folder: temporary, organization: 0, format: 0, quality: 100)
let image = makeImage(width: 40, height: 24, color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))

let firstURL = try CaptureStore.save(image, settings: settings, date: sampleDate)
let secondURL = try? CaptureStore.save(image, settings: settings, date: sampleDate)

let namePattern = "^Grab_\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2}-\\d{3}_[0-9a-z]{4}\\.png$"
check(
    firstURL.lastPathComponent.range(of: namePattern, options: .regularExpression) != nil,
    "capture name matches Grab_<date>_<time>-<ms>_<suffix>.png",
    firstURL.lastPathComponent
)
checkEqual(firstURL.deletingLastPathComponent().lastPathComponent, "2026-10-28", "capture filed under daily folder")

if let secondURL {
    check(secondURL != firstURL, "second capture in the same instant gets a distinct name")
} else {
    check(false, "second capture saved")
}

let storedData = try Data(contentsOf: firstURL)
checkEqual(Array(storedData.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG signature written")

let jpgSettings = CaptureSettings(folder: temporary, organization: 0, format: 1, quality: 72)
let jpgURL = try CaptureStore.save(image, settings: jpgSettings, date: sampleDate)
checkEqual(jpgURL.pathExtension, "jpg", "JPG format extension")
let jpgData = try Data(contentsOf: jpgURL)
checkEqual(Array(jpgData.prefix(2)), [0xFF, 0xD8], "JPEG signature written")

let metadata = ImageLoader.metadata(at: firstURL)
checkEqual(metadata?.pixelWidth ?? 0, 40, "saved pixel width")
checkEqual(metadata?.pixelHeight ?? 0, 24, "saved pixel height")

// MARK: - Cropping orientation

let primary = NSScreen.screens.first
let scale = primary?.backingScaleFactor ?? 2

let shot = DisplayShot(
    screenID: 1,
    frame: CGRect(x: 0, y: 0, width: 200, height: 100),
    scale: 2,
    image: makeQuadrantImage(width: 400, height: 200)
)

if let topLeft = ImageComposer.compose(shots: [shot], rect: CGRect(x: 0, y: 50, width: 100, height: 50)) {
    checkEqual(topLeft.width, 200, "single-display crop pixel width")
    checkEqual(topLeft.height, 100, "single-display crop pixel height")
    check(near(pixel(in: topLeft, x: 100, y: 50), red), "top-left selection keeps the top-left quadrant",
          pixel(in: topLeft, x: 100, y: 50).description)
} else {
    check(false, "single-display crop produced an image")
}

if let bottomRight = ImageComposer.crop(shot, to: CGRect(x: 100, y: 0, width: 100, height: 50)) {
    check(near(pixel(in: bottomRight, x: 100, y: 50), yellow), "bottom-right selection keeps the bottom-right quadrant",
          pixel(in: bottomRight, x: 100, y: 50).description)
} else {
    check(false, "bottom-right crop produced an image")
}

// MARK: - Multi-display composition

let leftShot = DisplayShot(
    screenID: 1,
    frame: CGRect(x: -160, y: 0, width: 160, height: 100),
    scale: 2,
    image: makeQuadrantImage(width: 320, height: 200)
)
let rightShot = DisplayShot(
    screenID: 2,
    frame: CGRect(x: 0, y: 0, width: 200, height: 100),
    scale: 1,
    image: makeQuadrantImage(width: 200, height: 100)
)

if let composed = ImageComposer.compose(shots: [leftShot, rightShot], rect: CGRect(x: -160, y: 50, width: 360, height: 50)) {
    checkEqual(composed.width, 720, "cross-display compose uses the highest scale")
    checkEqual(composed.height, 100, "cross-display compose height")
    check(near(pixel(in: composed, x: 80, y: 25), red), "left display contributes its top-left quadrant",
          pixel(in: composed, x: 80, y: 25).description)
    check(near(pixel(in: composed, x: 600, y: 25), green), "right display contributes its top-right quadrant",
          pixel(in: composed, x: 600, y: 25).description)
} else {
    check(false, "cross-display compose produced an image")
}

// A gap between displays stays quiet instead of smearing a neighbour.
let gapShot = DisplayShot(
    screenID: 3,
    frame: CGRect(x: 0, y: 0, width: 100, height: 100),
    scale: 2,
    image: makeQuadrantImage(width: 200, height: 200)
)
let farShot = DisplayShot(
    screenID: 4,
    frame: CGRect(x: 200, y: 0, width: 100, height: 100),
    scale: 2,
    image: makeQuadrantImage(width: 200, height: 200)
)
if let withGap = ImageComposer.compose(shots: [gapShot, farShot], rect: CGRect(x: 0, y: 0, width: 300, height: 100)) {
    checkEqual(withGap.width, 600, "gap compose width")
    check(near(pixel(in: withGap, x: 300, y: 100), gap), "uncovered space is filled with the quiet gap colour",
          pixel(in: withGap, x: 300, y: 100).description)
} else {
    check(false, "gap compose produced an image")
}

// MARK: - Shortcuts

checkEqual(ShortcutBinding.ctrlShift(18).label, "⌃⇧1", "compact shortcut label")
checkEqual(
    ShortcutBinding(keyCode: 18, modifiers: ShortcutBinding.command | ShortcutBinding.control).label,
    "⌃⌘1",
    "shortcut label order"
)
check(ShortcutBinding.ctrlShift(18).validationError() == nil, "⌃⇧1 is accepted")
check(ShortcutBinding(keyCode: 0, modifiers: 0).validationError() != nil, "bare letter is declined")
check(ShortcutBinding(keyCode: 122, modifiers: 0).validationError() == nil, "bare function key is accepted")
check(ShortcutBinding(keyCode: 12, modifiers: ShortcutBinding.command).validationError() != nil, "⌘Q is reserved")
check(ShortcutBinding(keyCode: 55, modifiers: 0).validationError() != nil, "modifier-only press is declined")
check(ShortcutBinding.ctrlShift(18).hasModifier, "modifier detection")

// MARK: - Preferences

let profile = temporary.appendingPathComponent("profile", isDirectory: true)
setenv("GRABPIC_PROFILE_DIRECTORY", profile.path, 1)

let preferences = Preferences()
checkEqual(preferences.quality, 100, "default JPG quality")
checkEqual(preferences.shortcut(for: .fullScreen), .ctrlShift(18), "default full-screen shortcut")
checkEqual(preferences.shortcut(for: .area), .ctrlShift(19), "default area shortcut")
checkEqual(preferences.shortcut(for: .openCaptures), .ctrlShift(20), "default captures shortcut")
checkEqual(preferences.monitor, 0, "default captures the pointer display")
check(preferences.copy, "clipboard copy defaults on")
check(preferences.flash, "capture flash defaults on")
check(preferences.shutter, "shutter sound defaults on")
check(preferences.menuBarIcon, "menu bar icon defaults on")

preferences.folder = temporary.path
preferences.organization = 2
preferences.format = 1
preferences.quality = 88
preferences.flash = false
preferences.shutter = false
preferences.menuBarIcon = false
preferences.areaShortcut = nil
try preferences.save()

let reloaded = Preferences()
checkEqual(reloaded.folder, temporary.path, "folder persists")
checkEqual(reloaded.organization, 2, "organization persists")
checkEqual(reloaded.format, 1, "format persists")
checkEqual(reloaded.quality, 88, "quality persists")
checkEqual(reloaded.flash, false, "flash setting persists")
checkEqual(reloaded.shutter, false, "shutter setting persists")
checkEqual(reloaded.menuBarIcon, false, "menu bar icon setting persists")
check(reloaded.areaShortcut == nil, "cleared shortcut persists")
checkEqual(reloaded.shortcut(for: .fullScreen), .ctrlShift(18), "untouched shortcut persists")

let example = Preferences()
example.folder = temporary.path
example.organization = 0
example.format = 0
check(
    example.examplePath(for: sampleDate).range(
        of: "^2026-10-28/Grab_2026-10-28_\\d{2}-\\d{2}-\\d{2}-\\d{3}_[0-9a-z]{4}\\.png$",
        options: .regularExpression
    ) != nil,
    "example path mirrors the real capture name",
    example.examplePath(for: sampleDate)
)

// "Open captures" mirrors the organize setting: today, this ISO week, or this month.
checkEqual(
    example.periodFolderURL(for: sampleDate).path,
    temporary.appendingPathComponent("2026-10-28", isDirectory: true).path,
    "open captures targets the current day folder"
)
example.organization = 1
checkEqual(
    example.periodFolderURL(for: sampleDate).path,
    temporary.appendingPathComponent("2026-W44", isDirectory: true).path,
    "open captures targets the current ISO week folder"
)
example.organization = 2
checkEqual(
    example.periodFolderURL(for: sampleDate).path,
    temporary.appendingPathComponent("2026-10", isDirectory: true).path,
    "open captures targets the current month folder"
)
example.organization = 0

// A settings file written before the cleared-shortcut flag existed must still restore bindings
// and leave untouched shortcuts on their defaults.
let legacyProfile = temporary.appendingPathComponent("legacy-profile", isDirectory: true)
try FileManager.default.createDirectory(at: legacyProfile, withIntermediateDirectories: true)
let legacyJSON = """
{
  "folder": "\(temporary.path)",
  "fullScreenShortcut": { "keyCode": 19, "modifiers": 4608 },
  "settingsVersion": 1
}
"""
try legacyJSON.write(to: legacyProfile.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
setenv("GRABPIC_PROFILE_DIRECTORY", legacyProfile.path, 1)
let legacy = Preferences()
checkEqual(legacy.shortcut(for: .fullScreen), .ctrlShift(19), "legacy settings restore a stored shortcut")
checkEqual(legacy.shortcut(for: .area), .ctrlShift(19), "legacy settings keep default shortcuts")
check(legacy.shortcut(for: .openCaptures) != nil, "legacy settings do not clear shortcuts")

// MARK: - Summary

print("")
print("\(checks - failures) of \(checks) checks passed")
if failures > 0 {
    exit(1)
}
