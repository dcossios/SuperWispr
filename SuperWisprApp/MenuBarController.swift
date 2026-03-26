import AppKit
import SwiftUI
import os

func debugLog(_ message: String) {
    let logDir = NSHomeDirectory() + "/Library/Logs/superWispr"
    try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    let logPath = logDir + "/debug.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}

/// Owns the NSStatusItem, coordinates hotkey → record → transcribe → paste flow.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let serverManager = ServerManager()
    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private let transcriptionClient = TranscriptionClient()
    private let clipboardManager = ClipboardManager()
    private let flowBar = FlowBarPanel()
    private let logger = Logger(subsystem: "com.superwispr", category: "MenuBarController")

    private var recordingStartTime: Date?
    private let minimumRecordingDuration: TimeInterval = 0.5
    private var accessibilityTimer: Timer?
    private var hotkeyActive = false
    private var targetAppPID: pid_t?

    private let appState = AppState.shared

    init() {
        debugLog("MenuBarController.init()")
        setupStatusItem()
        setupHotkey()
        startServer()
    }

    func shutdown() {
        accessibilityTimer?.invalidate()
        hotkeyManager.stop()
        serverManager.stop()
        flowBar.hide()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .idle)

        if let button = statusItem?.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let stateText: String
        switch appState.recordingState {
        case .idle: stateText = hotkeyActive ? "Ready — hold ⌃⌥ to dictate" : "Ready"
        case .recording: stateText = "Recording…"
        case .processing: stateText = "Processing…"
        case .error(let msg): stateText = "Error: \(msg)"
        }

        let statusItem = NSMenuItem(title: stateText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if !hotkeyActive {
            menu.addItem(NSMenuItem.separator())
            let permItem = NSMenuItem(
                title: "⚠ Grant Accessibility Permission…",
                action: #selector(grantAccessibility),
                keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        if !appState.loadedModel.isEmpty {
            let modelItem = NSMenuItem(
                title: "Model: \(appState.loadedModel.components(separatedBy: "/").last ?? appState.loadedModel)",
                action: nil, keyEquivalent: "")
            modelItem.isEnabled = false
            menu.addItem(modelItem)
        }

        if !appState.lastTranscription.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let preview = String(appState.lastTranscription.prefix(80))
            let lastItem = NSMenuItem(title: "Last: \(preview)", action: nil, keyEquivalent: "")
            lastItem.isEnabled = false
            menu.addItem(lastItem)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","))
        menu.item(withTitle: "Settings…")?.target = self

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit superWispr", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
        self.statusItem?.button?.performClick(nil)
        self.statusItem?.menu = nil
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        shutdown()
        NSApp.terminate(nil)
    }

    // MARK: - Icon

    private func updateIcon(for state: RecordingState) {
        let symbolName: String
        switch state {
        case .idle: symbolName = "waveform"
        case .recording: symbolName = "waveform.circle.fill"
        case .processing: symbolName = "arrow.trianglehead.2.clockwise"
        case .error: symbolName = "exclamationmark.triangle"
        }
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "superWispr"
        )
    }

    // MARK: - Server

    private func startServer() {
        serverManager.start()

        Task {
            let ready = await serverManager.waitUntilReady()
            if ready {
                appState.serverReady = true
                appState.loadedModel = UserDefaults.standard.string(forKey: "selectedModel")
                    ?? "openai/whisper-large-v3-turbo"
                appState.recordingState = .idle
                updateIcon(for: .idle)
                logger.info("Server is ready")
            } else {
                appState.recordingState = .error("Server failed to start")
                updateIcon(for: appState.recordingState)
                logger.error("Server did not become ready")
            }
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in self?.stopRecordingAndTranscribe() }
        }
        debugLog("AXIsProcessTrusted: \(AXIsProcessTrusted())")

        hotkeyManager.start()
        hotkeyActive = hotkeyManager.isActive
        debugLog("Hotkey setup done, isActive=\(hotkeyActive)")

        if !AXIsProcessTrusted() {
            HotkeyManager.requestAccessibilityPermission()
        }
    }

    private func startAccessibilityPolling() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            if !self.hotkeyManager.isActive {
                self.hotkeyManager.start()
            }
            if self.hotkeyManager.isActive {
                self.accessibilityTimer?.invalidate()
                self.accessibilityTimer = nil
            }
        }
    }

    @objc private func grantAccessibility() {
        HotkeyManager.requestAccessibilityPermission()
        if accessibilityTimer == nil {
            startAccessibilityPolling()
        }
    }

    // MARK: - Recording Flow

    private func startRecording() {
        debugLog("startRecording() called, serverReady=\(appState.serverReady), state=\(String(describing: appState.recordingState))")
        guard appState.serverReady else {
            debugLog("Cannot record: server not ready")
            NSSound.beep()
            return
        }
        guard appState.recordingState == .idle else { return }

        appState.recordingState = .recording
        updateIcon(for: .recording)
        recordingStartTime = Date()
        targetAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        debugLog("Target app PID captured: \(targetAppPID.map(String.init) ?? "none")")

        if UserDefaults.standard.bool(forKey: "soundFeedback") {
            NSSound(named: "Tink")?.play()
        }

        audioRecorder.onLevelUpdate = { [weak self] level in
            self?.flowBar.updateLevel(level)
        }
        let started = audioRecorder.startRecording()
        if started {
            flowBar.show()
        }
    }

    private func stopRecordingAndTranscribe() {
        guard appState.recordingState == .recording else { return }

        if let start = recordingStartTime,
           Date().timeIntervalSince(start) < minimumRecordingDuration {
            _ = audioRecorder.stopRecording()
            audioRecorder.cleanup()
            appState.recordingState = .idle
            updateIcon(for: .idle)
            flowBar.hide()
            return
        }

        guard let fileURL = audioRecorder.stopRecording() else {
            appState.recordingState = .idle
            updateIcon(for: .idle)
            flowBar.hide()
            return
        }

        if UserDefaults.standard.bool(forKey: "soundFeedback") {
            NSSound(named: "Pop")?.play()
        }

        appState.recordingState = .processing
        updateIcon(for: .processing)
        flowBar.showProcessing()

        let language = UserDefaults.standard.string(forKey: "language") ?? "auto"
        let cleanup = UserDefaults.standard.object(forKey: "cleanupEnabled") as? Bool ?? true

        Task {
            do {
                clipboardManager.saveClipboard()

                let result = try await transcriptionClient.transcribe(
                    fileURL: fileURL,
                    language: language,
                    cleanup: cleanup
                )

                guard !result.text.isEmpty else {
                    appState.recordingState = .idle
                    updateIcon(for: .idle)
                    flowBar.hide()
                    audioRecorder.cleanup()
                    return
                }

                appState.lastTranscription = result.text
                clipboardManager.pasteText(result.text, targetAppPID: targetAppPID)
                targetAppPID = nil

                appState.recordingState = .idle
                updateIcon(for: .idle)
                flowBar.hide()
            } catch {
                logger.error("Transcription failed: \(error.localizedDescription)")
                appState.recordingState = .error(error.localizedDescription)
                updateIcon(for: appState.recordingState)
                flowBar.hide()

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.appState.recordingState = .idle
                    self?.updateIcon(for: .idle)
                }
            }

            targetAppPID = nil
            audioRecorder.cleanup()
        }
    }
}
