import Foundation

/// Combines a list of bits into a single MP3 with repeats and silent gaps,
/// for offline listening on a phone / MP3 player.
///
/// Uses ffmpeg twice:
///   1. Generate `gap.mp3` of N seconds of silence (anullsrc filter)
///   2. Concat-demuxer over a list file that interleaves clips + gaps
enum MixtapeService {

    enum MixtapeError: LocalizedError {
        case binaryMissing
        case noBits
        case ffmpegFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .binaryMissing: return "ffmpeg isn't available."
            case .noBits: return "No clips to export."
            case .ffmpegFailed(let s): return "ffmpeg failed: \(s.prefix(200))"
            case .writeFailed(let s): return "Couldn't write mixtape: \(s)"
            }
        }
    }

    struct Options {
        var repeats: Int            // 1–10
        var gapSeconds: Double      // 0.0–10.0 (ignored when autoGap is true)
        var autoGap: Bool           // gap = the preceding clip's own duration
        var shuffle: Bool

        static let `default` = Options(
            repeats: 1, gapSeconds: 1.0, autoGap: true, shuffle: false
        )
    }

    /// Estimated length of the resulting mixtape (sum of clip durations × repeats
    /// + gaps). Gap is either fixed (`gapSeconds`) or matches each clip's duration
    /// (`autoGap`).
    static func estimatedLength(bits: [Bit], options: Options) -> TimeInterval {
        guard !bits.isEmpty else { return 0 }
        let durations = bits.map { audioDuration(of: $0.audioURL) ?? 0 }
        let clipTotal = durations.reduce(0, +) * Double(options.repeats)

        // We insert a gap after every clip occurrence except the last.
        // Total clip occurrences in the stream = bits.count * repeats.
        let totalClips = bits.count * options.repeats

        if options.autoGap {
            // Sum of durations across the whole stream = clipTotal. Number
            // of gaps = totalClips - 1. Auto-gap "uses the preceding clip's
            // duration" so gap-total = (sum of all clip durations placed,
            // minus the LAST one). Simpler approximation: average duration
            // × (totalClips - 1).
            guard totalClips > 1 else { return clipTotal }
            let avgDuration = durations.reduce(0, +) / Double(durations.count)
            return clipTotal + avgDuration * Double(totalClips - 1)
        } else {
            let gaps = max(0, Double(totalClips - 1)) * options.gapSeconds
            return clipTotal + gaps
        }
    }

    /// Build the mixtape and write it to `outputURL`.
    static func export(bits: [Bit], options: Options, outputURL: URL) async throws {
        guard let ffmpeg = ProcessRunner.locate("ffmpeg") else {
            throw MixtapeError.binaryMissing
        }
        guard !bits.isEmpty else { throw MixtapeError.noBits }

        let ordered = options.shuffle ? bits.shuffled() : bits

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliptalk-mixtape-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // 1. Determine the gap duration per bit. With autoGap, each bit gets a
        //    silence file equal to its own duration. Otherwise one shared gap.
        var gapURLByBitId: [String: URL] = [:]
        var sharedGapURL: URL? = nil

        if options.autoGap {
            // Unique durations get one silence file each (rounded to 0.05s
            // buckets so we don't generate dozens of identical files).
            var bucketURL: [Int: URL] = [:]
            for bit in ordered {
                let dur = audioDuration(of: bit.audioURL) ?? 0
                guard dur > 0.05 else { continue }
                let bucket = Int((dur * 20).rounded())   // 0.05s resolution
                if let existing = bucketURL[bucket] {
                    gapURLByBitId[bit.id] = existing
                    continue
                }
                let g = work.appendingPathComponent("gap-\(bucket).mp3")
                let bucketSeconds = Double(bucket) / 20.0
                let r = await ProcessRunner.run(executable: ffmpeg, args: [
                    "-hide_banner", "-loglevel", "error",
                    "-f", "lavfi",
                    "-i", "anullsrc=r=44100:cl=stereo",
                    "-t", String(format: "%.3f", bucketSeconds),
                    "-c:a", "libmp3lame", "-q:a", "5",
                    "-y", g.path,
                ])
                guard r.ok else { throw MixtapeError.ffmpegFailed(r.stderr) }
                bucketURL[bucket] = g
                gapURLByBitId[bit.id] = g
            }
        } else if options.gapSeconds > 0.001 {
            let g = work.appendingPathComponent("gap.mp3")
            let r = await ProcessRunner.run(executable: ffmpeg, args: [
                "-hide_banner", "-loglevel", "error",
                "-f", "lavfi",
                "-i", "anullsrc=r=44100:cl=stereo",
                "-t", String(format: "%.3f", options.gapSeconds),
                "-c:a", "libmp3lame", "-q:a", "5",
                "-y", g.path,
            ])
            guard r.ok else { throw MixtapeError.ffmpegFailed(r.stderr) }
            sharedGapURL = g
        }

        // 2. Concat list.
        var listLines: [String] = []
        let total = ordered.count * options.repeats
        var seen = 0
        for bit in ordered {
            for _ in 0..<options.repeats {
                listLines.append("file \(quotedPath(bit.audioURL.path))")
                seen += 1
                guard seen < total else { continue }
                let gap: URL?
                if options.autoGap {
                    gap = gapURLByBitId[bit.id]
                } else {
                    gap = sharedGapURL
                }
                if let gap {
                    listLines.append("file \(quotedPath(gap.path))")
                }
            }
        }

        let listURL = work.appendingPathComponent("list.txt")
        do {
            try listLines.joined(separator: "\n").write(to: listURL, atomically: true, encoding: .utf8)
        } catch {
            throw MixtapeError.writeFailed(error.localizedDescription)
        }

        // 3. Concat demux → MP3.
        let r = await ProcessRunner.run(executable: ffmpeg, args: [
            "-hide_banner", "-loglevel", "error",
            "-f", "concat",
            "-safe", "0",
            "-i", listURL.path,
            "-c:a", "libmp3lame", "-b:a", "128k",
            "-y", outputURL.path,
        ])
        guard r.ok else { throw MixtapeError.ffmpegFailed(r.stderr) }
    }

    // MARK: - Helpers

    /// Quote a path for ffmpeg's concat demuxer (escapes single quotes).
    private static func quotedPath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Cheap duration probe via AVURLAsset-equivalent CMD: ask ffmpeg for it.
    /// Returns nil on failure; we tolerate that in the estimate.
    private static func audioDuration(of url: URL) -> TimeInterval? {
        // Use ffprobe-style call via ffmpeg by reading container metadata.
        // We use a synchronous Process here because it's used during slider
        // updates (rare, fast) not in hot loops.
        guard let ffmpeg = ProcessRunner.locate("ffmpeg") else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = ["-hide_banner", "-i", url.path]
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let data = err.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        // ffmpeg prints e.g.   Duration: 00:00:09.04, start: ...
        guard let range = text.range(of: #"Duration: (\d+):(\d+):(\d+\.\d+)"#, options: .regularExpression) else {
            return nil
        }
        let match = String(text[range])
        let parts = match.replacingOccurrences(of: "Duration: ", with: "")
            .split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else {
            return nil
        }
        return h * 3600 + m * 60 + s
    }
}
