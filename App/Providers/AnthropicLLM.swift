import Foundation

/// Polish via the Anthropic Messages API.
struct AnthropicLLM: PolishProvider {
    var model: String = "claude-sonnet-5"
    var apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func polish(_ request: PolishRequest) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw PolishError.missingAPIKey }

        struct Body: Encodable {
            struct Message: Encodable { let role: String; let content: String }
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Message]
        }
        let body = Body(
            model: model,
            max_tokens: 4096,
            system: PromptBuilder.systemPrompt(for: request),
            messages: [.init(role: "user", content: request.transcript)]
        )

        struct MessagesResponse: Decodable {
            struct ContentBlock: Decodable {
                let type: String
                let text: String?
            }
            let content: [ContentBlock]
        }
        return try await PolishHTTP.post(
            Self.endpoint,
            body: body,
            headers: ["x-api-key": key, "anthropic-version": "2023-06-01"],
            session: session,
            as: MessagesResponse.self
        ) { response in
            response.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        }
    }
}
