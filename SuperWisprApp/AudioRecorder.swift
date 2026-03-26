import AVFoundation
import Foundation
import os

/// Records microphone audio to a temporary 16kHz mono WAV file.
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var tempURL: URL?
    private var meterTimer: Timer?
    private let logger = Logger(subsystem: "com.superwispr", category: "AudioRecorder")

    var onLevelUpdate: ((Float) -> Void)?

    var isRecording: Bool { recorder?.isRecording ?? false }

    var recordedFileURL: URL? { tempURL }

    func startRecording(deviceUID: String? = nil) -> Bool {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("superwispr_\(UUID().uuidString).wav")
        tempURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.record()

            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
                [weak self] _ in
                self?.recorder?.updateMeters()
                let power = self?.recorder?.averagePower(forChannel: 0) ?? -160
                let normalized = max(0, min(1, (power + 50) / 50))
                self?.onLevelUpdate?(normalized)
            }

            logger.info("Recording started → \(url.lastPathComponent)")
            return true
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            return false
        }
    }

    func stopRecording() -> URL? {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        logger.info("Recording stopped")
        return tempURL
    }

    func cleanup() {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { logger.warning("Recording did not finish successfully") }
    }
}
