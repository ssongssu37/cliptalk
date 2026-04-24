import Combine
import Foundation
import SwiftUI

/// Owns the Clip tab's transient state: URL, current save folder, active
/// jobs, and the persistent history list.
@MainActor
final class ClipViewModel: ObservableObject {

    // URL and query persist across view recreation and app restarts.
    @Published var urlInput: String = UserDefaults.standard.string(forKey: "ct.clip.url") ?? ""
    @Published var clipQuery: String = UserDefaults.standard.string(forKey: "ct.clip.query") ?? ""
    @Published private(set) var saveFolder: URL = Preferences.saveFolder()
    @Published private(set) var history: [HistoryEntry] = HistoryStore.load()
    @Published private(set) var activeJobs: [String] = []
    @Published var toast: String?

    private var cancellables: Set<AnyCancellable> = []

    init() {
        $urlInput
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { value in
                UserDefaults.standard.set(value, forKey: "ct.clip.url")
            }
            .store(in: &cancellables)

        $clipQuery
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { value in
                UserDefaults.standard.set(value, forKey: "ct.clip.query")
            }
            .store(in: &cancellables)
    }

    // MARK: - Folder controls

    func pickFolder() {
        if let chosen = Preferences.pickSaveFolder(startingAt: saveFolder) {
            saveFolder = chosen
            flash("Saving to \(chosen.lastPathComponent)")
        }
    }

    func openSaveFolderInFinder() {
        NSWorkspace.shared.open(saveFolder)
    }

    // MARK: - Downloads

    func download(kind: DownloadKind) {
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            flash("Paste a YouTube URL first", isError: true)
            return
        }

        let jobLabel = "\(kind.label) · \(shortURL(url))"
        activeJobs.append(jobLabel)

        Task {
            do {
                let outcome = try await DownloadService.run(
                    url: url, kind: kind, saveFolder: saveFolder
                )
                recordSuccess(kind: historyKind(for: kind),
                              message: outcome.message,
                              url: url,
                              paths: outcome.paths,
                              query: nil)
                flash(outcome.message)
            } catch {
                recordFailure(kind: historyKind(for: kind),
                              message: error.localizedDescription,
                              url: url)
                flash(error.localizedDescription, isError: true)
            }
            activeJobs.removeAll { $0 == jobLabel }
        }
    }

    // MARK: - Clip by Text

    func warmCaptions() {
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            flash("Paste a YouTube URL first", isError: true)
            return
        }
        let jobLabel = "Loading captions · \(shortURL(url))"
        activeJobs.append(jobLabel)

        Task {
            do {
                let title = try await ClipExtractor.warm(url: url)
                flash("Captions ready · \(title)")
            } catch {
                flash(error.localizedDescription, isError: true)
            }
            activeJobs.removeAll { $0 == jobLabel }
        }
    }

    func extractClip() {
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = clipQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            flash("Paste a YouTube URL first", isError: true)
            return
        }
        guard !query.isEmpty else {
            flash("Paste transcript text first", isError: true)
            return
        }

        let jobLabel = "Extracting clip · \(shortURL(url))"
        activeJobs.append(jobLabel)

        Task {
            do {
                let result = try await ClipExtractor.extract(
                    url: url, query: query, saveFolder: saveFolder
                )
                let msg = "Clip saved · \(result.rangeLabel)"
                recordSuccess(kind: .clip,
                              message: msg,
                              url: url,
                              paths: [result.outputPath],
                              query: query)
                flash("Clip saved")
                // Reset textarea so the user can paste the next chunk.
                clipQuery = ""
            } catch {
                recordFailure(kind: .clip,
                              message: error.localizedDescription,
                              url: url)
                flash(error.localizedDescription, isError: true)
            }
            activeJobs.removeAll { $0 == jobLabel }
        }
    }

    /// Copy a previously-produced clip into the bits folder (so it shows up in Study).
    func sendToBits(entry: HistoryEntry) {
        guard let mp3Str = entry.producedPaths.first(where: {
            $0.lowercased().hasSuffix(".mp3")
        }) else {
            flash("No MP3 on this entry", isError: true)
            return
        }
        let source = URL(fileURLWithPath: mp3Str)
        let bitsDir = LibraryPaths.bitsDir

        // Avoid overwriting an existing bit with the same stem.
        let originalStem = source.deletingPathExtension().lastPathComponent
        var destStem = originalStem
        var n = 2
        while FileManager.default.fileExists(
            atPath: bitsDir.appendingPathComponent("\(destStem).mp3").path
        ) {
            destStem = "\(originalStem)_\(n)"
            n += 1
        }

        let destMP3 = bitsDir.appendingPathComponent("\(destStem).mp3")
        do {
            try FileManager.default.copyItem(at: source, to: destMP3)
        } catch {
            flash("Copy failed: \(error.localizedDescription)", isError: true)
            return
        }

        // Write transcript (entry.query) alongside if present.
        if let query = entry.query, !query.isEmpty {
            let destTxt = bitsDir.appendingPathComponent("\(destStem).txt")
            try? (query + "\n").write(to: destTxt, atomically: true, encoding: .utf8)

            // Fire off plain-English generation in the background (no-op if no key).
            autoGenerateExplanation(transcript: query, stem: destStem)
        }

        markSent(entryId: entry.id)
        flash("Sent to Bits — ready to study")
    }

    /// Generate a plain-English rewrite for a bit and write it to disk.
    /// Silent no-op if the user hasn't set an OpenAI key yet.
    private func autoGenerateExplanation(transcript: String, stem: String) {
        guard Keychain.getOpenAIKey() != nil else { return }

        Task {
            do {
                let clean = try await OpenAIService.rewriteToCleanEnglish(transcript)
                guard !clean.isEmpty else { return }
                let destClean = LibraryPaths.bitsDir.appendingPathComponent("\(stem).clean.txt")
                try? (clean + "\n").write(to: destClean, atomically: true, encoding: .utf8)
            } catch {
                // Don't interrupt the Send to Bits success — just note it.
                print("[auto-explain] \(stem): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Bulk fill missing explanations

    /// Scans the bits folder for MP3s that have a transcript but no .clean.txt,
    /// and generates explanations for each one.
    func fillMissingExplanations() async {
        guard Keychain.getOpenAIKey() != nil else {
            flash("Add an OpenAI key in Settings (⌘,) first", isError: true)
            return
        }

        let bits = Library.loadBits()
        let missing = bits.filter { $0.hasTranscript && !$0.hasClean }

        guard !missing.isEmpty else {
            flash("All bits already have explanations.")
            return
        }

        let jobLabel = "Filling explanations · \(missing.count) bit\(missing.count == 1 ? "" : "s")"
        activeJobs.append(jobLabel)
        flash(jobLabel)

        var generated = 0
        for bit in missing {
            let transcript = bit.transcript
            if transcript.isEmpty { continue }
            do {
                let clean = try await OpenAIService.rewriteToCleanEnglish(transcript)
                guard !clean.isEmpty else { continue }
                let destClean = LibraryPaths.bitsDir.appendingPathComponent("\(bit.id).clean.txt")
                try? (clean + "\n").write(to: destClean, atomically: true, encoding: .utf8)
                generated += 1
            } catch {
                print("[fill] \(bit.id): \(error.localizedDescription)")
            }
        }

        activeJobs.removeAll { $0 == jobLabel }
        flash("Filled \(generated) of \(missing.count) explanation\(missing.count == 1 ? "" : "s")")
    }

    // MARK: - History

    func clearHistory() {
        history = []
        HistoryStore.save(history)
    }

    func markSent(entryId: UUID) {
        guard let idx = history.firstIndex(where: { $0.id == entryId }) else { return }
        history[idx].sentToBits = true
        HistoryStore.save(history)
    }

    func openFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Private helpers

    private func historyKind(for dl: DownloadKind) -> HistoryEntry.Kind {
        switch dl {
        case .mp3: return .mp3
        case .transcript: return .transcript
        case .both: return .both
        }
    }

    private func recordSuccess(kind: HistoryEntry.Kind, message: String, url: String, paths: [URL], query: String?) {
        let entry = HistoryEntry(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            status: .done,
            message: message,
            url: url,
            query: query,
            producedPaths: paths.map(\.path),
            sentToBits: false
        )
        history.insert(entry, at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        HistoryStore.save(history)
    }

    private func recordFailure(kind: HistoryEntry.Kind, message: String, url: String) {
        let entry = HistoryEntry(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            status: .error,
            message: message,
            url: url,
            query: nil,
            producedPaths: [],
            sentToBits: false
        )
        history.insert(entry, at: 0)
        HistoryStore.save(history)
    }

    private func shortURL(_ s: String) -> String {
        // youtube.com/watch?v=ABCD12 → ABCD12
        if let comp = URLComponents(string: s),
           let v = comp.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        return String(s.suffix(24))
    }

    private func flash(_ msg: String, isError: Bool = false) {
        toast = msg
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if self?.toast == msg { self?.toast = nil }
            }
        }
    }
}
