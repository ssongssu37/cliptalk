import SwiftUI

/// Top-level shell: sidebar on the left, active view on the right.
/// Every future feature just adds another `SidebarItem` case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case study
    case newClip
    case studyBook
    case download

    var id: String { rawValue }

    var title: String {
        switch self {
        case .study: return "Playlist"
        case .newClip: return "Add Clip"
        case .studyBook: return "Study Book"
        case .download: return "Download"
        }
    }

    var systemImage: String {
        switch self {
        case .study: return "book.pages"
        case .newClip: return "plus.rectangle"
        case .studyBook: return "text.book.closed"
        case .download: return "arrow.down.circle"
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
            case .studyBook:
                StudyBookView()
            case .download:
                DownloadView()
            }
        }
    }
}

#Preview {
    ContentView()
}
