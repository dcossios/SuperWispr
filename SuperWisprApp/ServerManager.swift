import Foundation
import os

/// Manages the Python transcription server as a child process.
final class ServerManager {
    private var process: Process?
    private var restartCount = 0
    private let maxRestarts = 3
    private let logger = Logger(subsystem: "com.superwispr", category: "ServerManager")
    private let serverURL = URL(string: "http://127.0.0.1:9876")!
    private var logFileHandle: FileHandle?

    var isRunning: Bool { process?.isRunning ?? false }

    func start() {
        guard !isRunning else { return }

        let pythonPath = UserDefaults.standard.string(forKey: "pythonPath")
            ?? findPython()
            ?? "/usr/bin/python3"

        let serverDir = findServerDirectory()
        logger.info("Server directory: \(serverDir)")
        logger.info("Python path: \(pythonPath)")

        let logURL = setupLogFile()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-m", "uvicorn", "server.main:app",
                          "--host", "127.0.0.1",
                          "--port", "9876",
                          "--log-level", "info"]
        proc.currentDirectoryURL = URL(fileURLWithPath: serverDir)

        if let logURL {
            let outHandle = try? FileHandle(forWritingTo: logURL)
            outHandle?.seekToEndOfFile()
            proc.standardOutput = outHandle
            proc.standardError = outHandle
            logFileHandle = outHandle
        }

        proc.terminationHandler = { [weak self] proc in
            self?.logger.warning("Server exited with code \(proc.terminationStatus)")
            DispatchQueue.main.async { self?.handleTermination() }
        }

        do {
            try proc.run()
            process = proc
            logger.info("Server started (pid \(proc.processIdentifier))")
        } catch {
            logger.error("Failed to start server: \(error.localizedDescription)")
        }
    }

    func waitUntilReady() async -> Bool {
        for attempt in 1...15 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if await checkHealth() { return true }
            logger.info("Health check attempt \(attempt)/15 …")
        }
        return false
    }

    func stop() {
        guard let proc = process, proc.isRunning else {
            process = nil
            logFileHandle?.closeFile()
            logFileHandle = nil
            return
        }
        proc.terminationHandler = nil
        proc.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let proc = self?.process, proc.isRunning else { return }
            self?.logger.warning("Force-killing server after timeout")
            proc.interrupt()
        }

        process = nil
        logFileHandle?.closeFile()
        logFileHandle = nil
    }

    func swapModel(_ modelName: String) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:9876/config") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["model": modelName])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                return status == "ok"
            }
            return false
        } catch {
            logger.error("Model swap failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private

    private func checkHealth() async -> Bool {
        let url = serverURL.appendingPathComponent("health")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                return status == "ok"
            }
            return false
        } catch {
            return false
        }
    }

    private func handleTermination() {
        guard restartCount < maxRestarts else {
            logger.error("Server crashed \(self.maxRestarts) times. Giving up.")
            Task { @MainActor in
                AppState.shared.recordingState = .error("Server crashed repeatedly.")
            }
            return
        }
        restartCount += 1
        logger.info("Restarting server (attempt \(self.restartCount)/\(self.maxRestarts))")
        start()
    }

    private func findPython() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.superwispr/venv/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func findServerDirectory() -> String {
        let fm = FileManager.default

        // 1. Inside .app bundle: Contents/Resources/server/main.py
        if let resourcePath = Bundle.main.resourcePath {
            if fm.fileExists(atPath: "\(resourcePath)/server/main.py") {
                return resourcePath
            }
        }

        // 2. Development: server/ alongside the .app or binary
        let bundleParent = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        if fm.fileExists(atPath: "\(bundleParent)/server/main.py") {
            return bundleParent
        }

        // 3. Two levels up from binary (swift build output: .build/debug/SuperWispr)
        let binaryDir = (Bundle.main.executablePath ?? "") as NSString
        let twoUp = (binaryDir.deletingLastPathComponent as NSString).deletingLastPathComponent
        let threeUp = (twoUp as NSString).deletingLastPathComponent
        if fm.fileExists(atPath: "\(threeUp)/server/main.py") {
            return threeUp
        }

        // 4. Current working directory
        let cwd = fm.currentDirectoryPath
        if fm.fileExists(atPath: "\(cwd)/server/main.py") {
            return cwd
        }

        logger.error("Could not find server/main.py in any expected location")
        return cwd
    }

    @discardableResult
    private func setupLogFile() -> URL? {
        let logDir = NSHomeDirectory() + "/Library/Logs/superWispr"
        try? FileManager.default.createDirectory(
            atPath: logDir, withIntermediateDirectories: true)
        let logPath = logDir + "/server.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        return URL(fileURLWithPath: logPath)
    }
}
