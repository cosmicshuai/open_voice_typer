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

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PolishError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }

        struct MessagesResponse: Decodable {
            struct ContentBlock: Decodable {
                let type: String
                let text: String?
            }
            let content: [ContentBlock]
        }
        let text = try JSONDecoder().decode(MessagesResponse.self, from: data)
            .content.compactMap { $0.type == "text" ? $0.text : nil }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PolishError.emptyResponse }
        return text
    }
}
