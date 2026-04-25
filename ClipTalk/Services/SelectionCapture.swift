import AppKit
import CoreGraphics
import Foundation

/// Captures the current selected text from whatever app is frontmost by
/// round-tripping through the pasteboard: save old contents, synthesize ⌘C,
/// wait briefly for the copy to land, read string, restore old contents.
///
/// Used by the global hotkey path. The macOS Services path doesn't need this —
/// Services hands the selection to the app directly.
///
/// Requires Accessibility permission (to post synthetic key events).
enum SelectionCapture {

    /// Returns the currently selected text, or nil if nothing got copied.
    /// Blocks briefly (~100ms total) waiting for the pasteboard to update.
    static func grabSelectedText() -> String? {
        let pb = NSPasteboard.general

        // 1. Snapshot existing pasteboard items (multi-type, so images survive).
        let saved = snapshotPasteboard(pb)
        let beforeChangeCount = pb.changeCount

        // 2. Post ⌘C to the frontmost app.
        postCopyShortcut()

        // 3. Poll for pasteboard change (~max 300ms).
        let deadline = Date().addingTimeInterval(0.3)
        var copied: String? = nil
        while Date() < deadline {
            if pb.changeCount != beforeChangeCount {
                copied = pb.string(forType: .string)
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        // 4. Restore original pasteboard contents.
        restorePasteboard(pb, items: saved)

        guard let s = copied?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else {
            return nil
        }
        return s
    }

    // MARK: - Pasteboard snapshot/restore

    private static func snapshotPasteboard(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
    }

    private static func restorePasteboard(_ pb: NSPasteboard, items snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        let restored = snapshot.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pb.writeObjects(restored)
    }

    // MARK: - Synthetic keypress

    /// Post ⌘C at the HID event tap so the frontmost app receives it.
    private static func postCopyShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        // Virtual keycode 8 = 'C' on US layout; macOS handles this layout-agnostically
        // when we set the modifier flag.
        let cKey: CGKeyCode = 8

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        keyUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        let loc = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: loc)
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
        cmdUp?.post(tap: loc)
    }
}
