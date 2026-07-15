import Foundation

/// One transcription job: finalized 16 kHz mono PCM audio plus context.
struct ASRRequest: Sendable {
    /// Complete WAV file (16 kHz, mono, 16-bit PCM).
    var wavData: Data
    /// BCP-47 / ISO-639 language hint; empty means auto-detect.
    var language: String = ""
    /// Dictionary terms the recognizer should bias toward.
    var hotwords: [String] = []
}

protocol ASRProvider: Sendable {
    func transcribe(_ request: ASRRequest) async throws -> String
}

enum ASRError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL(String)
    case http(status: Int, body: String)
    case emptyTranscript
    case speechPermissionDenied
    case recognizerUnavailable
    case appleRecognitionFailed(String)
    case appleUnavailableInSimulator

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No ASR API key configured. Add one in Settings."
        case .invalidBaseURL(let url):
            "Invalid ASR base URL: \(url)"
        case .http(let status, let body):
            "ASR request failed (HTTP \(status)): \(body.prefix(200))"
        case .emptyTranscript:
            "No speech was recognized."
        case .speechPermissionDenied:
            "Speech recognition permission was denied. Enable it in iOS Settings."
        case .recognizerUnavailable:
            "On-device speech recognition is unavailable for the selected language."
        case .appleRecognitionFailed(let reason):
            "Apple speech recognition failed: \(reason) Check that Siri & Dictation is enabled in iOS Settings, or switch to a cloud engine in Settings."
        case .appleUnavailableInSimulator:
            "Apple speech recognition is not available in the iOS Simulator. Use a cloud ASR engine (Settings → Speech to text → Cloud) or run on a real device."
        }
    }
}
