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
