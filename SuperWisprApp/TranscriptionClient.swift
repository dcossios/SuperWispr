import Foundation
import os

/// HTTP client for the local Python transcription server.
final class TranscriptionClient {
    private let baseURL = URL(string: "http://127.0.0.1:9876")!
    private let session: URLSession
    private let logger = Logger(subsystem: "com.superwispr", category: "TranscriptionClient")

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    struct TranscriptionResult {
        let text: String
        let raw: String
        let model: String
    }

    func transcribe(
        fileURL: URL,
        language: String = "auto",
        cleanup: Bool = true
    ) async throws -> TranscriptionResult {
        var components = URLComponents(url: baseURL.appendingPathComponent("transcribe"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "cleanup", value: cleanup ? "true" : "false"),
        ]

        let boundary = UUID().uuidString
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError(http.statusCode, message)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw TranscriptionError.decodingFailed
        }

        return TranscriptionResult(
            text: text,
            raw: json["raw"] as? String ?? text,
            model: json["model"] as? String ?? ""
        )
    }
}

enum TranscriptionError: LocalizedError {
    case invalidResponse
    case serverError(Int, String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from transcription server."
        case .serverError(let code, let msg):
            return "Server error \(code): \(msg)"
        case .decodingFailed:
            return "Failed to decode server response."
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
