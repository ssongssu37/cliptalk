import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var vm: StudyViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if vm.hasBits {
                    playerCard
                    if vm.showingText || vm.showingClean {
                        transcriptCard
                    }
                    removeRow
                    shortcutHints
                } else {
                    emptyState
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if let toast = vm.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: vm.toast)
        .onAppear { vm.loadBits() }
        .background(keyboardShortcuts)
    }

    /// Invisible buttons that capture keyboard shortcuts. Works on macOS 13+.
    private var keyboardShortcuts: some View {
        Group {
            Button("") { vm.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { vm.playRandom() }
                .keyboardShortcut("n", modifiers: [])
            Button("") { vm.toggleText() }
                .keyboardShortcut("t", modifiers: [])
            Button("") { vm.toggleClean() }
                .keyboardShortcut("c", modifiers: [])
            Button("") { vm.saveCurrentToStudyBook() }
                .keyboardShortcut("s", modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Study")
                .font(.largeTitle.bold())
            if vm.hasBits {
                Text("\(vm.bitCount) clip\(vm.bitCount == 1 ? "" : "s") in your library · press Play for a random one")
                    .foregroundStyle(.secondary)
            } else {
                Text("Random-play your clip library. Reveal the transcript, save favorites to the study book.")
                    .foregroundStyle(.secondary)
            }
            Divider().padding(.top, 12)
        }
    }

    private var playerCard: some View {
        VStack(spacing: 20) {
            // Heading
            VStack(spacing: 6) {
                Text("Listen up.")
                    .font(.system(size: 26, weight: .bold))
                Text(vm.currentBit?.prettyTitle ?? "Press Play to start")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 32)

            // Big circular play button
            Button {
                vm.togglePlay()
            } label: {
                ZStack {
                    Circle()
                        .fill(.black)
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                        .offset(x: vm.isPlaying ? 0 : 3)
                }
                .frame(width: 124, height: 124)
            }
            .buttonStyle(.plain)

            // Scrubber
            Scrubber(
                current: vm.currentTime,
                total: vm.duration,
                onSeek: { fraction in vm.seek(toFraction: fraction) }
            )
            .frame(maxWidth: 600)

            Divider().padding(.top, 8)

            // Action row
            HStack(spacing: 0) {
                actionButton("Next", systemImage: "forward.fill") { vm.playRandom() }
                actionDivider
                actionButton(vm.showingText ? "Hide Text" : "Text",
                             systemImage: "text.alignleft") { vm.toggleText() }
                actionDivider
                actionButton(vm.showingClean ? "Hide Explain" : "Explain",
                             systemImage: "sparkles") { vm.toggleClean() }
                actionDivider
                actionButton(vm.justSaved ? "✓ Saved" : "Save",
                             systemImage: "bookmark.fill",
                             highlight: vm.justSaved) {
                    vm.saveCurrentToStudyBook()
                }
            }
        }
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(Color.separator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private func actionButton(_ label: String, systemImage: String, highlight: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(highlight ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(highlight ? Color.black : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.currentBit == nil && label != "Next")
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            if vm.showingText {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Transcript")
                    Text(bitText.isEmpty ? "(No transcript for this clip)" : bitText)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(bitText.isEmpty ? .secondary : .primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if vm.showingText && vm.showingClean { Divider() }
            if vm.showingClean {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Plain English")
                    Text(cleanText.isEmpty ? "(No plain-English version yet for this clip)" : cleanText)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var bitText: String { vm.currentBit?.transcript ?? "" }
    private var cleanText: String { vm.currentBit?.cleanEnglish ?? "" }

    private var removeRow: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                vm.removeCurrentBit()
            } label: {
                Text("Remove from bits")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(vm.currentBit == nil)
            Spacer()
        }
    }

    private var shortcutHints: some View {
        HStack(spacing: 20) {
            hint("space", "play")
            hint("n", "next")
            hint("t", "text")
            hint("c", "explain")
            hint("s", "save")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                )
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No clips yet")
                .font(.title3.weight(.semibold))
            Text("Add bits via the Clip tab, or drop MP3 + transcript files into the bits folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open bits folder") {
                NSWorkspace.shared.open(LibraryPaths.bitsDir)
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Scrubber

private struct Scrubber: View {
    let current: TimeInterval
    let total: TimeInterval
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragFraction: Double = 0

    private var fraction: Double {
        if isDragging { return dragFraction }
        guard total > 0 else { return 0 }
        return min(max(current / total, 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: isDragging ? 6 : 4)

                    // Fill
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: geo.size.width * fraction, height: isDragging ? 6 : 4)

                    // Thumb
                    Circle()
                        .fill(Color.primary)
                        .frame(width: isDragging ? 14 : 12, height: isDragging ? 14 : 12)
                        .offset(x: geo.size.width * fraction - (isDragging ? 7 : 6))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = min(max(value.location.x / geo.size.width, 0), 1)
                            dragFraction = f
                            isDragging = true
                        }
                        .onEnded { _ in
                            onSeek(dragFraction)
                            isDragging = false
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(formatTime(current))
                Spacer()
                Text(formatTime(total))
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "00:00.0" }
        let minutes = Int(t) / 60
        let seconds = t - Double(Int(t) / 60 * 60)
        return String(format: "%02d:%04.1f", minutes, seconds)
    }
}

// MARK: - Color helper

private extension Color {
    static var separator: Color {
        Color(nsColor: .separatorColor)
    }
}

#Preview {
    StudyView()
        .environmentObject(StudyViewModel())
        .frame(width: 880, height: 800)
}
