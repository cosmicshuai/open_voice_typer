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

final class PolishBackendSpecTests: XCTestCase {
    func testRegistryHasExactlyOneSpecPerBackend() {
        XCTAssertEqual(
            PolishBackendSpec.all.count,
            ProviderSettings.PolishBackend.allCases.count,
            "registry must stay exhaustive — one spec per backend"
        )
        for backend in ProviderSettings.PolishBackend.allCases {
            XCTAssertEqual(PolishBackendSpec.for(backend).backend, backend)
        }
    }

    func testKeychainKeysAreDistinctPerBackend() {
        let keys = PolishBackendSpec.all.map(\.keychainKey)
        XCTAssertEqual(Set(keys).count, keys.count, "each backend needs its own key slot")
    }

    func testModelKeyPathsResolveToTheRightField() {
        var settings = ProviderSettings()
        settings.deepseekModel = "deepseek-v4-pro"
        settings.anthropicModel = "claude-x"
        XCTAssertEqual(PolishBackendSpec.for(.deepseek).model(in: settings), "deepseek-v4-pro")
        XCTAssertEqual(PolishBackendSpec.for(.anthropic).model(in: settings), "claude-x")
    }

    func testOnlyOpenAICompatibleHasAConfigurableBaseURL() {
        XCTAssertTrue(PolishBackendSpec.for(.openAICompatible).hasConfigurableBaseURL)
        XCTAssertFalse(PolishBackendSpec.for(.deepseek).hasConfigurableBaseURL)
        XCTAssertFalse(PolishBackendSpec.for(.anthropic).hasConfigurableBaseURL)
        XCTAssertFalse(PolishBackendSpec.for(.gemini).hasConfigurableBaseURL)
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

    func testInvalidTargetLanguageClampsToDefault() throws {
        let bad = try JSONDecoder().decode(ProviderSettings.self, from: Data(#"{"targetLanguage":"Klingon"}"#.utf8))
        XCTAssertEqual(bad.targetLanguage, "English", "an unknown language must clamp to the default")

        let good = try JSONDecoder().decode(ProviderSettings.self, from: Data(#"{"targetLanguage":"Japanese"}"#.utf8))
        XCTAssertEqual(good.targetLanguage, "Japanese", "a known language must be preserved")
    }
}

final class AsyncRetryTests: XCTestCase {
    private actor Counter {
        private(set) var count = 0
        func bump() -> Int { count += 1; return count }
    }

    func testRetriesTimeoutThenSucceeds() async throws {
        let counter = Counter()
        let result = try await AsyncRetry.retryingOnTimeout(maxAttempts: 3, timeout: .milliseconds(80)) {
            let n = await counter.bump()
            if n < 3 { try await Task.sleep(for: .milliseconds(400)) } // first two time out
            return "done"
        }
        XCTAssertEqual(result, "done")
        let attempts = await counter.count
        XCTAssertEqual(attempts, 3, "should have retried twice before succeeding on the third try")
    }

    func testNonTimeoutErrorFailsImmediately() async {
        let counter = Counter()
        do {
            _ = try await AsyncRetry.retryingOnTimeout(maxAttempts: 3, timeout: .seconds(5)) { () async throws -> String in
                _ = await counter.bump()
                throw PolishError.missingAPIKey
            }
            XCTFail("a non-timeout error should propagate, not retry")
        } catch {
            XCTAssertTrue(error is PolishError)
        }
        let attempts = await counter.count
        XCTAssertEqual(attempts, 1, "a bad-key error must not be retried")
    }

    func testExhaustsRetriesThenThrowsTimeout() async {
        let counter = Counter()
        do {
            _ = try await AsyncRetry.retryingOnTimeout(maxAttempts: 3, timeout: .milliseconds(60)) { () async throws -> String in
                _ = await counter.bump()
                try await Task.sleep(for: .milliseconds(400)) // always times out
                return "never"
            }
            XCTFail("should throw after exhausting retries")
        } catch {
            XCTAssertTrue(error is TimeoutError, "final failure should be a timeout")
        }
        let attempts = await counter.count
        XCTAssertEqual(attempts, 3, "should try the full budget of attempts")
    }
}

/// Boxes captured request bodies across the Sendable stub boundary.
final class ReceivedBox: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func set(_ value: Data) { lock.withLock { data = value } }
    func get() -> Data { lock.withLock { data } }
}
