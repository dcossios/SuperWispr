import SwiftUI
import ServiceManagement
import AVFoundation

struct SettingsView: View {
    @AppStorage("selectedModel") private var selectedModel = "openai/whisper-large-v3-turbo"
    @AppStorage("language") private var language = "auto"
    @AppStorage("cleanupEnabled") private var cleanupEnabled = true
    @AppStorage("soundFeedback") private var soundFeedback = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("pythonPath") private var pythonPath = ""
    @AppStorage("autoPasteShortcut") private var autoPasteShortcut = "cmd_v"

    @StateObject private var appState = AppState.shared
    @State private var isSwappingModel = false

    private let models = [
        ("openai/whisper-large-v3-turbo", "Large V3 Turbo (fast, recommended)"),
        ("openai/whisper-large-v3", "Large V3 (most accurate)"),
        ("distil-whisper/distil-large-v3", "Distil Large V3 (fastest)"),
    ]

    private let languages = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("ru", "Russian"),
        ("pl", "Polish"),
        ("tr", "Turkish"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("no", "Norwegian"),
        ("fi", "Finnish"),
    ]

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Model", selection: $selectedModel) {
                    ForEach(models, id: \.0) { model in
                        Text(model.1).tag(model.0)
                    }
                }
                .onChange(of: selectedModel) { _, newValue in
                    swapModel(newValue)
                }

                if isSwappingModel {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading model…")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Language", selection: $language) {
                    ForEach(languages, id: \.0) { lang in
                        Text(lang.1).tag(lang.0)
                    }
                }

                Toggle("Clean up text (remove fillers)", isOn: $cleanupEnabled)
            }

            Section("Audio") {
                Toggle("Sound feedback (start/stop chime)", isOn: $soundFeedback)

                AudioDevicePicker()
            }

            Section("Hotkey") {
                Text("Hold **⌃⌥** (Control + Option) to record")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                Picker("Auto-paste shortcut", selection: $autoPasteShortcut) {
                    Text("Cmd+V").tag("cmd_v")
                    Text("Cmd+Shift+V").tag("cmd_shift_v")
                    Text("Cmd+Option+V").tag("cmd_opt_v")
                    Text("Cmd+Option+Shift+V").tag("cmd_opt_shift_v")
                }

                Text("Command sent after transcription for automatic paste.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                HStack {
                    TextField("Python path", text: $pythonPath,
                              prompt: Text("/opt/homebrew/bin/python3"))
                    Button("Detect") {
                        detectPython()
                    }
                }
            }

            Section("Status") {
                LabeledContent("Server") {
                    Text(appState.serverReady ? "Running" : "Not running")
                        .foregroundStyle(appState.serverReady ? .green : .red)
                }
                LabeledContent("Model") {
                    Text(appState.loadedModel.components(separatedBy: "/").last ?? "None")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
        .onAppear {
            if pythonPath.isEmpty { detectPython() }
        }
    }

    private func swapModel(_ model: String) {
        isSwappingModel = true
        Task {
            let mgr = ServerManager()
            let ok = await mgr.swapModel(model)
            isSwappingModel = false
            if ok {
                appState.loadedModel = model
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // silently fail for non-bundled builds
            }
        }
    }

    private func detectPython() {
        let candidates = [
            "\(NSHomeDirectory())/.superwispr/venv/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            pythonPath = found
        }
    }
}

struct AudioDevicePicker: View {
    @State private var devices: [String] = []
    @AppStorage("audioDevice") private var selectedDevice = "default"

    var body: some View {
        Picker("Microphone", selection: $selectedDevice) {
            Text("System Default").tag("default")
            ForEach(devices, id: \.self) { device in
                Text(device).tag(device)
            }
        }
        .onAppear { refreshDevices() }
    }

    private func refreshDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize)

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs)

        var names: [String] = []
        for id in deviceIDs {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var hasInput: UInt32 = 0
            var inputSize = UInt32(MemoryLayout<UInt32>.size)
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &inputSize)
            if inputSize > 0 {
                var name: CFString = "" as CFString
                var nameSize = UInt32(MemoryLayout<CFString>.size)
                let status = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
                if status == noErr {
                    names.append(name as String)
                }
            }
        }
        devices = names
    }
}
