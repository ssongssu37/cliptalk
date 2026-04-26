import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var vm: StudyViewModel
    @State private var editingBit: Bit?
    @State private var showingMixtape = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if vm.hasBits {
                    playerCard
                    if vm.showingText || vm.showingClean {
                        transcriptCard
                    }
                    shortcutHints
                    bitListSection
                } else {
                    emptyState
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingBit) { bit in
            EditBitView(bit: bit) {
                vm.loadBits()
            }
        }
        .sheet(isPresented: $showingMixtape) {
            MixtapeExportView(
                allBits: vm.bits,
                favoritedBits: vm.bits.filter { vm.favorites.contains($0.id) }
            )
        }
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
            Button("") { vm.toggleFavoriteCurrent() }
                .keyboardShortcut("s", modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Playlist")
                    .font(.largeTitle.bold())
                Spacer()
                if vm.hasBits {
                    Toggle(isOn: $vm.randomMode) {
                        Text("Shuffle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .scaleEffect(1.3)
                    .padding(.trailing, 6)
                }
            }
            if vm.hasBits {
                Text("\(vm.bitCount) clip\(vm.bitCount == 1 ? "" : "s") in your library")
                    .foregroundStyle(.secondary)
            } else {
                Text("Save clips here, replay them, mark favorites for the Study Book.")
                    .foregroundStyle(.secondary)
            }

            if vm.hasBits {
                mixtapeBanner
            }

            Divider()
        }
    }

    private var mixtapeBanner: some View {
        Button {
            showingMixtape = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export to mixtape")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Combine your clips into one MP3 for your phone or MP3 player")
                        .font(.system(size: 12))
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).pointerCursor()
    }

    private var playerCard: some View {
        VStack(spacing: 20) {
            // Current bit title (only)
            Text(vm.currentBit?.prettyTitle ?? "Press Play to start")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 32)

            // Big circular play button
            Button {
                vm.togglePlay()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 16, y: 6)
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                        .offset(x: vm.isPlaying ? 0 : 3)
                }
                .frame(width: 124, height: 124)
            }
            .buttonStyle(.plain).pointerCursor()

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
                             systemImage: vm.justSaved ? "bookmark.fill" : "bookmark",
                             highlight: vm.justSaved) {
                    vm.toggleFavoriteCurrent()
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
            .background(highlight ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor()
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

    private var bitListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("All clips")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                Text("\(vm.bitCount)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Divider()

            LazyVStack(spacing: 6) {
                ForEach(vm.bits) { bit in
                    bitRow(bit)
                }
            }
        }
        .padding(.top, 12)
    }

    private func bitRow(_ bit: Bit) -> some View {
        let isCurrent = vm.currentBitId == bit.id
        return HStack(spacing: 12) {
            Button {
                vm.playBit(id: bit.id)
            } label: {
                Image(systemName: isCurrent && vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain).pointerCursor()

            Button {
                vm.playBit(id: bit.id)
            } label: {
                Text(displayLabel(bit))
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerCursor()

            if vm.favorites.contains(bit.id) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                editingBit = bit
            } label: {
                Image(systemName: "scissors")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerCursor()
            .help("Trim this clip")

            Button {
                vm.removeBit(id: bit.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerCursor()
            .help("Remove from playlist")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent
                      ? Color.accentColor.opacity(0.10)
                      : Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isCurrent ? Color.accentColor.opacity(0.4) : Color.separator, lineWidth: 1)
        )
    }

    private func displayLabel(_ bit: Bit) -> String {
        let t = bit.transcript
        if !t.isEmpty { return t }
        return bit.prettyTitle
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
                        .frame(height: isDragging ? 12 : 8)

                    // Fill
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * fraction, height: isDragging ? 12 : 8)

                    // Thumb
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: isDragging ? 18 : 16, height: isDragging ? 18 : 16)
                        .offset(x: geo.size.width * fraction - (isDragging ? 9 : 8))
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
