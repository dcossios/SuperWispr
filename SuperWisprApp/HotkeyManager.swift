import Cocoa
import Carbon
import os

/// Captures a global hold-to-record hotkey.
/// Uses both CGEvent tap and NSEvent monitor for maximum compatibility.
/// Default hotkey: Ctrl+Option (⌃⌥).
final class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyIsDown = false

    private(set) var isActive = false

    func start() {
        guard !isActive else { return }

        // Set up CGEvent tap (works best with Accessibility permission)
        let tapOK = tryStartEventTap()
        debugLog("CGEvent tap created: \(tapOK)")

        // Always also set up NSEvent monitor as backup/complement
        startNSEventMonitor()
        debugLog("NSEvent monitors installed")

        isActive = true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        eventTap = nil
        runLoopSource = nil
        globalMonitor = nil
        localMonitor = nil
        keyIsDown = false
        isActive = false
    }

    // MARK: - CGEvent Tap

    private func tryStartEventTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - NSEvent Monitor

    private func startNSEventMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            self?.handleNSFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            self?.handleNSFlagsChanged(event)
            return event
        }
    }

    private func handleNSFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let active = flags.contains(.control) && flags.contains(.option)
        processKeyState(active)
    }

    // MARK: - CGEvent callback handler

    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let active = flags.contains(.maskControl) && flags.contains(.maskAlternate)
        processKeyState(active)
    }

    // MARK: - Shared key state logic

    private func processKeyState(_ active: Bool) {
        if active && !keyIsDown {
            keyIsDown = true
            debugLog("HOTKEY DOWN — ⌃⌥ held")
            DispatchQueue.main.async { self.onKeyDown?() }
        } else if !active && keyIsDown {
            keyIsDown = false
            debugLog("HOTKEY UP — ⌃⌥ released")
            DispatchQueue.main.async { self.onKeyUp?() }
        }
    }

    // MARK: - Accessibility

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }

    if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    if type == .flagsChanged {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
        manager.handleFlagsChanged(event)
    }

    return Unmanaged.passRetained(event)
}
