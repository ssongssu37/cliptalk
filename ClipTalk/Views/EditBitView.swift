import AVFoundation
import SwiftUI

/// Modal sheet for trimming a bit's MP3. The user drags two handles to set
/// new start/end bounds, can preview the trimmed range, and saves to
/// atomically replace the file via `Library.trimBit`.
struct EditBitView: View {
    let bit: Bit
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var player = TrimPlayer()
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var saving = false
    @State private var restoring = false
    @State private var hasOriginal = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            transcriptBlock
            scrubberBlock
            actionRow
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(28)
        .frame(width: 640, height: 460)
        .onAppear {
            player.load(url: bit.audioURL) { duration in
                trimStart = 0
                trimEnd = duration
            }
            hasOriginal = Library.hasOriginalBackup(forBitId: bit.id)
        }
        .onDisappear {
            player.stop()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit clip")
                    .font(.title2.bold())
                Text(bit.prettyTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(saving)
        }
    }

    private var transcriptBlock: some View {
        Group {
            if !bit.transcript.isEmpty {
                Text(bit.transcript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Scrubber + handles

    private var scrubberBlock: some View {
        VStack(spacing: 12) {
            TrimScrubber(
                duration: player.duration,
                playhead: player.currentTime,
                trimStart: $trimStart,
                trimEnd: $trimEnd,
                isPlaying: player.isPlaying,
                onSeek: { player.seek(to: $0) }
            )
            .frame(height: 50)

            HStack {
                Text("Start: \(formatTime(trimStart))")
                Spacer()
                Text("Length: \(formatTime(max(0, trimEnd - trimStart)))")
                Spacer()
                Text("End: \(formatTime(trimEnd))")
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlay()
            } label: {
                Label(player.isPlaying ? "Pause" : "Play",
                      systemImage: player.isPlaying ? "pause.fill" : "play.fill")
            }

            Button {
                player.previewRange(start: trimStart, end: trimEnd)
            } label: {
                Label("Preview trim", systemImage: "play.rectangle")
            }
            .disabled(trimEnd - trimStart < 0.1)

            if hasOriginal {
                Button {
                    restoreOriginal()
                } label: {
                    Label("Restore original", systemImage: "arrow.uturn.backward")
                }
                .disabled(saving || restoring)
                .help("Replace this clip with the untouched original audio")
            }

            Spacer()

            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(saving || restoring || !canSave)
        }
    }

    private var canSave: Bool {
        // Only save if the user actually changed something and the range is valid.
        let length = trimEnd - trimStart
        guard length >= 0.1, player.duration > 0 else { return false }
        let unchanged = trimStart < 0.05 && abs(trimEnd - player.duration) < 0.05
        return !unchanged
    }

    private func save() {
        saving = true
        errorMessage = nil
        let start = trimStart
        let end = trimEnd
        Task {
            let ok = await Library.trimBit(bit, start: start, end: end)
            await MainActor.run {
                saving = false
                if ok {
                    onSaved()
                    dismiss()
                } else {
                    errorMessage = "Couldn't trim audio. Make sure ffmpeg is available and try again."
                }
            }
        }
    }

    private func restoreOriginal() {
        restoring = true
        errorMessage = nil
        // Stop any in-progress playback so the file isn't held open.
        player.stop()
        Task {
            let ok = Library.restoreOriginal(bit)
            await MainActor.run {
                restoring = false
                if ok {
                    onSaved()
                    dismiss()
                } else {
                    errorMessage = "Couldn't restore the original audio."
                }
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "00:00.0" }
        let m = Int(t) / 60
        let s = t - Double((Int(t) / 60) * 60)
        return String(format: "%02d:%04.1f", m, s)
    }
}

// MARK: - Two-handle scrubber

private struct TrimScrubber: View {
    let duration: TimeInterval
    let playhead: TimeInterval
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    private let handleW: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let dur = max(duration, 0.001)

            ZStack(alignment: .leading) {
                // Whole track
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 8)
                    .frame(maxHeight: .infinity)

                // Kept (in-trim) region
                let startX = CGFloat(trimStart / dur) * width
                let endX = CGFloat(trimEnd / dur) * width
                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: max(0, endX - startX), height: 8)
                    .offset(x: startX)
                    .frame(maxHeight: .infinity)

                // Playhead
                if duration > 0 {
                    let phX = CGFloat(playhead / dur) * width
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 28)
                        .offset(x: phX - 1)
                        .frame(maxHeight: .infinity)
                }

                // Start handle
                handle(x: startX)
                    .gesture(dragGesture(width: width, isStart: true))

                // End handle
                handle(x: endX)
                    .gesture(dragGesture(width: width, isStart: false))
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let frac = max(0, min(1, location.x / width))
                onSeek(frac * duration)
            }
        }
    }

    private func handle(x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: handleW, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.white.opacity(0.85), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .offset(x: x - handleW / 2)
    }

    private func dragGesture(width: CGFloat, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let frac = max(0, min(1, value.location.x / width))
                let t = frac * duration
                if isStart {
                    trimStart = min(t, trimEnd - 0.05)
                } else {
                    trimEnd = max(t, trimStart + 0.05)
                }
            }
    }
}

// MARK: - Player

@MainActor
final class TrimPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    /// When set, playback auto-stops once currentTime crosses this.
    private var stopAt: TimeInterval?

    func load(url: URL, onReady: (TimeInterval) -> Void) {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            self.player = p
            self.duration = p.duration
            self.currentTime = 0
            onReady(p.duration)
        } catch {
            NSLog("[TrimPlayer] load failed: \(error.localizedDescription)")
            onReady(0)
        }
    }

    func togglePlay() {
        guard let player else { return }
        stopAt = nil
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func previewRange(start: TimeInterval, end: TimeInterval) {
        guard let player else { return }
        stopAt = end
        player.currentTime = start
        currentTime = start
        player.play()
        isPlaying = true
        startTimer()
    }

    func seek(to t: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(t, duration))
        currentTime = player.currentTime
    }

    func stop() {
        timer?.invalidate(); timer = nil
        player?.stop()
        isPlaying = false
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
                if let stopAt = self.stopAt, p.currentTime >= stopAt {
                    p.pause()
                    self.isPlaying = false
                    self.stopAt = nil
                }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
        }
    }
}
