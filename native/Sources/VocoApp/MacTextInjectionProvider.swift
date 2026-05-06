import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import VocoAppCore

@MainActor
struct MacTextInjectionProvider: TextInjectionProviding {
    private let provider: NativeTextInjectionProvider

    init(client: any TextInsertionClient = MacTextInsertionClient()) {
        self.provider = NativeTextInjectionProvider(client: client)
    }

    func insert(_ text: String) async throws -> TextInjectionSnapshot {
        try await provider.insert(text)
    }
}

@MainActor
private struct MacTextInsertionClient: TextInsertionClient {
    func currentContext() async -> TextInjectionContext {
        let trusted = AXIsProcessTrusted()
        return TextInjectionContext(
            targetAppName: NSWorkspace.shared.frontmostApplication?.localizedName,
            isAccessibilityTrusted: trusted,
            supportsDirectAccessibility: trusted && focusedElementSupportsSelectedText(),
            supportsUnicodeEvents: trusted,
            supportsClipboardFallback: trusted
        )
    }

    func insert(_ text: String, using strategy: TextInjectionStrategy) async throws {
        switch strategy {
        case .directAccessibility:
            try insertWithAccessibility(text)
        case .unicodeEvent:
            try postUnicodeEvents(for: text)
        case .clipboardFallback:
            try await insertWithClipboardFallback(text)
        case .unavailable, .skippedEmpty:
            throw TextInjectionError.noSupportedStrategy(
                targetAppName: NSWorkspace.shared.frontmostApplication?.localizedName
            )
        }
    }

    private func focusedElementSupportsSelectedText() -> Bool {
        guard let element = focusedTextElement() else {
            return false
        }

        var attributes: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &attributes)
        guard result == .success, let attributes else {
            return false
        }

        let names = attributes as NSArray as? [String] ?? []
        return names.contains(kAXSelectedTextAttribute as String)
    }

    private func focusedTextElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success, let focusedElement else {
            return nil
        }

        return (focusedElement as! AXUIElement)
    }

    private func insertWithAccessibility(_ text: String) throws {
        guard let focusedElement = focusedTextElement() else {
            throw TextInjectionError.noSupportedStrategy(
                targetAppName: NSWorkspace.shared.frontmostApplication?.localizedName
            )
        }

        let result = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard result == .success else {
            throw TextInjectionError.insertionFailed(
                strategy: .directAccessibility,
                message: "AX error \(result.rawValue)"
            )
        }
    }

    private func postUnicodeEvents(for text: String) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw TextInjectionError.eventPostFailed(message: "could not create event source")
        }

        for codeUnit in text.utf16 {
            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw TextInjectionError.eventPostFailed(message: "could not create keyboard event")
            }

            var downCharacter = UniChar(codeUnit)
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &downCharacter)
            keyDown.post(tap: .cghidEventTap)

            var upCharacter = UniChar(codeUnit)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &upCharacter)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func insertWithClipboardFallback(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        let backup = PasteboardBackup.capture(from: pasteboard)
        var insertionError: Error?

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            insertionError = TextInjectionError.clipboardUnavailable(message: "could not write transcript text")
            try restoreClipboard(backup, to: pasteboard, priorError: insertionError)
            return
        }

        do {
            try postCommandV()
            try await Task.sleep(nanoseconds: 80_000_000)
        } catch {
            insertionError = error
        }

        try restoreClipboard(backup, to: pasteboard, priorError: insertionError)
    }

    private func postCommandV() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw TextInjectionError.eventPostFailed(message: "could not create event source")
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            throw TextInjectionError.eventPostFailed(message: "could not create paste shortcut")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func restoreClipboard(
        _ backup: PasteboardBackup,
        to pasteboard: NSPasteboard,
        priorError: Error?
    ) throws {
        do {
            try backup.restore(to: pasteboard)
        } catch {
            throw error
        }

        if let priorError {
            throw priorError
        }
    }
}

private struct PasteboardBackup {
    struct Item {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    let items: [Item]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardBackup {
        let items = pasteboard.pasteboardItems?.map { pasteboardItem in
            Item(
                values: pasteboardItem.types.compactMap { type in
                    guard let data = pasteboardItem.data(forType: type) else {
                        return nil
                    }

                    return (type, data)
                }
            )
        } ?? []

        return PasteboardBackup(items: items)
    }

    func restore(to pasteboard: NSPasteboard) throws {
        pasteboard.clearContents()

        guard !items.isEmpty else {
            return
        }

        let restoredItems = items.map { item in
            let pasteboardItem = NSPasteboardItem()
            for value in item.values {
                pasteboardItem.setData(value.data, forType: value.type)
            }
            return pasteboardItem
        }

        guard pasteboard.writeObjects(restoredItems) else {
            throw TextInjectionError.clipboardRestoreFailed(message: "could not write original pasteboard items")
        }
    }
}
