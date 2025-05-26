import Foundation

/// Helper that centralises all app-wide filesystem paths.
/// Creates directories on first launch so callers can assume they exist.
public enum AppFolders {
    /// Folder where we store the user’s audio files and the `notes.json` index.
    static let notes: URL = {
        let fm = FileManager.default
        let url = try! fm.url(for: .applicationSupportDirectory,
                              in: .userDomainMask,
                              appropriateFor: nil,
                              create: true)
            .appendingPathComponent("Notes", isDirectory: true)
        // Create the directory the first time.
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }()
}
