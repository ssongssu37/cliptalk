import SwiftUI

struct ClipView: View {
    @EnvironmentObject private var vm: ClipViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                folderRow
                urlSection
                actionsGrid
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
            Text("New clip")
                .font(.largeTitle.bold())
            Text("Download from YouTube, or extract a precise clip by pasting transcript text.")
                .foregroundStyle(.secondary)
            Divider().padding(.top, 12)
        }
    }

    // MARK: - Save folder row

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
                    .strokeBorder(.separator, lineWidth: 1)
            )
        }
    }

    // MARK: - Download + Clip-by-text panels

    private var actionsGrid: some View {
        HStack(alignment: .top, spacing: 20) {
            downloadPanel
            clipByTextPanel
        }
    }

    private var downloadPanel: some View {
        panelContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Download")
                    .font(.system(size: 16, weight: .semibold))
                Text("Save the full video as audio or text.")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    downloadButton("MP3", kind: .mp3, primary: false)
                    downloadButton("Transcript", kind: .transcript, primary: false)
                    downloadButton("Both", kind: .both, primary: true)
                }
            }
        }
    }

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

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Clear") { vm.clearHistory() }
                    .buttonStyle(.link)
                    .disabled(vm.history.isEmpty)
            }
            .padding(.bottom, 4)
            Divider()

            if vm.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("No history yet.")
                        .foregroundStyle(.secondary)
                    Text("Your downloads and clips will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(vm.history) { entry in
                        HistoryRow(
                            entry: entry,
                            onOpenFile: { vm.openFile(at: $0) },
                            onSendToBits: { vm.sendToBits(entry: entry) },
                            onRemove: { vm.removeHistoryEntry(entry.id) }
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
    let onOpenFile: (String) -> Void
    let onSendToBits: () -> Void
    let onRemove: () -> Void

    private var canSendToBits: Bool {
        entry.status == .done
        && !entry.sentToBits
        && entry.producedPaths.contains(where: { $0.lowercased().hasSuffix(".mp3") })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(formattedTimestamp(entry.timestamp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 120, alignment: .leading)

            Text(entry.query ?? "")
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

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

#Preview {
    ClipView()
        .environmentObject(ClipViewModel())
        .frame(width: 1100, height: 900)
}
