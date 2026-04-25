import AppKit
import Foundation
import UserNotifications

/// One-shot pipeline for the Quick Capture flow (hotkey or Services):
///   highlighted text + current browser URL -> MP3 in bits/, capped at 30s.
///
/// Skips the ClipViewModel's history/"Send to Bits" two-step — the bit lands
/// directly in the study library.
enum QuickClipper {

    static let maxDuration: TimeInterval = 30.0

    /// Public entry point. Validates inputs, runs the extract pipeline, writes
    /// the MP3 + transcript into the bits folder, fires a user notification.
    /// Safe to call from any actor — internally marshals onto its own task.
    static func capture(text rawText: String, url rawURL: String) {
        Task.detached {
            await captureAsync(text: rawText, url: rawURL)
        }
    }

    private static func captureAsync(text rawText: String, url rawURL: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            let msg = "Highlight transcript text first, then try again."
            notify(title: "No text selected", body: msg, isError: true)
            await recordFailure(url: url, text: nil, message: msg)
            return
        }
        guard !url.isEmpty else {
            let msg = "Open the YouTube tab in your browser and try again."
            notify(title: "No browser URL", body: msg, isError: true)
            await recordFailure(url: "", text: text, message: msg)
            return
        }
        guard isYouTubeURL(url) else {
            let msg = "Current tab isn't a YouTube video: \(shortURL(url))"
            notify(title: "Not a YouTube URL", body: msg, isError: true)
            await recordFailure(url: url, text: text, message: msg)
            return
        }

        do {
            let result = try await ClipExtractor.extract(
                url: url,
                query: text,
                saveFolder: LibraryPaths.bitsDir,
                maxDuration: maxDuration
            )

            // Stem matches the extractor's filename (minus ".mp3").
            let stem = result.outputPath.deletingPathExtension().lastPathComponent

            // Write transcript alongside the MP3.
            let txtPath = LibraryPaths.bitsDir.appendingPathComponent("\(stem).txt")
            try? (text + "\n").write(to: txtPath, atomically: true, encoding: .utf8)

            // Fire auto-explain if an OpenAI key is set — silent on no-key.
            if Keychain.getOpenAIKey() != nil {
                Task.detached {
                    await generateExplanation(transcript: text, stem: stem)
                }
            }

            let cappedSuffix = result.duration >= maxDuration - 0.05 ? " (capped at 30s)" : ""
            let successMsg = "Clip saved · \(result.rangeLabel)\(cappedSuffix)"

            notify(title: "Saved to ClipTalk", body: successMsg, isError: false)
            await recordSuccess(url: url, text: text, outputPath: result.outputPath, message: successMsg)
        } catch {
            let msg = error.localizedDescription
            notify(title: "Couldn't save clip", body: msg, isError: true)
            await recordFailure(url: url, text: text, message: msg)
        }
    }

    // MARK: - History hooks (main-actor hop into ClipViewModel)

    @MainActor
    private static func recordSuccess(url: String, text: String, outputPath: URL, message: String) {
        ClipViewModel.shared?.recordQuickCaptureSuccess(
            url: url, text: text, outputPath: outputPath, message: message
        )
    }

    @MainActor
    private static func recordFailure(url: String, text: String?, message: String) {
        ClipViewModel.shared?.recordQuickCaptureFailure(
            url: url, text: text, message: message
        )
    }

    // MARK: - Auto-explain

    private static func generateExplanation(transcript: String, stem: String) async {
        do {
            let clean = try await OpenAIService.rewriteToCleanEnglish(transcript)
            guard !clean.isEmpty else { return }
            let dest = LibraryPaths.bitsDir.appendingPathComponent("\(stem).clean.txt")
            try? (clean + "\n").write(to: dest, atomically: true, encoding: .utf8)
        } catch {
            // Silent — the clip itself is already saved.
            print("[QuickClipper.autoExplain] \(stem): \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func isYouTubeURL(_ s: String) -> Bool {
        guard let host = URL(string: s)?.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    private static func shortURL(_ s: String) -> String {
        if s.count <= 60 { return s }
        return String(s.prefix(57)) + "…"
    }

    // MARK: - Notifications

    private static func notify(title: String, body: String, isError: Bool) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            // Request auth on first call if not determined yet.
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                    postNotification(title: title, body: body, isError: isError)
                }
            } else {
                postNotification(title: title, body: body, isError: isError)
            }
        }
    }

    private static func postNotification(title: String, body: String, isError: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isError ? .defaultCritical : .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
