import AppKit
import Foundation

/// Small prefs store living in ~/Library/Application Support/ClipTalk/folder.txt.
/// Keeps things file-based so it's easy to inspect and wipe.
enum Preferences {

    private static var folderPrefURL: URL {
        LibraryPaths.supportDir.appendingPathComponent("folder.txt")
    }

    /// Where downloaded MP3s and transcripts land.
    static func saveFolder() -> URL {
        if let raw = try? String(contentsOf: folderPrefURL, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = URL(fileURLWithPath: trimmed)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        // Default: ~/Downloads
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    static func setSaveFolder(_ url: URL) {
        try? url.path.write(to: folderPrefURL, atomically: true, encoding: .utf8)
    }

    /// Show the macOS folder picker. Returns the chosen URL or nil if cancelled.
    @MainActor
    static func pickSaveFolder(startingAt: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Where should files be saved?"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let start = startingAt {
            panel.directoryURL = start
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        setSaveFolder(url)
        return url
    }
}
