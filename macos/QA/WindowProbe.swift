import AppKit
import CoreGraphics
import Foundation

// QA helper for capture feedback. Two modes:
//
//   WindowProbe <owner-substring> <seconds>   samples the window server and reports the windows
//                                             that process owns: bounds, level, and opacity.
//   WindowProbe --sound                       loads and plays the system shutter, then reports
//                                             whether playback actually started.
//
// The window mode reads only geometry, level, and alpha — no pixels, so it needs no
// screen-recording permission — and is how the flash overlay is verified without looking at it.

let arguments = CommandLine.arguments

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

if arguments.count == 2, arguments[1] == "--sound" {
    let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif"
    guard let sound = NSSound(contentsOfFile: path, byReference: true) else {
        fail("FAIL  the system shutter could not be loaded from \(path)")
    }
    print(String(format: "shutter loaded: %.3f s", sound.duration))
    print("shutter playing after play(): \(sound.play())")
    Thread.sleep(forTimeInterval: 0.12)
    print("shutter isPlaying during playback: \(sound.isPlaying)")
    sound.stop()
    Thread.sleep(forTimeInterval: 0.05)
    print("shutter stopped: \(!sound.isPlaying)")
    exit(0)
}

guard arguments.count >= 3, let seconds = Double(arguments[2]), seconds > 0 else {
    fail("usage: WindowProbe <owner-substring> <seconds> | WindowProbe --sound")
}

let needle = arguments[1].lowercased()
let deadline = Date().addingTimeInterval(seconds)
let started = Date()

struct Snapshot: Equatable {
    let layer: Int
    let alpha: Double
    let width: Double
    let height: Double
    let x: Double
    let y: Double
}

struct Track {
    var first: Double
    var last: Double
    var minAlpha: Double
    var maxAlpha: Double
    var samples: Int
    var snapshot: Snapshot
}

var tracks: [Int: Track] = [:]

while Date() < deadline {
    if let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
        let now = Date().timeIntervalSince(started)
        for info in windows {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner.lowercased().contains(needle) else { continue }
            guard let id = info[kCGWindowNumber as String] as? Int else { continue }
            let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0
            let snapshot = Snapshot(
                layer: info[kCGWindowLayer as String] as? Int ?? 0,
                alpha: alpha,
                width: (bounds["Width"] as? NSNumber)?.doubleValue ?? 0,
                height: (bounds["Height"] as? NSNumber)?.doubleValue ?? 0,
                x: (bounds["X"] as? NSNumber)?.doubleValue ?? 0,
                y: (bounds["Y"] as? NSNumber)?.doubleValue ?? 0
            )
            if var track = tracks[id] {
                track.last = now
                track.minAlpha = min(track.minAlpha, alpha)
                track.maxAlpha = max(track.maxAlpha, alpha)
                track.samples += 1
                if track.snapshot != snapshot {
                    track.snapshot = snapshot
                    print(String(format: "%.3f  id=%d layer=%d alpha=%.3f %.0f×%.0f at %.0f,%.0f",
                                 now, id, snapshot.layer, snapshot.alpha,
                                 snapshot.width, snapshot.height, snapshot.x, snapshot.y))
                }
                tracks[id] = track
            } else {
                tracks[id] = Track(
                    first: now, last: now, minAlpha: alpha, maxAlpha: alpha,
                    samples: 1, snapshot: snapshot
                )
                print(String(format: "%.3f  id=%d layer=%d alpha=%.3f %.0f×%.0f at %.0f,%.0f  (new)",
                             now, id, snapshot.layer, snapshot.alpha,
                             snapshot.width, snapshot.height, snapshot.x, snapshot.y))
            }
        }
    }
    usleep(8_000)
}

print("")
print("summary (owner containing \"\(arguments[1])\")")
if tracks.isEmpty {
    print("  no windows observed")
}
for (id, track) in tracks.sorted(by: { $0.value.maxAlpha > $1.value.maxAlpha }) {
    let lifetime = track.last - track.first
    print(String(format: "  id=%d  %.0f×%.0f at %.0f,%.0f  layer=%d  alpha %.2f…%.2f  visible %.0f ms",
                 id, track.snapshot.width, track.snapshot.height, track.snapshot.x, track.snapshot.y,
                 track.snapshot.layer, track.minAlpha, track.maxAlpha, lifetime * 1000))
}
