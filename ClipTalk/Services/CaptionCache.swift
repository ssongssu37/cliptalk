import Foundation

/// On-disk cache of raw VTT captions per YouTube URL. 24-hour TTL.
/// Cuts the most common cause of YouTube 429s: re-fetching captions for
/// the same video while iterating.
///
/// Lives in /tmp so it auto-clears on reboot. ClipExtractor has its own
/// richer cache (parsed cues + audio URL); this one is just the raw VTT
/// for everywhere else.
enum CaptionCache {

    private static let ttl: TimeInterval = 24 * 3600

    private static var dir: URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliptalk-vtt-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func read(forURL url: String) -> String? {
        let f = path(for: url)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: f.path),
              let mtime = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mtime) < ttl,
              let raw = try? String(contentsOf: f, encoding: .utf8),
              !raw.isEmpty else { return nil }
        return raw
    }

    static func write(_ vtt: String, forURL url: String) {
        let f = path(for: url)
        try? vtt.write(to: f, atomically: true, encoding: .utf8)
    }

    private static func path(for url: String) -> URL {
        dir.appendingPathComponent("\(hash(url)).vtt")
    }

    private static func hash(_ s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h &*= 1099511628211
        }
        return String(h, radix: 16)
    }
}
