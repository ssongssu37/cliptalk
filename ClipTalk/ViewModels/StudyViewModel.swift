import AVFoundation
import Combine
import Foundation
import SwiftUI

/// Owns the playback state for the Study view: current bit, AVAudioPlayer,
/// the bits list, and the user-facing toggles (show text, show clean, saved).
@MainActor
final class StudyViewModel: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var bits: [Bit] = []
    @Published private(set) var currentBit: Bit?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    @Published var showingText = false
    @Published var showingClean = false
    @Published var justSaved = false
    @Published var toast: String?
    @Published private(set) var favorites: Set<String> = FavoritesStore.load()

    var isCurrentFavorited: Bool {
        guard let id = currentBit?.id else { return false }
        return favorites.contains(id)
    }

    // MARK: - Private

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var lastIndex: Int?

    // MARK: - Library

    func loadBits() {
        bits = Library.loadBits()
    }

    var bitCount: Int { bits.count }

    var hasBits: Bool { !bits.isEmpty }

    // MARK: - Playback

    /// Pick a fresh random bit and start it. Used for both initial Play and Next.
    func playRandom() {
        loadBits()  // refresh in case new bits were added
        guard !bits.isEmpty else { return }

        var idx = Int.random(in: 0..<bits.count)
        if bits.count > 1, let last = lastIndex {
            // Avoid repeating the same bit twice in a row
            while idx == last {
                idx = Int.random(in: 0..<bits.count)
            }
        }
        lastIndex = idx
        play(bit: bits[idx])
    }

    /// Toggle play/pause on the current bit. If finished, replays from 0.
    /// If no bit loaded yet, picks a random one.
    func togglePlay() {
        guard let player else {
            playRandom()
            return
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        // Either paused mid-clip or finished — just play.
        if player.currentTime >= player.duration - 0.01 {
            player.currentTime = 0
        }
        player.play()
        isPlaying = true
    }

    func seek(toFraction fraction: Double) {
        guard let player else { return }
        let clamped = min(max(fraction, 0), 1)
        player.currentTime = player.duration * clamped
        currentTime = player.currentTime
    }

    // MARK: - Study actions

    func showText() { showingText = true }
    func hideText() { showingText = false }
    func toggleText() { showingText.toggle() }

    func showClean() { showingClean = true }
    func hideClean() { showingClean = false }
    func toggleClean() { showingClean.toggle() }

    /// Toggle whether the current bit is in the Study Book favorites list.
    func toggleFavoriteCurrent() {
        guard let bit = currentBit else { return }
        let nowFavorited = FavoritesStore.toggle(bit.id)
        favorites = FavoritesStore.load()
        justSaved = nowFavorited
        flash(nowFavorited ? "Saved to Study Book" : "Removed from Study Book")
    }

    func removeCurrentBit() {
        guard let bit = currentBit else { return }
        Library.removeBit(bit)
        stop()
        currentBit = nil
        showingText = false
        showingClean = false
        justSaved = false
        loadBits()
        flash("Removed from bits")
    }

    // MARK: - Private playback helpers

    private func play(bit: Bit) {
        stop()

        // Leave showingText / showingClean sticky — if the user opened them,
        // they stay open across Next so they can read along with each new clip.
        // `justSaved` reflects favorite state of the new bit.
        justSaved = FavoritesStore.isFavorited(bit.id)

        do {
            let player = try AVAudioPlayer(contentsOf: bit.audioURL)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            self.currentBit = bit
            self.duration = player.duration
            self.currentTime = 0
            self.isPlaying = true
            startTimer()
        } catch {
            flash("Couldn't play: \(error.localizedDescription)")
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
            }
        }
    }

    private func flash(_ message: String) {
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                if self?.toast == message { self?.toast = nil }
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension StudyViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.currentTime = self?.duration ?? 0
        }
    }
}
