import AppKit
import os

/// Handles clipboard save/restore and simulated Cmd+V paste into the active app.
final class ClipboardManager {
    private var savedItems: [NSPasteboardItem]?
    private var savedChangeCount: Int = 0
    private let logger = Logger(subsystem: "com.superwispr", category: "ClipboardManager")

    func saveClipboard() {
        let pb = NSPasteboard.general
        savedChangeCount = pb.changeCount
        savedItems = pb.pasteboardItems?.compactMap { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    func pasteText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        simulateCmdV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.restoreClipboard()
        }
    }

    // MARK: - Private

    private func restoreClipboard() {
        guard let items = savedItems else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items)
        savedItems = nil
        logger.info("Clipboard restored")
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            logger.error("Failed to create CGEvent for Cmd+V")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
