import XCTest
@testable import OpenVoiceTyper

final class WAVEncodingTests: XCTestCase {
    func testWavHeaderIsWellFormed() {
        let pcm = Data(repeating: 0xAB, count: 32_000) // 1s of 16kHz mono Int16
        let wav = AudioRecorder.wavFile(fromPCM: pcm)

        XCTAssertEqual(wav.count, 44 + pcm.count)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")
        // Sample rate at offset 24, little-endian.
        let sampleRate = wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: sampleRate), 16_000)
    }

    func testAudioSecondsFromWav() {
        let wav = AudioRecorder.wavFile(fromPCM: Data(count: 64_000)) // 2s
        XCTAssertEqual(DictationPipeline.audioSeconds(ofWAV: wav), 2.0, accuracy: 0.001)
    }
}

final class MultipartDialectTests: XCTestCase {
    private func formBody(baseURL: String, hotwords: [String]) async throws -> String {
        let received = ReceivedBox()
        StubURLProtocol.stub(host: URL(string: baseURL)!.host()!) { _, body in
            received.set(body)
            return .init(body: Data(#"{"text":"ok"}"#.utf8))
        }
        defer { StubURLProtocol.reset() }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let asr = OpenAICompatibleASR(
            baseURL: baseURL,
            model: "test-model",
            apiKey: { "sk-test" },
            session: URLSession(configuration: config)
        )
        _ = try await asr.transcribe(ASRRequest(wavData: Data(count: 100), hotwords: hotwords))
        return String(decoding: received.get(), as: UTF8.self)
    }

    func testOpenAIDialectSendsPromptAndResponseFormat() async throws {
        let body = try await formBody(baseURL: "https://api.openai.com/v1", hotwords: ["XcodeGen", "Wispr"])
        XCTAssertTrue(body.contains("name=\"response_format\""))
        XCTAssertTrue(body.contains("name=\"prompt\""))
        XCTAssertTrue(body.contains("XcodeGen, Wispr"))
        XCTAssertFalse(body.contains("name=\"stream\""))
    }

    func testGLMDialectSendsStreamFalseAndNoPrompt() async throws {
        let body = try await formBody(baseURL: "https://open.bigmodel.cn/api/paas/v4", hotwords: ["XcodeGen"])
        XCTAssertTrue(body.contains("name=\"stream\""))
        XCTAssertFalse(body.contains("name=\"prompt\""), "GLM has no Whisper prompt field")
        XCTAssertFalse(body.contains("name=\"response_format\""))
        XCTAssertTrue(body.contains("glm") == false && body.contains("test-model"))
    }
}

final class PromptBuilderTests: XCTestCase {
    func testPromptContainsBaseRulesStyleAndDictionary() {
        let prompt = PromptBuilder.systemPrompt(for: PolishRequest(
            transcript: "whatever",
            style: .formal,
            dictionary: ["OpenVoiceTyper"],
            targetLanguage: "English"
        ))
        XCTAssertTrue(prompt.contains("NEVER answer"))
        XCTAssertTrue(prompt.contains("professional register"))
        XCTAssertTrue(prompt.contains("- OpenVoiceTyper"))
    }

    func testTranslateStyleSubstitutesTargetLanguage() {
        let prompt = PromptBuilder.systemPrompt(for: PolishRequest(
            transcript: "whatever",
            style: .translate,
            targetLanguage: "Japanese"
        ))
        XCTAssertTrue(prompt.contains("Japanese"))
        XCTAssertFalse(prompt.contains("{{TARGET_LANGUAGE}}"))
    }
}

final class PresetTests: XCTestCase {
    func testPresetsCoverRequestedProviders() {
        XCTAssertTrue(ProviderPreset.asr.contains { $0.model == "glm-asr-2512" })
        // DeepSeek graduated from a preset to a first-class backend.
        XCTAssertFalse(ProviderPreset.polish.contains { $0.baseURL.contains("deepseek") })
    }

    func testDeepSeekIsFirstClassPolishBackend() {
        XCTAssertTrue(ProviderSettings.PolishBackend.allCases.contains(.deepseek))
        XCTAssertEqual(ProviderSettings().deepseekModel, "deepseek-v4-flash")
        XCTAssertTrue(ProviderSettings.deepseekModels.contains("deepseek-v4-pro"))
    }
}

final class SettingsMigrationTests: XCTestCase {
    /// Settings saved before `deepseekModel` (or any later field) existed must
    /// decode intact, not reset to defaults.
    func testOlderSettingsPayloadDecodesWithNewFieldsDefaulted() throws {
        let old = #"{"asrBackend":"apple","polishBackend":"anthropic","anthropicModel":"claude-3-5-haiku","sessionAutoEndMinutes":60}"#
        let settings = try JSONDecoder().decode(ProviderSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.polishBackend, .anthropic)
        XCTAssertEqual(settings.anthropicModel, "claude-3-5-haiku")
        XCTAssertEqual(settings.sessionAutoEndMinutes, 60)
        XCTAssertEqual(settings.deepseekModel, "deepseek-v4-flash", "missing field should take the default")
    }
}

/// Boxes captured request bodies across the Sendable stub boundary.
final class ReceivedBox: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func set(_ value: Data) { lock.withLock { data = value } }
    func get() -> Data { lock.withLock { data } }
}
