import AppKit
import ApplicationServices
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

    func pasteText(_ text: String, targetAppPID: pid_t? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        let clipboardPreview = String((pb.string(forType: .string) ?? "").prefix(60))
        debugLog("Clipboard set (\(text.count) chars): \(clipboardPreview)")

        guard AXIsProcessTrusted() else {
            debugLog("Auto-paste skipped: Accessibility permission missing")
            savedItems = nil
            return
        }

        // Method 1: direct Accessibility insertion at the caret.
        if insertViaAccessibility(text) {
            debugLog("Pasted via Accessibility insertion")
        } else if simulateConfiguredPasteShortcut(targetAppPID: targetAppPID) {
            // Method 2: keyboard shortcut fallback.
            debugLog("Pasted via configured shortcut")
        } else {
            // Leave text on clipboard so user can manually Cmd+V
            debugLog("Auto-paste failed — transcription left on clipboard for manual paste")
        }

        // Reliability first: keep transcription in clipboard in all cases.
        savedItems = nil
    }

    // MARK: - Private

    private func restoreClipboard() {
        guard let items = savedItems else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items)
        savedItems = nil
    }

    private func insertViaAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusResult == .success, let focusedRef else {
            debugLog("AX focused element unavailable: \(focusResult.rawValue)")
            return false
        }

        let focused = unsafeBitCast(focusedRef, to: AXUIElement.self)
        let setResult = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if setResult != .success {
            debugLog("AX selected text set failed: \(setResult.rawValue)")
            return false
        }

        return true
    }

    private func simulateConfiguredPasteShortcut(targetAppPID: pid_t?) -> Bool {
        let shortcut = PasteShortcut.fromDefaults()
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        else { return false }

        keyDown.flags = shortcut.flags
        keyUp.flags = shortcut.flags

        debugLog("Trying auto-paste shortcut: \(shortcut.debugLabel)")

        if let targetAppPID {
            keyDown.postToPid(targetAppPID)
            keyUp.postToPid(targetAppPID)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }
}

private struct PasteShortcut {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let debugLabel: String

    static func fromDefaults() -> PasteShortcut {
        let stored = UserDefaults.standard.string(forKey: "autoPasteShortcut") ?? "cmd_v"
        switch stored {
        case "cmd_shift_v":
            return PasteShortcut(
                keyCode: 0x09,
                flags: [.maskCommand, .maskShift],
                debugLabel: "Cmd+Shift+V"
            )
        case "cmd_opt_v":
            return PasteShortcut(
                keyCode: 0x09,
                flags: [.maskCommand, .maskAlternate],
                debugLabel: "Cmd+Option+V"
            )
        case "cmd_opt_shift_v":
            return PasteShortcut(
                keyCode: 0x09,
                flags: [.maskCommand, .maskAlternate, .maskShift],
                debugLabel: "Cmd+Option+Shift+V"
            )
        default:
            return PasteShortcut(
                keyCode: 0x09,
                flags: .maskCommand,
                debugLabel: "Cmd+V"
            )
        }
    }
}
