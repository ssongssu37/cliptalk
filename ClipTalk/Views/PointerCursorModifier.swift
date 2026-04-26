import AppKit
import SwiftUI

/// Switches the system cursor to the pointing-hand on hover. Apply with
/// `.pointerCursor()` to any clickable view that isn't already a system
/// `Button` (system buttons handle this automatically). For our custom
/// `.buttonStyle(.plain)` buttons, banners, and chip-style click targets,
/// the modifier closes the gap.
struct PointerCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}

extension View {
    /// Show the pointing-hand cursor while hovering this view.
    func pointerCursor() -> some View {
        modifier(PointerCursorModifier())
    }
}
