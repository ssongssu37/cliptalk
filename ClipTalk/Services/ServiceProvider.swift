import AppKit
import Foundation

/// macOS Services handler. Registered via `NSApp.servicesProvider = ...` and
/// declared in Info.plist's NSServices array as "Save to ClipTalk".
///
/// When the user right-clicks selected text and picks Services → Save to
/// ClipTalk, macOS calls `saveToClipTalk(_:userData:error:)` with the
/// selection on the given pasteboard. We pair it with the current browser
/// URL and hand off to QuickClipper.
final class ServiceProvider: NSObject {

    /// Service: highlight a YouTube URL anywhere → right-click → Download from
    /// ClipTalk. Pops a small picker so the user can choose MP3 / Transcript /
    /// Both, then runs `DownloadService` against the Download page's save folder.
    @objc func downloadFromClipTalk(_ pboard: NSPasteboard, userData: String?, error errorPointer: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let raw = pboard.string(forType: .string) else {
            errorPointer.pointee = "No URL selected." as NSString
            return
        }
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isYouTubeURL(url) else {
            errorPointer.pointee = "Selection isn't a YouTube URL." as NSString
            return
        }

        DispatchQueue.main.async {
            // Bring the app forward so the alert isn't hidden behind another window.
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "Download from YouTube"
            alert.informativeText = self.shortenURL(url)
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Both")          // .alertFirstButtonReturn   (default)
            alert.addButton(withTitle: "MP3")           // .alertSecondButtonReturn
            alert.addButton(withTitle: "Transcript")    // .alertThirdButtonReturn
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            let kind: DownloadKind?
            switch response {
            case .alertFirstButtonReturn:  kind = .both
            case .alertSecondButtonReturn: kind = .mp3
            case .alertThirdButtonReturn:  kind = .transcript
            default:                        kind = nil
            }

            guard let kind else { return }
            ClipViewModel.shared?.downloadFromService(url: url, kind: kind)
        }
    }

    // MARK: - Helpers

    private func isYouTubeURL(_ s: String) -> Bool {
        guard let host = URL(string: s)?.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    private func shortenURL(_ s: String) -> String {
        if s.count <= 80 { return s }
        return String(s.prefix(77)) + "…"
    }

    /// Bridge target matching the NSMessage declared in Info.plist.
    /// Selector signature is fixed by AppKit.
    @objc func saveToClipTalk(_ pboard: NSPasteboard, userData: String?, error errorPointer: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorPointer.pointee = "No text selected." as NSString
            return
        }

        // Fetch URL on the main thread (AppleScript requires a run loop).
        DispatchQueue.main.async {
            let url: String
            do {
                url = try URLFetcher.currentTabURL()
            } catch {
                // Hand failure to QuickClipper as empty URL so user gets a
                // notification explaining the problem.
                QuickClipper.capture(text: text, url: "")
                NSLog("[ClipTalk] URL fetch failed: \(error.localizedDescription)")
                return
            }
            QuickClipper.capture(text: text, url: url)
        }
    }
}
