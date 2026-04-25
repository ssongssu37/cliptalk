import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var isSecure: Bool = true
    @State private var savedMessage: String = ""
    @State private var errorMessage: String = ""
    @State private var isValidating: Bool = false

    var body: some View {
        TabView {
            apiKeyTab
                .tabItem { Label("API Key", systemImage: "key") }
            quickCaptureTab
                .tabItem { Label("Quick Capture", systemImage: "bolt") }
        }
        .padding(24)
        .frame(width: 520, height: 380)
        .onAppear {
            apiKey = Keychain.getOpenAIKey() ?? ""
        }
    }

    // MARK: - API key tab

    private var apiKeyTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI API Key")
                    .font(.headline)
                Text("Used to auto-generate plain-English explanations for your clips. Stored securely in the macOS Keychain. Costs ~$0.0001 per clip.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Group {
                    if isSecure {
                        SecureField("sk-…", text: $apiKey)
                    } else {
                        TextField("sk-…", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                Button {
                    isSecure.toggle()
                } label: {
                    Image(systemName: isSecure ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(isSecure ? "Show key" : "Hide key")
            }

            HStack(spacing: 12) {
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isValidating)

                Button("Clear") {
                    apiKey = ""
                    Keychain.clearOpenAIKey()
                    savedMessage = "Cleared"
                    errorMessage = ""
                }
                .disabled(apiKey.isEmpty && Keychain.getOpenAIKey() == nil)

                Spacer()

                Link("Get a key →",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.callout)
            }

            if !savedMessage.isEmpty {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
            if !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()
        }
    }

    // MARK: - Quick Capture tab

    private var quickCaptureTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Capture Hotkey")
                    .font(.headline)
                Text("Highlight transcript text in your browser, press the hotkey, and ClipTalk saves a clip (up to 30s) straight to your bits library. Also available as a right-click Services menu item.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                KeyboardShortcuts.Recorder("Shortcut:", name: .quickCapture)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions required")
                    .font(.subheadline.weight(.semibold))
                Text("• Accessibility — to read the selected text")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("• Automation — to read the current tab URL from Chrome or Safari")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("macOS will prompt on first use. Grant both in System Settings → Privacy & Security.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = ""
        savedMessage = ""

        if trimmed.isEmpty {
            Keychain.clearOpenAIKey()
            savedMessage = "Cleared"
            return
        }

        if !trimmed.hasPrefix("sk-") {
            errorMessage = "OpenAI keys start with \"sk-\". Double-check and try again."
            return
        }

        let ok = Keychain.setOpenAIKey(trimmed)
        apiKey = trimmed

        // Confirm by reading back — this proves it's retrievable.
        if ok, let readBack = Keychain.getOpenAIKey(), readBack == trimmed {
            savedMessage = "Saved"
        } else {
            errorMessage = "Couldn't save. Check macOS privacy permissions and try again."
        }
    }
}

#Preview {
    SettingsView()
}
