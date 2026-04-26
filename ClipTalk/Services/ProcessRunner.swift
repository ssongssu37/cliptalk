import Foundation

/// Thin async wrapper around `Process` / `NSTask`. Captures stdout + stderr
/// into strings, returns them with the exit status.
///
/// Errors are not thrown for non-zero exit; the caller gets `.status` and can
/// decide what to do with stderr output.
struct ProcessRunner {

    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { status == 0 }
    }

    /// Run a command to completion.
    ///   executable: absolute path (/usr/local/bin/yt-dlp etc.)
    ///   args:       argv list (do NOT shell-quote — Process handles that)
    ///   extraPATH:  prepended to PATH so yt-dlp can find ffmpeg, etc.
    static func run(
        executable: String,
        args: [String],
        extraPATH: [String] = ["/usr/local/bin", "/opt/homebrew/bin"]
    ) async -> Result {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: executable)
                task.arguments = args

                // Merge PATH so spawned children (e.g. yt-dlp → ffmpeg) work.
                var env = ProcessInfo.processInfo.environment
                let existing = env["PATH"] ?? ""
                env["PATH"] = (extraPATH + [existing]).joined(separator: ":")
                task.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                task.standardOutput = outPipe
                task.standardError = errPipe

                do {
                    try task.run()
                } catch {
                    cont.resume(returning: Result(
                        status: -1,
                        stdout: "",
                        stderr: "Launch failed: \(error.localizedDescription)"
                    ))
                    return
                }
                task.waitUntilExit()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: Result(
                    status: task.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                ))
            }
        }
    }

    /// Like `run`, but retries on transient failures — specifically YouTube's
    /// HTTP 429 (Too Many Requests), which yt-dlp surfaces as a regular
    /// non-zero exit with "429" in stderr. Linear backoff: 5s, 15s, 30s.
    /// Returns the last result regardless of success.
    static func runWithRetry(
        executable: String,
        args: [String],
        extraPATH: [String] = ["/usr/local/bin", "/opt/homebrew/bin"],
        attempts: Int = 3
    ) async -> Result {
        let waits: [UInt64] = [5_000_000_000, 15_000_000_000, 30_000_000_000]
        var last: Result = Result(status: -1, stdout: "", stderr: "no attempts")
        for i in 0..<max(1, attempts) {
            let r = await run(executable: executable, args: args, extraPATH: extraPATH)
            last = r
            if r.ok { return r }
            // Only retry on rate-limit-shaped errors. Anything else is
            // probably a real failure (bad URL, missing video, etc.).
            let combined = (r.stderr + r.stdout).lowercased()
            let rateLimited = combined.contains("http error 429")
                || combined.contains("too many requests")
                || combined.contains("rate limit")
            if !rateLimited { return r }
            if i < attempts - 1 {
                NSLog("[ProcessRunner] 429 detected, retrying in \(waits[min(i, waits.count-1)] / 1_000_000_000)s")
                try? await Task.sleep(nanoseconds: waits[min(i, waits.count - 1)])
            }
        }
        return last
    }

    /// First existing executable path wins. Lookup order:
    ///   1. ~/Library/Application Support/ClipTalk/bin/  (auto-updated yt-dlp lives here)
    ///   2. ClipTalk.app/Contents/Resources/bin/        (the bundled copy that ships with the app)
    ///   3. Homebrew (Intel /usr/local, Apple Silicon /opt/homebrew) — dev fallback
    static func locate(_ binary: String) -> String? {
        let appSupport = LibraryPaths.binDir.appendingPathComponent(binary).path
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(binary).path
        let candidates = [
            appSupport,
            bundled ?? "",
            "/usr/local/bin/\(binary)",
            "/opt/homebrew/bin/\(binary)",
        ]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }
}
