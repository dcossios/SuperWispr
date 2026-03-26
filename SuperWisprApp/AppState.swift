import Foundation

enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var recordingState: RecordingState = .idle
    @Published var lastTranscription: String = ""
    @Published var serverReady: Bool = false
    @Published var loadedModel: String = ""
    @Published var isModelLoading: Bool = false

    private init() {}
}
