import Foundation

/// Whisper-style transcription against any OpenAI-compatible endpoint:
/// `POST {baseURL}/audio/transcriptions` (multipart). Covers OpenAI
/// (`gpt-4o-transcribe`, `whisper-1`), Groq (`whisper-large-v3-turbo`), etc.
struct OpenAICompatibleASR: ASRProvider {
    var baseURL: String
    var model: String
    var apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    func transcribe(_ request: ASRRequest) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw ASRError.missingAPIKey }
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(trimmedBase)/audio/transcriptions") else {
            throw ASRError.invalidBaseURL(baseURL)
        }

        var form = MultipartForm()
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: request.wavData)
        form.addField(name: "model", value: model)
        form.addField(name: "response_format", value: "json")
        if !request.language.isEmpty {
            form.addField(name: "language", value: request.language)
        }
        if !request.hotwords.isEmpty {
            // Whisper-style biasing: terms in the prompt are spelled as given.
            form.addField(name: "prompt", value: request.hotwords.joined(separator: ", "))
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(form.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = form.encode()

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ASRError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }

        struct TranscriptionResponse: Decodable { let text: String }
        let text = try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ASRError.emptyTranscript }
        return text
    }
}

/// Minimal multipart/form-data encoder.
struct MultipartForm {
    private let boundary = "OpenVoiceTyper-\(UUID().uuidString)"
    private var parts: [Data] = []

    var contentTypeHeader: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        var part = Data()
        part.append("--\(boundary)\r\n")
        part.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        part.append("\(value)\r\n")
        parts.append(part)
    }

    mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        var part = Data()
        part.append("--\(boundary)\r\n")
        part.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        part.append("Content-Type: \(contentType)\r\n\r\n")
        part.append(data)
        part.append("\r\n")
        parts.append(part)
    }

    func encode() -> Data {
        var body = Data()
        parts.forEach { body.append($0) }
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
