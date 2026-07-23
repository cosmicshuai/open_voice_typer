import Foundation

/// Chat-completions polish against any OpenAI-compatible endpoint:
/// `POST {baseURL}/chat/completions`. Covers OpenAI, Groq, OpenRouter,
/// DeepSeek, local servers, etc.
struct OpenAICompatibleLLM: PolishProvider {
    var baseURL: String
    var model: String
    var apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    func polish(_ request: PolishRequest) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw PolishError.missingAPIKey }
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
            throw PolishError.invalidBaseURL(baseURL)
        }

        struct Body: Encodable {
            struct Message: Encodable { let role: String; let content: String }
            let model: String
            let messages: [Message]
        }
        let body = Body(model: model, messages: [
            .init(role: "system", content: PromptBuilder.systemPrompt(for: request)),
            .init(role: "user", content: request.transcript),
        ])

        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        return try await PolishHTTP.post(
            url,
            body: body,
            headers: ["Authorization": "Bearer \(key)"],
            session: session,
            as: Completion.self
        ) { response in
            response.choices.first?.message.content
        }
    }
}
