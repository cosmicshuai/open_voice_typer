import XCTest
@testable import OpenVoiceTyper

/// The full dictation pipeline — provider factory, multipart audio upload,
/// hotword propagation, prompt building, polish, outcome metadata — run
/// end-to-end over stubbed provider HTTP. Uses global URLProtocol
/// registration because the pipeline's providers use `URLSession.shared`.
final class PipelineE2ETests: XCTestCase {
    private var savedSettings: ProviderSettings!
    private var savedDictionary: [DictionaryEntry]!

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
        savedSettings = SettingsStore.load()
        savedDictionary = SharedCatalog.loadDictionary()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        StubURLProtocol.reset()
        SettingsStore.save(savedSettings)
        SharedCatalog.saveDictionary(savedDictionary)
        KeychainStore.delete(.asrAPIKey)
        KeychainStore.delete(.polishOpenAIKey)
        super.tearDown()
    }

    func testFullPipelineCloudASRPlusPolish() async throws {
        // Arrange: cloud ASR + OpenAI-compatible polish, one dictionary term.
        var settings = ProviderSettings()
        settings.asrBackend = .openAICompatible
        settings.asrBaseURL = "https://asr.stub.test/v1"
        settings.asrModel = "whisper-large-v3-turbo"
        settings.polishBackend = .openAICompatible
        settings.polishBaseURL = "https://llm.stub.test/v1"
        settings.polishModel = "test-polish-model"
        KeychainStore.set("sk-asr-test", for: .asrAPIKey)
        KeychainStore.set("sk-llm-test", for: .polishOpenAIKey)
        SharedCatalog.saveDictionary([DictionaryEntry(term: "OpenVoiceTyper")])

        StubURLProtocol.stub(host: "asr.stub.test") { request, body in
            XCTAssertEqual(request.url?.path(), "/v1/audio/transcriptions")
            let form = String(decoding: body, as: UTF8.self)
            XCTAssertTrue(form.contains("name=\"file\""), "audio file part missing")
            XCTAssertTrue(form.contains("OpenVoiceTyper"), "dictionary hotword missing from ASR prompt")
            return .init(body: Data(#"{"text":"um hello open voice typer test"}"#.utf8))
        }
        StubURLProtocol.stub(host: "llm.stub.test") { _, body in
            let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            let messages = json["messages"] as! [[String: Any]]
            let system = messages[0]["content"] as! String
            XCTAssertTrue(system.contains("NEVER answer"), "base rules missing")
            XCTAssertTrue(system.contains("OpenVoiceTyper"), "dictionary missing from polish prompt")
            XCTAssertEqual(messages[1]["content"] as! String, "um hello open voice typer test")
            return .init(body: Data(#"{"choices":[{"message":{"content":"Hello, OpenVoiceTyper test."}}]}"#.utf8))
        }

        // Act: run the real pipeline over the synthesized speech fixture.
        let wav = try fixtureWAV()
        let outcome = try await DictationPipeline(settings: settings).run(wavData: wav, style: .light)

        // Assert: both stages ran and metadata is right.
        XCTAssertEqual(outcome.rawText, "um hello open voice typer test")
        XCTAssertEqual(outcome.polishedText, "Hello, OpenVoiceTyper test.")
        XCTAssertEqual(outcome.engineName, "test-polish-model")
        // afconvert pads the fixture header, so the 44-byte-header estimate
        // reads slightly high; recorder-produced WAVs are exact.
        XCTAssertEqual(outcome.audioSeconds, 2.2, accuracy: 0.15)
    }

    func testRawStyleSkipsPolishEntirely() async throws {
        var settings = ProviderSettings()
        settings.asrBackend = .openAICompatible
        settings.asrBaseURL = "https://asr.stub.test/v1"
        settings.asrModel = "whisper-1"
        KeychainStore.set("sk-asr-test", for: .asrAPIKey)

        StubURLProtocol.stub(host: "asr.stub.test") { _, _ in
            .init(body: Data(#"{"text":"verbatim words"}"#.utf8))
        }
        // No polish stub: any polish call would fail the test with unsupportedURL.

        let outcome = try await DictationPipeline(settings: settings)
            .run(wavData: try fixtureWAV(), style: .raw)
        XCTAssertEqual(outcome.polishedText, "verbatim words")
        XCTAssertEqual(outcome.engineName, "whisper-1")
    }

    private func fixtureWAV() throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "hello", withExtension: "wav") else {
            throw XCTSkip("hello.wav fixture not bundled")
        }
        return try Data(contentsOf: url)
    }
}
