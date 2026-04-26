import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Modal sheet for the "Export to mixtape" feature: combines all clips
/// into a single MP3 with configurable repeats and silent gaps. Result
/// goes through a save panel so the user picks where to drop it.
struct MixtapeExportView: View {
    let allBits: [Bit]
    let favoritedBits: [Bit]
    @Environment(\.dismiss) private var dismiss

    enum Source: String, CaseIterable, Identifiable {
        case all
        case favorites
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All clips"
            case .favorites: return "Study Book only"
            }
        }
    }

    @State private var source: Source = .all
    @State private var repeats: Int = 1
    @State private var gapSeconds: Double = 1.0
    @State private var autoGap: Bool = true
    @State private var shuffle: Bool = false

    @State private var exporting = false
    @State private var errorMessage: String?

    private var selectedBits: [Bit] {
        source == .favorites ? favoritedBits : allBits
    }

    private var estimated: TimeInterval {
        MixtapeService.estimatedLength(
            bits: selectedBits,
            options: .init(
                repeats: repeats,
                gapSeconds: gapSeconds,
                autoGap: autoGap,
                shuffle: shuffle
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            Divider()
            sourceSection
            repeatsSection
            gapSection
            orderSection
            summary
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            actions
        }
        .padding(28)
        .frame(width: 520)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export to mixtape")
                .font(.title2.bold())
            Text("Combine your clips into one MP3 you can put on a phone or MP3 player.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Include")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Picker("Include", selection: $source) {
                ForEach(Source.allCases) { src in
                    Text("\(src.label) (\(src == .favorites ? favoritedBits.count : allBits.count))")
                        .tag(src)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var repeatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Repeat each clip")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ArrowControl(
                label: "\(repeats) time\(repeats == 1 ? "" : "s")",
                canDecrement: repeats > 1,
                canIncrement: repeats < 10,
                onDecrement: { if repeats > 1 { repeats -= 1 } },
                onIncrement: { if repeats < 10 { repeats += 1 } }
            )
        }
    }

    private var gapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gap between clips")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ArrowControl(
                label: autoGap ? "Auto (matches clip length)" : String(format: "%.1f seconds", gapSeconds),
                canDecrement: !autoGap && gapSeconds > 0,
                canIncrement: !autoGap && gapSeconds < 10,
                onDecrement: { if !autoGap { gapSeconds = max(0, gapSeconds - 0.5) } },
                onIncrement: { if !autoGap { gapSeconds = min(10, gapSeconds + 0.5) } }
            )
            Toggle("Auto adjust to match clip length", isOn: $autoGap)
                .toggleStyle(.switch)
                .font(.callout)
        }
    }

    private var orderSection: some View {
        Toggle("Shuffle clip order", isOn: $shuffle)
            .toggleStyle(.switch)
    }

    private var summary: some View {
        HStack {
            Text("Estimated length")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatDuration(estimated))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(exporting)
            Button(exporting ? "Exporting…" : "Export…") { runExport() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(exporting || selectedBits.isEmpty)
        }
    }

    // MARK: - Actions

    private func runExport() {
        guard !selectedBits.isEmpty else { return }

        // Show save panel synchronously, then kick off ffmpeg.
        let panel = NSSavePanel()
        panel.title = "Save mixtape"
        panel.allowedContentTypes = [.mp3]
        panel.nameFieldStringValue = defaultFilename()
        guard panel.runModal() == .OK, let outURL = panel.url else { return }

        exporting = true
        errorMessage = nil
        let bitsCopy = selectedBits
        let options = MixtapeService.Options(
            repeats: repeats,
            gapSeconds: gapSeconds,
            autoGap: autoGap,
            shuffle: shuffle
        )

        Task {
            do {
                try await MixtapeService.export(bits: bitsCopy, options: options, outputURL: outURL)
                await MainActor.run {
                    exporting = false
                    dismiss()
                    NSWorkspace.shared.activateFileViewerSelecting([outURL])
                }
            } catch {
                await MainActor.run {
                    exporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    private func defaultFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "ClipTalk-mixtape-\(f.string(from: Date())).mp3"
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "—" }
        let total = Int(t.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

/// Big < value > control. Keeps the whole row easy to click and matches
/// the "stretch the value across the full width" feel the user asked for.
private struct ArrowControl: View {
    let label: String
    let canDecrement: Bool
    let canIncrement: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrowButton(systemName: "chevron.left", enabled: canDecrement, action: onDecrement)
            Divider()
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            Divider()
            arrowButton(systemName: "chevron.right", enabled: canIncrement, action: onIncrement)
        }
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func arrowButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
                .frame(width: 56)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor()
        .disabled(!enabled)
    }
}
