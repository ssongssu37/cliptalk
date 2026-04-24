import Foundation

/// Per-video cached artifacts used by Clip by Text: parsed captions + direct
/// audio stream URL (yt-dlp's signed URL, ~6h TTL).
///
/// Stored in /tmp so it's auto-cleared on reboot.
private struct CaptionCacheEntry: Codable {
    let schemaV: Int
    let title: String
    let cues: [CueDTO]
    let bigText: String
    let charToCue: [Int]
    let charToRawPos: [Int]
    let audioURL: String
    let fetchedAt: Date

    /// Flat, Codable version of `Cue`.
    struct CueDTO: Codable {
        let text: String
        let start: Double
        let end: Double
        let anchorsPos: [Int]
        let anchorsTime: [Double]
    }
}

struct ClipExtractResult {
    let outputPath: URL
    let start: TimeInterval
    let end: TimeInterval
    var duration: TimeInterval { end - start }
    var rangeLabel: String {
        "\(format(start)) → \(format(end))  (\(String(format: "%.1f", duration))s)"
    }
    private func format(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = t - Double(Int(t) / 60 * 60)
        return String(format: "%02d:%02d:%04.1f", h, m, s)
    }
}

enum ClipExtractorError: LocalizedError {
    case binaryMissing(String)
    case captionFetchFailed(String)
    case captionParseFailed
    case audioURLFailed(String)
    case ffmpegFailed(String)
    case textNotFound(String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing(let name):
            return "\(name) isn't installed. Run `brew install \(name)`."
        case .captionFetchFailed(let s): return "Couldn't fetch captions: \(s)"
        case .captionParseFailed: return "Couldn't parse caption file."
        case .audioURLFailed(let s): return "Couldn't resolve audio stream: \(s)"
        case .ffmpegFailed(let s): return "Extract failed: \(s)"
        case .textNotFound(let q):
            let snip = q.count > 80 ? String(q.prefix(80)) + "…" : q
            return "Text not found in captions: “\(snip)”"
        }
    }
}

/// End-to-end Clip-by-Text pipeline: fetch captions & audio URL, match text,
/// cut a precise MP3 with ffmpeg. Captions cached per video URL.
struct ClipExtractor {

    // MARK: - Public API

    /// Warm the cache for a URL so subsequent clips are instant.
    static func warm(url: String) async throws -> String {
        let entry = try await loadOrFetch(url: url)
        return entry.title
    }

    /// Match `query` in captions and extract the matching audio range as MP3.
    static func extract(url: String, query: String, saveFolder: URL) async throws -> ClipExtractResult {
        guard let ffmpeg = ProcessRunner.locate("ffmpeg") else {
            throw ClipExtractorError.binaryMissing("ffmpeg")
        }

        let entry = try await loadOrFetch(url: url)
        let index = indexFromEntry(entry)

        guard let range = index.findRange(query: query) else {
            throw ClipExtractorError.textNotFound(query)
        }

        // Pad slightly so we don't clip words.
        let start = max(0, range.start - 0.3)
        let end = range.end + 0.5
        let duration = end - start

        let outPath = outputURL(for: entry.title, start: start, end: end, saveFolder: saveFolder)

        let result = await ProcessRunner.run(
            executable: ffmpeg,
            args: [
                "-hide_banner", "-loglevel", "error",
                "-ss", String(format: "%.3f", start),
                "-i", entry.audioURL,
                "-t", String(format: "%.3f", duration),
                "-vn",
                "-c:a", "libmp3lame",
                "-q:a", "2",
                "-y",
                outPath.path,
            ]
        )
        if !result.ok {
            throw ClipExtractorError.ffmpegFailed(shorten(result.stderr))
        }

        return ClipExtractResult(outputPath: outPath, start: start, end: end)
    }

    // MARK: - Cache

    private static var cacheDir: URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliptalk-captions", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let cacheTTL: TimeInterval = 6 * 3600

    private static func cachePath(for url: String) -> URL {
        let h = simpleHash(url)
        return cacheDir.appendingPathComponent("\(h).json")
    }

    private static func simpleHash(_ s: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    /// Returns a valid cache entry (loading from disk or fetching fresh).
    private static func loadOrFetch(url: String) async throws -> CaptionCacheEntry {
        let cachePath = cachePath(for: url)

        if let data = try? Data(contentsOf: cachePath),
           let entry = try? JSONDecoder.iso8601.decode(CaptionCacheEntry.self, from: data),
           Date().timeIntervalSince(entry.fetchedAt) < cacheTTL,
           entry.schemaV == 1 {
            return entry
        }

        return try await fetchFresh(url: url, cachePath: cachePath)
    }

    private static func fetchFresh(url: String, cachePath: URL) async throws -> CaptionCacheEntry {
        guard let ytdlp = ProcessRunner.locate("yt-dlp") else {
            throw ClipExtractorError.binaryMissing("yt-dlp")
        }

        // 1. Captions (VTT) into a temp dir.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliptalk-capfetch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let outTemplate = "\(tmp.path)/vid.%(ext)s"
        let capResult = await ProcessRunner.run(executable: ytdlp, args: [
            "--skip-download",
            "--write-subs", "--write-auto-subs",
            "--sub-langs", "en.*,en",
            "--sub-format", "vtt",
            "--no-playlist", "--no-warnings",
            "-o", outTemplate,
            url,
        ])
        if !capResult.ok {
            throw ClipExtractorError.captionFetchFailed(shorten(capResult.stderr))
        }

        guard let vtt = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil
        ).first(where: { $0.pathExtension.lowercased() == "vtt" }),
              let vttText = try? String(contentsOf: vtt, encoding: .utf8) else {
            throw ClipExtractorError.captionFetchFailed("No captions available")
        }

        let cues = CaptionParser.parse(vtt: vttText)
        guard !cues.isEmpty else { throw ClipExtractorError.captionParseFailed }

        let index = CaptionIndex.build(from: cues)

        // 2. Video title (used for filename).
        let titleResult = await ProcessRunner.run(executable: ytdlp, args: [
            "--get-title", "--no-playlist", url,
        ])
        let title = titleResult.ok
            ? titleResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            : "clip"

        // 3. Direct audio stream URL (signed, ~6h TTL).
        let urlResult = await ProcessRunner.run(executable: ytdlp, args: [
            "-f", "bestaudio", "--get-url", "--no-playlist", url,
        ])
        if !urlResult.ok {
            throw ClipExtractorError.audioURLFailed(shorten(urlResult.stderr))
        }
        let audioURL = urlResult.stdout
            .split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if audioURL.isEmpty { throw ClipExtractorError.audioURLFailed("empty URL") }

        // Build + persist cache entry.
        let cueDTOs = cues.map { cue in
            CaptionCacheEntry.CueDTO(
                text: cue.text,
                start: cue.start,
                end: cue.end,
                anchorsPos: cue.wordAnchors.map { $0.0 },
                anchorsTime: cue.wordAnchors.map { $0.1 }
            )
        }
        let entry = CaptionCacheEntry(
            schemaV: 1,
            title: title,
            cues: cueDTOs,
            bigText: index.bigText,
            charToCue: index.charToCue,
            charToRawPos: index.charToRawPos,
            audioURL: audioURL,
            fetchedAt: Date()
        )
        if let data = try? JSONEncoder.iso8601.encode(entry) {
            try? data.write(to: cachePath, options: [.atomic])
        }
        return entry
    }

    private static func indexFromEntry(_ e: CaptionCacheEntry) -> CaptionIndex {
        let cues = e.cues.map { dto -> Cue in
            let anchors = zip(dto.anchorsPos, dto.anchorsTime).map { ($0, $1) }
            return Cue(text: dto.text, start: dto.start, end: dto.end, wordAnchors: anchors)
        }
        return CaptionIndex(
            cues: cues,
            bigText: e.bigText,
            charToCue: e.charToCue,
            charToRawPos: e.charToRawPos
        )
    }

    // MARK: - Helpers

    private static func outputURL(for title: String, start: TimeInterval, end: TimeInterval, saveFolder: URL) -> URL {
        let safeTitle = sanitizeFilename(title)
        let startTag = tsForFilename(start)
        let endTag = tsForFilename(end)
        return saveFolder.appendingPathComponent("\(safeTitle)__\(startTag)_to_\(endTag).mp3")
    }

    private static func tsForFilename(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return String(format: "%02d-%02d-%02d", h, m, s)
    }

    private static func sanitizeFilename(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: #"/\:*?"<>|"#)
        var out = String(s.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) })
        out = out.replacingOccurrences(of: " ", with: "_")
        out = out.replacingOccurrences(of: #"_+"#, with: "_", options: .regularExpression)
        if out.count > 60 { out = String(out.prefix(60)) }
        return out.isEmpty ? "clip" : out
    }

    private static func shorten(_ s: String) -> String {
        let lines = s.split(separator: "\n").map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let last = lines.last, last.count < 300 { return last }
        return String(s.prefix(300))
    }
}

// MARK: - JSON date helpers

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
