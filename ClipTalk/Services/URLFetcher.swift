import AppKit
import Foundation

/// Asks the frontmost browser for its current tab URL via AppleScript.
/// Tries Chrome-family browsers first (most common for Sunghun), falls back
/// to Safari. Firefox is unsupported — no AppleScript bridge.
///
/// First call triggers a macOS Automation permission prompt for the target
/// browser. Subsequent calls succeed silently.
enum URLFetcher {

    enum FetchError: LocalizedError {
        case noBrowserRunning
        case permissionDenied(String)
        case emptyURL
        case scriptError(String)

        var errorDescription: String? {
            switch self {
            case .noBrowserRunning:
                return "No supported browser is running. Open your YouTube tab in Chrome, Safari, Arc, Brave, or Edge."
            case .permissionDenied(let app):
                return "\(app) blocked automation access. Grant it in System Settings → Privacy & Security → Automation."
            case .emptyURL:
                return "The frontmost browser tab has no URL."
            case .scriptError(let msg):
                return "Couldn't read browser URL: \(msg)"
            }
        }
    }

    /// Browsers in preference order. Chromium-family use the same script;
    /// Safari uses a different one.
    private struct Target {
        let appName: String        // display name for errors
        let bundleId: String       // for running-app check
        let script: String         // AppleScript to fetch URL
    }

    private static let chromeScript = #"""
    tell application id "__BUNDLE__" to get URL of active tab of front window
    """#

    private static let safariScript = #"""
    tell application id "com.apple.Safari" to get URL of front document
    """#

    private static var targets: [Target] {
        let chromiumIds: [(String, String)] = [
            ("Google Chrome", "com.google.Chrome"),
            ("Arc",            "company.thebrowser.Browser"),
            ("Brave Browser",  "com.brave.Browser"),
            ("Microsoft Edge", "com.microsoft.edgemac"),
        ]
        var list = chromiumIds.map { name, id in
            Target(
                appName: name,
                bundleId: id,
                script: chromeScript.replacingOccurrences(of: "__BUNDLE__", with: id)
            )
        }
        list.append(Target(appName: "Safari", bundleId: "com.apple.Safari", script: safariScript))
        return list
    }

    /// Finds the first running supported browser and returns its current tab URL.
    /// Prioritizes the frontmost app if it's one of our supported browsers.
    static func currentTabURL() throws -> String {
        let running = NSWorkspace.shared.runningApplications
        let frontId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Prefer the frontmost browser, then any other running one.
        let ordered = targets.sorted { a, b in
            if a.bundleId == frontId { return true }
            if b.bundleId == frontId { return false }
            return false
        }

        var lastError: FetchError = .noBrowserRunning
        var sawAnyRunning = false

        for target in ordered {
            guard running.contains(where: { $0.bundleIdentifier == target.bundleId }) else {
                continue
            }
            sawAnyRunning = true
            do {
                let url = try run(script: target.script)
                if url.isEmpty { throw FetchError.emptyURL }
                return url
            } catch let err as FetchError {
                lastError = err
                continue  // try next browser
            }
        }

        throw sawAnyRunning ? lastError : FetchError.noBrowserRunning
    }

    private static func run(script: String) throws -> String {
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw FetchError.scriptError("couldn't compile script")
        }
        let descriptor = appleScript.executeAndReturnError(&errorInfo)

        if let info = errorInfo {
            let msg = (info[NSAppleScript.errorMessage] as? String) ?? "unknown"
            let num = (info[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743 is the classic "not authorized" code.
            if num == -1743 || msg.lowercased().contains("not authorized") {
                let app = (info[NSAppleScript.errorAppName] as? String) ?? "Browser"
                throw FetchError.permissionDenied(app)
            }
            throw FetchError.scriptError(msg)
        }

        return (descriptor.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
