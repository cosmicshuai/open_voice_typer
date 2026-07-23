import Foundation

/// Shared request/response plumbing for JSON polish providers. Every provider
/// posts a JSON body, checks the status the same way, and guards against an
/// empty result — so this centralizes all of that, leaving each provider to
/// supply just a body, its auth headers, and a text extractor. Adding a
/// provider stays small.
enum PolishHTTP {
    static func post<Body: Encodable, Response: Decodable>(
        _ url: URL,
        body: Body,
        headers: [String: String],
        session: URLSession,
        as responseType: Response.Type,
        extract: (Response) -> String?
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PolishError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = (extract(decoded) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PolishError.emptyResponse }
        return text
    }
}
