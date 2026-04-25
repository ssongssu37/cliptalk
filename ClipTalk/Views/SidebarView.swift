import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem
    @EnvironmentObject private var clipVM: ClipViewModel

    var body: some View {
        List(selection: $selection) {
            Section("Workspace") {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ClipTalk")
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
        }
    }
}

/// Reads the bit count on appear and whenever the app becomes active,
/// so the sidebar reflects additions/removals without a full refresh.
private struct SidebarFooter: View {
    @EnvironmentObject private var clipVM: ClipViewModel
    @State private var bitCount = 0
    @State private var isFilling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()

            HStack {
                Text("Bits")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(bitCount)")
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            footerButton(isFilling ? "Generating…" : "Generate missing explanations") {
                guard !isFilling else { return }
                isFilling = true
                Task {
                    await clipVM.fillMissingExplanations()
                    isFilling = false
                    refresh()
                }
            }

            footerButton("Bits folder") {
                NSWorkspace.shared.open(LibraryPaths.bitsDir)
            }
        }
        .padding(.bottom, 8)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    @ViewBuilder
    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refresh() {
        bitCount = Library.loadBits().count
    }
}

#Preview {
    SidebarView(selection: .constant(.study))
        .environmentObject(ClipViewModel())
        .frame(width: 220, height: 400)
}
