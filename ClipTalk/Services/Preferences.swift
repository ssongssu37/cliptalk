import AppKit
import Foundation

/// Small prefs store living in ~/Library/Application Support/ClipTalk/folder.txt.
/// Keeps things file-based so it's easy to inspect and wipe.
enum Preferences {

    // Legacy: shared "where files land" folder. Now used as the Download
    // page's save folder. Stored in folder.txt for backwards compatibility.
    private static var downloadFolderURL: URL {
        LibraryPaths.supportDir.appendingPathComponent("folder.txt")
    }

    /// Where the Download page (full MP3 / Transcript / Both) saves files.
    static func saveFolder() -> URL {
        readFolder(at: downloadFolderURL)
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    static func setSaveFolder(_ url: URL) {
        writeFolder(url, to: downloadFolderURL)
    }

    /// Show the macOS folder picker for the Download page.
    @MainActor
    static func pickSaveFolder(startingAt: URL? = nil) -> URL? {
        guard let url = pickFolder(title: "Where should downloaded files be saved?", start: startingAt) else { return nil }
        setSaveFolder(url)
        return url
    }

    // MARK: - Helpers

    private static func readFolder(at url: URL) -> URL? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = URL(fileURLWithPath: trimmed)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue {
            return folder
        }
        return nil
    }

    private static func writeFolder(_ folder: URL, to url: URL) {
        try? folder.path.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func pickFolder(title: String, start: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let start { panel.directoryURL = start }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
