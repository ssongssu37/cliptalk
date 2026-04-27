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

    /// Auto-updated CLI binaries (currently just yt-dlp). Bootstrapped by
    /// `BinarySetup` from the bundled copy on first launch.
    static var binDir: URL {
        let dir = supportDir.appendingPathComponent("bin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Where pinned full-video MP3s live. The user opts in per-URL; once
    /// pinned, ClipExtractor cuts from the local file instead of YouTube's
    /// signed CDN URL — no network calls per clip.
    static var pinnedDir: URL {
        let dir = supportDir.appendingPathComponent("source-audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Untouched MP3 backups, snapshotted before the first trim so the user
    /// can restore the original audio later. Hidden so it doesn't show up
    /// when they open `bitsDir` in Finder.
    static var originalsDir: URL {
        let dir = supportDir.appendingPathComponent("bits", isDirectory: true)
            .appendingPathComponent(".originals", isDirectory: true)
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

    /// Path of the untouched-original backup for a given bit id, if one exists.
    static func originalBackupURL(forBitId id: String) -> URL? {
        let url = LibraryPaths.originalsDir.appendingPathComponent("\(id).mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func hasOriginalBackup(forBitId id: String) -> Bool {
        originalBackupURL(forBitId: id) != nil
    }

    /// Restore the bit's audio from the backup made on the first trim.
    /// Returns true on success.
    @discardableResult
    static func restoreOriginal(_ bit: Bit) -> Bool {
        guard let backup = originalBackupURL(forBitId: bit.id) else { return false }
        let dst = bit.audioURL
        do {
            // Replace existing file atomically.
            let tmp = dst.deletingLastPathComponent()
                .appendingPathComponent("\(bit.id).restore-\(UUID().uuidString.prefix(6)).mp3")
            try FileManager.default.copyItem(at: backup, to: tmp)
            _ = try FileManager.default.replaceItemAt(dst, withItemAt: tmp)
            return true
        } catch {
            return false
        }
    }

    /// Snapshot the bit's MP3 into `originalsDir` if no backup exists yet.
    /// Cheap copy; ffmpeg won't run before this.
    private static func ensureOriginalBackup(_ bit: Bit) {
        let dst = LibraryPaths.originalsDir.appendingPathComponent("\(bit.id).mp3")
        guard !FileManager.default.fileExists(atPath: dst.path) else { return }
        try? FileManager.default.copyItem(at: bit.audioURL, to: dst)
    }

    /// Trim an MP3 to [start, end] (in seconds) via ffmpeg, atomically
    /// replacing the original file. Returns true on success.
    /// Caller should reload bits after this.
    @discardableResult
    static func trimBit(_ bit: Bit, start: TimeInterval, end: TimeInterval) async -> Bool {
        guard end - start >= 0.1 else { return false }
        guard let ffmpeg = ProcessRunner.locate("ffmpeg") else { return false }

        // Snapshot the untouched original the first time we trim.
        ensureOriginalBackup(bit)

        let src = bit.audioURL
        let tmp = src.deletingLastPathComponent()
            .appendingPathComponent("\(bit.id).trim-\(UUID().uuidString.prefix(6)).mp3")

        let result = await ProcessRunner.run(
            executable: ffmpeg,
            args: [
                "-hide_banner", "-loglevel", "error",
                "-ss", String(format: "%.3f", start),
                "-to", String(format: "%.3f", end),
                "-i", src.path,
                "-c:a", "libmp3lame",
                "-q:a", "2",
                "-y",
                tmp.path,
            ]
        )
        guard result.ok else {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }

        // Atomic replace
        do {
            _ = try FileManager.default.replaceItemAt(src, withItemAt: tmp)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
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
