import Foundation

/// Bootstraps `yt-dlp` into `~/Library/Application Support/ClipTalk/bin/`
/// from the bundled copy, then keeps it fresh via `yt-dlp -U` once a day.
///
/// Why two copies: yt-dlp breaks every time YouTube changes their player.
/// Updating the binary in `bin/` doesn't require a full app release.
/// `ProcessRunner.locate` looks at `bin/` first, so the auto-updated copy
/// always wins over the bundled fallback.
///
/// `ffmpeg` is NOT auto-updated — it doesn't break, and updating a 70MB
/// static binary daily would be wasteful. It runs straight from the bundle.
enum BinarySetup {

    private static let lastUpdateKey = "ct.ytdlp.lastUpdateCheck"
    private static let updateInterval: TimeInterval = 24 * 3600

    /// Run on app launch. Idempotent — safe to call every time.
    /// Detached: never blocks UI, never throws to the caller.
    static func bootstrap() {
        Task.detached(priority: .background) {
            do {
                try await ensureBootstrapped()
                await maybeUpdate()
            } catch {
                NSLog("[BinarySetup] bootstrap failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - First-run copy

    /// Copy the bundled yt-dlp into Application Support if it's not there yet,
    /// or if the bundled copy is newer than the installed one (after an app upgrade).
    private static func ensureBootstrapped() async throws {
        let dest = LibraryPaths.binDir.appendingPathComponent("yt-dlp")
        guard let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("bin/yt-dlp") else {
            return
        }
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: bundled.path) else { return }

        let needsCopy: Bool
        if !fm.fileExists(atPath: dest.path) {
            needsCopy = true
        } else if let bundledMod = (try? bundled.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  let destMod = (try? dest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  bundledMod > destMod {
            // Bundled copy is newer — app was updated. Refresh.
            needsCopy = true
        } else {
            needsCopy = false
        }

        if needsCopy {
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
            try fm.copyItem(at: bundled, to: dest)
            // Make sure it's executable
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        }
    }

    // MARK: - Daily self-update

    private static func maybeUpdate() async {
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: lastUpdateKey)
        let now = Date().timeIntervalSince1970

        guard now - last >= updateInterval else { return }

        let dest = LibraryPaths.binDir.appendingPathComponent("yt-dlp")
        guard FileManager.default.isExecutableFile(atPath: dest.path) else { return }

        // yt-dlp's own updater. Quiet failure — if it's offline or YouTube
        // is unreachable, just try again tomorrow.
        let result = await ProcessRunner.run(executable: dest.path, args: ["-U"])
        if result.ok {
            NSLog("[BinarySetup] yt-dlp -U: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            defaults.set(now, forKey: lastUpdateKey)
        } else {
            NSLog("[BinarySetup] yt-dlp -U failed (will retry tomorrow): \(result.stderr.prefix(200))")
            // Stamp anyway so we don't hammer the network if it's persistently failing.
            defaults.set(now, forKey: lastUpdateKey)
        }
    }
}
