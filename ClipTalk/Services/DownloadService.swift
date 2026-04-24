import Foundation

/// Three-state job: what the user asked yt-dlp to do.
enum DownloadKind: String, Codable {
    case mp3
    case transcript
    case both

    var label: String {
        switch self {
        case .mp3: return "MP3"
        case .transcript: return "Transcript"
        case .both: return "MP3 + Transcript"
        }
    }
}

/// Result of a successful download job.
struct DownloadOutcome {
    let message: String
    let paths: [URL]
}

enum DownloadError: LocalizedError {
    case binaryMissing(String)
    case ytdlpFailed(String)
    case noCaptions
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .binaryMissing(let name):
            return "\(name) isn't installed. Run `brew install \(name)`."
        case .ytdlpFailed(let msg):
            return msg
        case .noCaptions:
            return "No captions available for this video."
        case .parseFailed:
            return "Couldn't parse captions file."
        }
    }
}

/// Wraps the three yt-dlp flows (MP3 / Transcript / Both).
struct DownloadService {

    /// Download audio + transcript.
    static func run(url: String, kind: DownloadKind, saveFolder: URL) async throws -> DownloadOutcome {
        guard let ytdlp = ProcessRunner.locate("yt-dlp") else {
            throw DownloadError.binaryMissing("yt-dlp")
        }

        let folder = saveFolder.path.hasSuffix("/")
            ? saveFolder.path
            : saveFolder.path + "/"

        var producedPaths: [URL] = []
        let startTime = Date()

        // ── MP3 ─────────────────────────────────────────────────────────
        if kind == .mp3 || kind == .both {
            let outTemplate = "\(folder)%(title)s.%(ext)s"
            let args = [
                "-x", "--audio-format", "mp3",
                "--no-playlist", "--no-mtime", "--no-warnings",
                "-o", outTemplate,
                url,
            ]
            let r = await ProcessRunner.run(executable: ytdlp, args: args)
            if !r.ok {
                throw DownloadError.ytdlpFailed(summarizeStderr(r.stderr))
            }
        }

        // ── Transcript ──────────────────────────────────────────────────
        if kind == .transcript || kind == .both {
            // yt-dlp writes VTT into a temp dir; we then strip and save .txt.
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("cliptalk-vtt-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let outTemplate = "\(tmp.path)/%(title)s.%(ext)s"
            let args = [
                "--skip-download",
                "--write-subs", "--write-auto-subs",
                "--sub-langs", "en.*,en",
                "--sub-format", "vtt",
                "--no-playlist", "--no-mtime", "--no-warnings",
                "-o", outTemplate,
                url,
            ]
            let r = await ProcessRunner.run(executable: ytdlp, args: args)
            if !r.ok {
                throw DownloadError.ytdlpFailed(summarizeStderr(r.stderr))
            }

            // Find the .vtt file yt-dlp wrote.
            guard let vtt = try? FileManager.default.contentsOfDirectory(
                at: tmp, includingPropertiesForKeys: nil
            ).first(where: { $0.pathExtension.lowercased() == "vtt" }) else {
                throw DownloadError.noCaptions
            }

            // Convert VTT → plain text with rolling-caption dedup.
            let raw = (try? String(contentsOf: vtt, encoding: .utf8)) ?? ""
            let txt = vttToPlainText(raw)
            guard !txt.isEmpty else { throw DownloadError.parseFailed }

            // Save alongside the MP3: use the VTT's base name minus language suffix.
            let base = vtt.lastPathComponent
                .replacingOccurrences(of: #"\.[a-zA-Z]{2}(-[a-zA-Z]+)?\.vtt$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.vtt$"#, with: "", options: .regularExpression)
            let txtURL = saveFolder.appendingPathComponent("\(base).txt")
            try txt.write(to: txtURL, atomically: true, encoding: .utf8)
        }

        // Collect anything freshly written in the save folder (mtime within last 2 min).
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: saveFolder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            for entry in entries {
                let mod = (try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                guard mod > startTime.addingTimeInterval(-2) else { continue }

                let ext = entry.pathExtension.lowercased()
                if (kind == .mp3 || kind == .both) && ext == "mp3" {
                    producedPaths.append(entry)
                } else if (kind == .transcript || kind == .both) && ext == "txt" {
                    producedPaths.append(entry)
                }
            }
        }

        return DownloadOutcome(
            message: "\(kind.label) saved",
            paths: producedPaths.sorted { $0.path < $1.path }
        )
    }

    // MARK: - VTT helpers

    /// Strip WEBVTT headers, timestamps, inline tags, collapse duplicates.
    /// Keeps one line per unique cue in the order they appear.
    static func vttToPlainText(_ vtt: String) -> String {
        var out: [String] = []
        var prev = ""
        for raw in vtt.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            // Header lines
            if line.hasPrefix("WEBVTT") || line.hasPrefix("Kind:") || line.hasPrefix("Language:") {
                continue
            }
            // Timestamp lines contain "-->"
            if line.contains("-->") { continue }
            // Remove inline tags like <c> and <00:00:00.500>, &nbsp;
            var cleaned = line.replacingOccurrences(
                of: #"<[^>]*>"#, with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty, cleaned != prev else { continue }
            out.append(cleaned)
            prev = cleaned
        }
        return out.joined(separator: "\n") + "\n"
    }

    private static func summarizeStderr(_ err: String) -> String {
        // Surface the last non-empty line; yt-dlp tends to print a final error summary.
        let lines = err.split(separator: "\n").map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let last = lines.last, last.count < 300 { return last }
        return String(err.prefix(300))
    }
}
