import Foundation

/// Polish via the Google Gemini API (`models/{model}:generateContent`).
struct GeminiLLM: PolishProvider {
    var model: String = "gemini-2.5-flash"
    var apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    func polish(_ request: PolishRequest) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw PolishError.missingAPIKey }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw PolishError.invalidBaseURL(model)
        }

        struct Body: Encodable {
            struct Part: Encodable { let text: String }
            struct Content: Encodable {
                var role: String?
                let parts: [Part]
            }
            let systemInstruction: Content
            let contents: [Content]

            enum CodingKeys: String, CodingKey {
                case systemInstruction = "system_instruction"
                case contents
            }
        }
        let body = Body(
            systemInstruction: .init(role: nil, parts: [.init(text: PromptBuilder.systemPrompt(for: request))]),
            contents: [.init(role: "user", parts: [.init(text: request.transcript)])]
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PolishError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }

        struct GenerateResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        let text = (try JSONDecoder().decode(GenerateResponse.self, from: data)
            .candidates?.first?.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PolishError.emptyResponse }
        return text
    }
}
