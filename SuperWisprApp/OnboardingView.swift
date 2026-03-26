import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @State private var micPermission: PermissionStatus = .unknown
    @State private var accessibilityPermission: PermissionStatus = .unknown
    @State private var pythonFound: PermissionStatus = .unknown
    @State private var modelDownloaded: PermissionStatus = .unknown
    @State private var isDownloadingModel = false

    @Environment(\.dismiss) private var dismiss

    enum PermissionStatus {
        case unknown, granted, denied
    }

    var allReady: Bool {
        micPermission == .granted
        && accessibilityPermission == .granted
        && pythonFound == .granted
        && modelDownloaded == .granted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to superWispr")
                .font(.title.bold())

            Text("A few things need to be set up before you can start dictating.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    title: "Microphone Access",
                    description: "Required to record your voice",
                    status: micPermission,
                    action: requestMicrophone
                )

                PermissionRow(
                    title: "Accessibility Access",
                    description: "Required for the global hotkey and auto-paste",
                    status: accessibilityPermission,
                    action: requestAccessibility
                )

                PermissionRow(
                    title: "Python 3.11+",
                    description: "Required for the transcription engine",
                    status: pythonFound,
                    action: checkPython
                )

                HStack {
                    VStack(alignment: .leading) {
                        HStack {
                            statusIcon(modelDownloaded)
                            Text("Whisper Model")
                                .font(.headline)
                        }
                        Text("whisper-large-v3-turbo (~3 GB download)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isDownloadingModel {
                        ProgressView()
                            .controlSize(.small)
                    } else if modelDownloaded != .granted {
                        Button("Download") { downloadModel() }
                            .disabled(pythonFound != .granted)
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            HStack {
                Spacer()
                Button("Get Started") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!allReady)
            }
        }
        .padding(24)
        .frame(width: 480, height: 440)
        .onAppear { refreshAll() }
    }

    // MARK: - Checks

    private func refreshAll() {
        checkMicrophone()
        checkAccessibility()
        checkPython()
        checkModel()
    }

    private func checkMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micPermission = .granted
        case .denied, .restricted: micPermission = .denied
        default: micPermission = .unknown
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micPermission = granted ? .granted : .denied
            }
        }
    }

    private func checkAccessibility() {
        accessibilityPermission = AXIsProcessTrusted() ? .granted : .unknown
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { checkAccessibility() }
    }

    private func checkPython() {
        let candidates = [
            "\(NSHomeDirectory())/.superwispr/venv/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        pythonFound = candidates.contains(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) ? .granted : .denied
    }

    private func checkModel() {
        let cache = NSHomeDirectory() + "/.cache/huggingface/hub/models--openai--whisper-large-v3-turbo"
        modelDownloaded = FileManager.default.fileExists(atPath: cache) ? .granted : .unknown
    }

    private func downloadModel() {
        guard let python = findPython() else { return }
        isDownloadingModel = true

        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: python)
            proc.arguments = ["-c",
                "from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor; "
                + "AutoProcessor.from_pretrained('openai/whisper-large-v3-turbo'); "
                + "AutoModelForSpeechSeq2Seq.from_pretrained('openai/whisper-large-v3-turbo')"
            ]
            try? proc.run()
            proc.waitUntilExit()

            await MainActor.run {
                isDownloadingModel = false
                checkModel()
            }
        }
    }

    private func findPython() -> String? {
        [
            "\(NSHomeDirectory())/.superwispr/venv/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unknown:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let status: OnboardingView.PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    switch status {
                    case .granted:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .denied:
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    case .unknown:
                        Image(systemName: "circle").foregroundStyle(.secondary)
                    }
                    Text(title).font(.headline)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status != .granted {
                Button("Grant") { action() }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
