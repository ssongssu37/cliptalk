import SwiftUI

/// Pull a full YouTube video as MP3, transcript, or both into a folder
/// the user picks. Shares ClipViewModel with the Add Clip page so the
/// URL field, history, and active jobs stay in sync.
struct DownloadView: View {
    @EnvironmentObject private var vm: ClipViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                folderRow
                urlSection
                downloadPanel
                if !vm.activeJobs.isEmpty {
                    activeJobsPanel
                }
                downloadHistory
            }
            .padding(.horizontal, 48)
            .padding(.top, 32)
            .padding(.bottom, 48)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Download")
                .font(.largeTitle.bold())
            Text("Save the full video as MP3, transcript, or both. Files land in the folder you pick.")
                .foregroundStyle(.secondary)
            Divider().padding(.top, 12)
        }
    }

    // MARK: - Save folder

    private var folderRow: some View {
        HStack(spacing: 10) {
            Text("Saving to")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text(vm.saveFolder.path)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )
                .lineLimit(1)
                .truncationMode(.middle)

            Button("Change") { vm.pickFolder() }
                .buttonStyle(.link)
            Button("Open") { vm.openSaveFolderInFinder() }
                .buttonStyle(.link)
            Spacer()
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
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    // MARK: - Download buttons

    private var downloadPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                downloadButton("MP3", kind: .mp3, primary: false)
                downloadButton("Transcript", kind: .transcript, primary: false)
                downloadButton("Both", kind: .both, primary: true)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func downloadButton(_ label: String, kind: DownloadKind, primary: Bool) -> some View {
        let button = Button {
            vm.download(kind: kind)
        } label: {
            Text(label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .controlSize(.large)
        .disabled(vm.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        if primary {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    // MARK: - Active jobs

    private var activeJobsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(vm.activeJobs, id: \.self) { job in
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(job).font(.callout)
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
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - History (download entries only)

    private var downloadHistory: some View {
        let entries = vm.history.filter {
            $0.kind == .mp3 || $0.kind == .transcript || $0.kind == .both
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.bottom, 4)
            Divider()

            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("No downloads yet.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(entries) { entry in
                        DownloadHistoryRow(
                            entry: entry,
                            onOpenFile: { vm.openFile(at: $0) },
                            onRemove: { vm.removeHistoryEntry(entry.id) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct DownloadHistoryRow: View {
    let entry: HistoryEntry
    let onOpenFile: (String) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(formattedTimestamp(entry.timestamp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.kind.label.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    Text(entry.message)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                if !entry.producedPaths.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(entry.producedPaths, id: \.self) { path in
                            Button { onOpenFile(path) } label: {
                                Text((path as NSString).lastPathComponent)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.secondary.opacity(0.12))
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            .help("Remove from history")
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

    private func formattedTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: date)
    }
}

#Preview {
    DownloadView()
        .environmentObject(ClipViewModel())
        .frame(width: 1100, height: 800)
}
