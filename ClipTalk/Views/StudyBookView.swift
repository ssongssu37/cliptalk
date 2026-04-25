import AVFoundation
import SwiftUI

/// List of every bit in the library. Each row shows the transcript with a
/// play and an X button. Styled like the New clip History page.
struct StudyBookView: View {
    @StateObject private var player = StudyBookPlayer()
    @State private var bits: [Bit] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if bits.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(bits) { bit in
                            StudyBookRow(
                                bit: bit,
                                isPlaying: player.isPlaying(bit.id),
                                onToggle: { player.toggle(bit: bit) },
                                onRemove: { remove(bit) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 32)
            .padding(.bottom, 48)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Study Book")
                    .font(.largeTitle.bold())
                Spacer()
                Text("\(bits.count) bit\(bits.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Clips you saved from the Playlist. Tap to play.")
                .foregroundStyle(.secondary)
            Divider().padding(.top, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No saved clips yet.")
                .foregroundStyle(.secondary)
            Text("Press Save in the Playlist to add a clip here.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func refresh() {
        let favorites = FavoritesStore.load()
        bits = Library.loadBits().filter { favorites.contains($0.id) }
    }

    /// Remove from the Study Book only — does NOT delete the underlying MP3.
    private func remove(_ bit: Bit) {
        if player.isPlaying(bit.id) { player.stop() }
        FavoritesStore.remove(bit.id)
        refresh()
    }
}

// MARK: - Row

private struct StudyBookRow: View {
    let bit: Bit
    let isPlaying: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isPlaying ? Color.accentColor : Color.primary.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play")

            Text(rowText)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var rowText: String {
        let t = bit.transcript
        if !t.isEmpty { return t }
        return bit.prettyTitle
    }
}

// MARK: - Minimal per-row audio player

@MainActor
final class StudyBookPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingId: String?
    private var player: AVAudioPlayer?

    func isPlaying(_ id: String) -> Bool { playingId == id }

    func toggle(bit: Bit) {
        if playingId == bit.id, let p = player {
            if p.isPlaying {
                p.pause()
                playingId = nil
            } else {
                p.play()
                playingId = bit.id
            }
            return
        }
        play(bit: bit)
    }

    func stop() {
        player?.stop()
        player = nil
        playingId = nil
    }

    private func play(bit: Bit) {
        player?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: bit.audioURL)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            self.player = p
            self.playingId = bit.id
        } catch {
            NSLog("[StudyBook] play failed: \(error.localizedDescription)")
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.playingId = nil
        }
    }
}

#Preview {
    StudyBookView()
        .frame(width: 900, height: 700)
}
