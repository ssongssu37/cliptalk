import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// Global hotkey for Quick Capture. Defaults to ⌥Z; user-rebindable in Settings.
    static let quickCapture = Self("quickCapture", default: .init(.z, modifiers: [.option]))
}

@main
struct ClipTalkApp: App {
    // These live at the App level so they survive view recreation (e.g. when
    // the user switches sidebar items). Any in-flight Task keeps running.
    @StateObject private var studyVM = StudyViewModel()
    @StateObject private var clipVM = ClipViewModel()

    // Strong ref to the Services provider so it stays alive for the app's lifetime.
    private let serviceProvider = ServiceProvider()

    init() {
        // Bootstrap bundled yt-dlp into Application Support and run daily updates.
        BinarySetup.bootstrap()

        // Register the Services menu handler with AppKit.
        NSApplication.shared.servicesProvider = serviceProvider
        NSUpdateDynamicServices()

        // Wire the global hotkey to the Quick Capture flow.
        KeyboardShortcuts.onKeyUp(for: .quickCapture) {
            Task { @MainActor in
                runQuickCaptureFromHotkey()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(studyVM)
                .environmentObject(clipVM)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .commands {
            // Replace default New Window with nothing — single-window app
            CommandGroup(replacing: .newItem) { }
        }

        // ⌘, opens Settings.
        Settings {
            SettingsView()
        }
    }
}

/// Hotkey path: grab selection via pasteboard trick, URL via AppleScript,
/// hand off to QuickClipper. Must run on the main thread (AppleScript +
/// pasteboard).
@MainActor
func runQuickCaptureFromHotkey() {
    guard let text = SelectionCapture.grabSelectedText() else {
        QuickClipper.capture(text: "", url: "")  // surfaces "No text selected"
        return
    }

    let url: String
    do {
        url = try URLFetcher.currentTabURL()
    } catch {
        QuickClipper.capture(text: text, url: "")
        NSLog("[ClipTalk] URL fetch failed: \(error.localizedDescription)")
        return
    }

    QuickClipper.capture(text: text, url: url)
}
