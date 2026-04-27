import Foundation

/// Per-URL "pinned" full-video MP3 cache. When a user opts in to pin a
/// video, the entire audio is downloaded once via yt-dlp; ClipExtractor
/// then cuts from the local file instead of YouTube's signed CDN URL,
/// dropping per-clip network calls to zero.
///
/// Files live in `~/Library/Application Support/ClipTalk/source-audio/`,
/// named by a stable hash of the video URL.
enum SourceAudio {

    enum PinError: LocalizedError {
        case binaryMissing
        case downloadFailed(String)
        case ffmpegMissing

        var errorDescription: String? {
            switch self {
            case .binaryMissing: return "yt-dlp isn't available."
            case .downloadFailed(let s): return "Download failed: \(s.prefix(200))"
            case .ffmpegMissing: return "ffmpeg isn't available."
            }
        }
    }

    /// Local MP3 path for a given URL, regardless of whether it exists yet.
    static func pinPath(for videoURL: String) -> URL {
        LibraryPaths.pinnedDir.appendingPathComponent("\(hash(videoURL)).mp3")
    }

    /// Returns the local URL if a pinned copy exists, else nil.
    static func pinnedURL(for videoURL: String) -> URL? {
        let p = pinPath(for: videoURL)
        return FileManager.default.fileExists(atPath: p.path) ? p : nil
    }

    /// Filesystem byte size of the pinned copy, or nil if not pinned.
    static func pinnedSize(for videoURL: String) -> Int64? {
        guard let url = pinnedURL(for: videoURL) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64
    }

    /// Download the full audio of `videoURL` as MP3 into the cache. Reports
    /// progress lines as yt-dlp prints them. Idempotent — silently skips if
    /// already pinned.
    static func pin(_ videoURL: String, onProgress: @escaping (String) -> Void = { _ in }) async throws {
        if pinnedURL(for: videoURL) != nil {
            onProgress("already pinned")
            return
        }
        guard let ytdlp = ProcessRunner.locate("yt-dlp") else {
            throw PinError.binaryMissing
        }
        let dst = pinPath(for: videoURL)
        // yt-dlp writes to a temp template, then we rename atomically.
        let tmp = dst.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).mp3")

        onProgress("downloading audio…")
        let r = await ProcessRunner.runWithRetry(executable: ytdlp, args: [
            "-x", "--audio-format", "mp3",
            "--no-playlist", "--no-warnings", "--no-mtime",
            "-o", tmp.path,
            videoURL,
        ])
        if !r.ok {
            try? FileManager.default.removeItem(at: tmp)
            throw PinError.downloadFailed(r.stderr)
        }
        // yt-dlp may rename the file based on the title template variations;
        // accept whichever .mp3 ended up in our temp dir.
        let actual = (try? FileManager.default.contentsOfDirectory(
            at: tmp.deletingLastPathComponent(), includingPropertiesForKeys: nil
        ))?.first(where: {
            $0.pathExtension.lowercased() == "mp3" &&
            $0.lastPathComponent.hasPrefix(tmp.deletingPathExtension().lastPathComponent)
        }) ?? tmp

        if FileManager.default.fileExists(atPath: actual.path) {
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: actual, to: dst)
            onProgress("pinned")
        } else {
            throw PinError.downloadFailed("output file not found after download")
        }
    }

    /// Remove the pinned MP3.
    @discardableResult
    static func unpin(_ videoURL: String) -> Bool {
        guard let url = pinnedURL(for: videoURL) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Hashing

    /// Stable URL → filename hash. Same URL always produces the same name
    /// so we hit the cache on subsequent runs.
    private static func hash(_ s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h &*= 1099511628211
        }
        return String(h, radix: 16)
    }
}
