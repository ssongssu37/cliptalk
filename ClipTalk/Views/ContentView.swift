import SwiftUI

/// Top-level shell: sidebar on the left, active view on the right.
/// Every future feature just adds another `SidebarItem` case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case study
    case newClip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .study: return "Study"
        case .newClip: return "New clip"
        }
    }

    var systemImage: String {
        switch self {
        case .study: return "book.pages"
        case .newClip: return "plus.rectangle"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem = .study

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            switch selection {
            case .study:
                StudyView()
            case .newClip:
                ClipView()
            }
        }
    }
}

#Preview {
    ContentView()
}
