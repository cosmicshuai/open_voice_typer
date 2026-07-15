import Foundation
import Speech

/// On-device transcription via Apple's Speech framework — free, offline, and
/// the default before any API key is configured. Uses `SFSpeechRecognizer`
/// (the stable API); upgrading to the iOS 26 `SpeechAnalyzer` stack is
/// tracked as a follow-up and slots in behind the same `ASRProvider` protocol.
struct AppleSpeechASR: ASRProvider {
    /// Empty means the current locale.
    var language: String = ""

    func transcribe(_ request: ASRRequest) async throws -> String {
        let status = await requestAuthorization()
        guard status == .authorized else { throw ASRError.speechPermissionDenied }

        let localeID = request.language.isEmpty ? language : request.language
        let locale = localeID.isEmpty ? Locale.current : Locale(identifier: localeID)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw ASRError.recognizerUnavailable
        }

        // SFSpeechURLRecognitionRequest needs a file on disk.
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-\(UUID().uuidString).wav")
        try request.wavData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let recognitionRequest = SFSpeechURLRecognitionRequest(url: fileURL)
        recognitionRequest.shouldReportPartialResults = false
        recognitionRequest.contextualStrings = request.hotwords
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        let text: String = try await withCheckedThrowingContinuation { continuation in
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                    task = nil
                } else if let error {
                    continuation.resume(throwing: error)
                    task = nil
                }
            }
            _ = task
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ASRError.emptyTranscript }
        return trimmed
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
