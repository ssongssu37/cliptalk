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
