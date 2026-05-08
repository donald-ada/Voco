import AppKit
import SwiftUI

enum SettingsWorkbenchPointerCursor {
    case interactive

    var nsCursor: NSCursor {
        switch self {
        case .interactive:
            NSCursor.pointingHand
        }
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isCursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                updateCursor(isHovering: isHovering)
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    popCursorIfNeeded()
                }
            }
            .onDisappear {
                popCursorIfNeeded()
            }
    }

    private func updateCursor(isHovering: Bool) {
        if isHovering, isEnabled, !isCursorPushed {
            SettingsWorkbenchPointerCursor.interactive.nsCursor.push()
            isCursorPushed = true
        } else if (!isHovering || !isEnabled), isCursorPushed {
            popCursorIfNeeded()
        }
    }

    private func popCursorIfNeeded() {
        guard isCursorPushed else {
            return
        }

        NSCursor.pop()
        isCursorPushed = false
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}
