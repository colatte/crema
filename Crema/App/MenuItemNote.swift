import SwiftUI

/// A short line under a menu item.
///
/// On macOS 15 and later it is AppKit's own item subtitle (`NSMenuItem.subtitle`),
/// reached through a second `Text` in the item's label — measured for a Toggle, a
/// Button, a submenu and a disabled item on macOS 27
/// (scripts/probes/menu-sections-and-subtitles.swift). Apple's documentation for
/// that property shows the subtitle from macOS 15 and not on 14 for a title that is
/// attributed, so on 14 the note is a line of its own: the menu says the same, a
/// line longer.
enum MenuItemNote {
    static var isSubtitle: Bool {
        if #available(macOS 15, *) {
            return true
        }
        return false
    }

    /// An item with its note. Without an action it is a disabled item — a fact,
    /// not a command. On macOS 14 a repair's note comes BEFORE its button, the fact
    /// first and the answer under it, and a fact's note after its title.
    @MainActor @ViewBuilder
    static func item(_ title: String, note: String, action: (() -> Void)?) -> some View {
        if isSubtitle {
            Button {
                action?()
            } label: {
                Text(title)
                Text(note)
            }
            .disabled(action == nil)
        } else if let action {
            Text(note)
            Button(title, action: action)
        } else {
            Text(title)
            Text(note)
        }
    }
}
