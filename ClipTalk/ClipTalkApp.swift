import SwiftUI

@main
struct ClipTalkApp: App {
    // These live at the App level so they survive view recreation (e.g. when
    // the user switches sidebar items). Any in-flight Task keeps running.
    @StateObject private var studyVM = StudyViewModel()
    @StateObject private var clipVM = ClipViewModel()

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
