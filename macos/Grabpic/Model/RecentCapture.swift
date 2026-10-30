import Foundation

enum RecentCapture {
    static var stateURL: URL {
        Preferences.profileDirectory.appendingPathComponent("latest-capture.json")
    }

    static func remember(_ url: URL) {
        guard let data = try? JSONEncoder().encode(url.path) else { return }
        try? FileManager.default.createDirectory(at: Preferences.profileDirectory, withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: .atomic)
    }

    static func storedURL() -> URL? {
        guard let data = try? Data(contentsOf: stateURL),
              let path = try? JSONDecoder().decode(String.self, from: data),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Bounded recursive search used only when the remembered file is gone.
    static func newestCapture(in folder: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var newest: URL?
        var newestDate = Date.distantPast
        var inspected = 0
        for case let url as URL in enumerator {
            inspected += 1
            if inspected > 8000 { break }
            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "mp4"].contains(ext) else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate else { continue }
            if modified > newestDate {
                newestDate = modified
                newest = url
            }
        }
        return newest
    }
}
