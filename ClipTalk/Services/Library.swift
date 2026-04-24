import Foundation

/// Filesystem locations for user data. Mirrors the layout the web version used.
enum LibraryPaths {
    /// ~/Library/Application Support/ClipTalk
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClipTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Where MP3 + transcript pairs live.
    static var bitsDir: URL {
        let dir = supportDir.appendingPathComponent("bits", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Single text file collecting saved quotes.
    static var studyBook: URL {
        supportDir.appendingPathComponent("study-book.txt")
    }
}

/// Reads and mutates the library on disk. Pure functions, no UI state.
enum Library {

    /// Enumerate every MP3 in bits/, pairing it with its .txt and .clean.txt
    /// siblings when present.
    static func loadBits() -> [Bit] {
        let fm = FileManager.default
        let dir = LibraryPaths.bitsDir
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let mp3s = entries
            .filter { $0.pathExtension.lowercased() == "mp3" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return mp3s.map { mp3 in
            let stem = mp3.deletingPathExtension().lastPathComponent
            let txt = dir.appendingPathComponent("\(stem).txt")
            let clean = dir.appendingPathComponent("\(stem).clean.txt")
            return Bit(
                id: stem,
                audioURL: mp3,
                transcriptURL: fm.fileExists(atPath: txt.path) ? txt : nil,
                cleanURL: fm.fileExists(atPath: clean.path) ? clean : nil
            )
        }
    }

    /// Delete a bit and its companion files. Returns the paths that were removed.
    @discardableResult
    static func removeBit(_ bit: Bit) -> [URL] {
        let dir = LibraryPaths.bitsDir
        let stem = bit.id
        let candidates = [
            bit.audioURL,
            dir.appendingPathComponent("\(stem).txt"),
            dir.appendingPathComponent("\(stem).clean.txt"),
        ]
        var removed: [URL] = []
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                    removed.append(url)
                } catch {
                    // Keep going even if one fails
                }
            }
        }
        return removed
    }

    /// Append a block of text to study-book.txt followed by a blank line.
    static func appendToStudyBook(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let url = LibraryPaths.studyBook
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
        existing += trimmed + "\n\n"
        try? existing.write(to: url, atomically: true, encoding: .utf8)
    }
}
