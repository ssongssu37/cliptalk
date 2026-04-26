import AVFoundation
import SwiftUI

struct ClipView: View {
    @EnvironmentObject private var vm: ClipViewModel
    @StateObject private var rowPlayer = HistoryRowPlayer()
    @State private var editingBit: Bit?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                urlSection
                clipByTextPanel
                if !vm.activeJobs.isEmpty {
                    activeJobsPanel
                }
                historySection
            }
            .padding(.horizontal, 48)
            .padding(.top, 32)
            .padding(.bottom, 48)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingBit) { bit in
            EditBitView(bit: bit) {
                rowPlayer.stop()  // file changed; drop any cached player state
            }
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add Clip")
                .font(.largeTitle.bold())
            Text("Paste a YouTube URL and a line from its transcript — saves just that audio clip to your Playlist.")
                .foregroundStyle(.secondary)
            Divider().padding(.top, 12)
        }
    }

    // MARK: - URL input

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YouTube URL")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 0) {
                TextField("https://youtube.com/watch?v=…", text: $vm.urlInput)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                Divider().frame(height: 20)

                Button {
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        vm.urlInput = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Text("Paste")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointerCursor()
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator, lineWidth: 1)
            )
        }
    }

    // MARK: - Clip-by-text panel

    private var clipByTextPanel: some View {
        panelContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Clip by Text")
                    .font(.system(size: 16, weight: .semibold))
                Text("Paste a line from the transcript — saves just that audio clip.")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                    TextEditor(text: $vm.clipQuery)
                        .font(.system(.body))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 64)
                    if vm.clipQuery.isEmpty {
                        Text("Paste transcript text…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 64)

                HStack(spacing: 8) {
                    Button("Pre-load captions") {
                        vm.warmCaptions()
                    }
                    .buttonStyle(.link)
                    .disabled(vm.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()

                    Button("Extract clip") {
                        vm.extractClip()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        vm.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || vm.clipQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func panelContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - Active jobs

    private var activeJobsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(vm.activeJobs, id: \.self) { job in
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(job)
                        .font(.callout)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    // MARK: - History (clip-by-text + quick capture only)

    private var clipHistory: [HistoryEntry] {
        vm.history.filter { $0.kind == .clip }
    }

    /// Construct a transient `Bit` from a history entry's MP3 path so the
    /// edit sheet can operate on it directly. Returns nil if the file is
    /// gone or the entry has no MP3.
    private func bitFromEntry(_ entry: HistoryEntry) -> Bit? {
        guard let mp3 = entry.producedPaths.first(where: {
            $0.lowercased().hasSuffix(".mp3")
        }) else { return nil }
        let url = URL(fileURLWithPath: mp3)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        let txt = dir.appendingPathComponent("\(stem).txt")
        let clean = dir.appendingPathComponent("\(stem).clean.txt")
        return Bit(
            id: stem,
            audioURL: url,
            transcriptURL: FileManager.default.fileExists(atPath: txt.path) ? txt : nil,
            cleanURL: FileManager.default.fileExists(atPath: clean.path) ? clean : nil
        )
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.bottom, 4)
            Divider()

            if clipHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("No clips yet.")
                        .foregroundStyle(.secondary)
                    Text("Highlight YouTube transcript text and press ⌥Z, or paste text above and click Extract.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(clipHistory) { entry in
                        HistoryRow(
                            entry: entry,
                            isPlaying: rowPlayer.isPlaying(entry.id),
                            onTogglePlay: { rowPlayer.toggle(entry: entry) },
                            onOpenFile: { vm.openFile(at: $0) },
                            onSendToBits: { vm.sendToBits(entry: entry) },
                            onEdit: {
                                if rowPlayer.isPlaying(entry.id) { rowPlayer.stop() }
                                if let bit = bitFromEntry(entry) {
                                    editingBit = bit
                                }
                            },
                            onRemove: {
                                if rowPlayer.isPlaying(entry.id) { rowPlayer.stop() }
                                vm.removeHistoryEntry(entry.id)
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - History row

private struct HistoryRow: View {
    let entry: HistoryEntry
    let isPlaying: Bool
    let onTogglePlay: () -> Void
    let onOpenFile: (String) -> Void
    let onSendToBits: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    private var hasMP3: Bool {
        entry.producedPaths.contains(where: { $0.lowercased().hasSuffix(".mp3") })
    }

    private var canSendToBits: Bool {
        entry.status == .done && !entry.sentToBits && hasMP3
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hasMP3 ? Color.white : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(
                            !hasMP3 ? Color.secondary.opacity(0.18) :
                            isPlaying ? Color.accentColor.opacity(0.7) : Color.accentColor
                        )
                    )
            }
            .buttonStyle(.plain).pointerCursor()
            .disabled(!hasMP3)
            .help(hasMP3 ? (isPlaying ? "Pause" : "Play") : "No audio for this entry")

            Text(formattedTimestamp(entry.timestamp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 110, alignment: .leading)
                .padding(.top, 5)

            Text(entry.query ?? "")
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)

            if canSendToBits {
                Button("Add to Playlist") { onSendToBits() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else if entry.sentToBits {
                Text("✓ in Playlist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            if hasMP3 {
                Button(action: onEdit) {
                    Image(systemName: "scissors")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointerCursor()
                .help("Trim this clip")
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerCursor()
            .help("Remove from history")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: date)
    }
}

private extension Color {
    static var separator: Color {
        Color(nsColor: .separatorColor)
    }
}

// MARK: - Per-row audio player

@MainActor
final class HistoryRowPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingId: UUID?
    private var player: AVAudioPlayer?

    func isPlaying(_ id: UUID) -> Bool { playingId == id }

    func toggle(entry: HistoryEntry) {
        guard let mp3 = entry.producedPaths.first(where: {
            $0.lowercased().hasSuffix(".mp3")
        }) else { return }

        if playingId == entry.id, let p = player {
            if p.isPlaying { p.pause(); playingId = nil }
            else { p.play(); playingId = entry.id }
            return
        }
        play(url: URL(fileURLWithPath: mp3), id: entry.id)
    }

    func stop() {
        player?.stop()
        player = nil
        playingId = nil
    }

    private func play(url: URL, id: UUID) {
        player?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            self.player = p
            self.playingId = id
        } catch {
            NSLog("[HistoryRowPlayer] play failed: \(error.localizedDescription)")
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.playingId = nil
        }
    }
}

#Preview {
    ClipView()
        .environmentObject(ClipViewModel())
        .frame(width: 1100, height: 900)
}
