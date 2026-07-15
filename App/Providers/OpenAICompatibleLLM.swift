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

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PolishError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }

        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let text = try JSONDecoder().decode(Completion.self, from: data)
            .choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw PolishError.emptyResponse }
        return text
    }
}
