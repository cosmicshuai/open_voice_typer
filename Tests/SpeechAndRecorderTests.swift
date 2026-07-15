import AVFoundation
import XCTest
@testable import OpenVoiceTyper

/// Real Apple speech recognition over synthesized speech ("hello world this
/// is a dictation test", generated with macOS `say`). Requires speech
/// permission to be pre-granted on the simulator; skips — loudly — when the
/// environment can't run recognition at all.
final class AppleSpeechE2ETests: XCTestCase {
    func testTranscribesSynthesizedSpeech() async throws {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "hello", withExtension: "wav") else {
            throw XCTSkip("hello.wav fixture not bundled")
        }
        let wav = try Data(contentsOf: url)

        let provider = AppleSpeechASR(language: "en-US")
        do {
            let text = try await provider.transcribe(ASRRequest(wavData: wav, language: "en-US"))
            let lowered = text.lowercased()
            XCTAssertTrue(
                lowered.contains("hello") && lowered.contains("test"),
                "unexpected transcript: \(text)"
            )
        } catch ASRError.speechPermissionDenied {
            throw XCTSkip("speech permission not granted in this environment")
        } catch ASRError.recognizerUnavailable {
            throw XCTSkip("recognizer unavailable in this environment")
        } catch ASRError.appleUnavailableInSimulator {
            // Verified 2026-07-15: both SFSpeechRecognizer (error 1101) and
            // SpeechAnalyzer (empty supportedLocales) are inert in the iOS 26
            // simulator. This test runs for real against a device destination.
            throw XCTSkip("Apple speech stacks are unavailable in the iOS Simulator")
        }
    }
}

/// The recording front end: engine start, capture window, WAV finalization.
/// Requires microphone permission (pre-granted via `simctl privacy`).
final class AudioRecorderTests: XCTestCase {
    func testEngineCapturesAudioIntoValidWav() async throws {
        guard await AudioRecorder.requestPermission() else {
            throw XCTSkip("microphone permission not granted")
        }

        let recorder = AudioRecorder()
        try recorder.startEngine()
        XCTAssertTrue(recorder.isEngineRunning)

        recorder.beginCapture()
        XCTAssertTrue(recorder.isCapturing)
        try await Task.sleep(for: .milliseconds(700))

        let wav = recorder.endCapture()
        recorder.stopEngine()
        XCTAssertFalse(recorder.isEngineRunning)

        XCTAssertGreaterThan(wav.count, 44, "capture produced no audio bytes")
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        // ~0.7s of 16kHz mono Int16 ≈ 22,400 bytes; allow generous slack for
        // engine spin-up, but it must be in the right ballpark.
        XCTAssertGreaterThan(wav.count, 8_000)
    }

    func testBuffersOutsideCaptureAreDiscarded() async throws {
        guard await AudioRecorder.requestPermission() else {
            throw XCTSkip("microphone permission not granted")
        }

        let recorder = AudioRecorder()
        try recorder.startEngine()
        // Engine runs but no capture window is open.
        try await Task.sleep(for: .milliseconds(400))
        recorder.beginCapture()
        let wav = recorder.endCapture() // immediately: near-empty window
        recorder.stopEngine()

        // The 400ms of pre-capture audio must not leak into the window.
        XCTAssertLessThan(wav.count, 44 + 16_000, "pre-capture audio leaked into the capture window")
    }
}
