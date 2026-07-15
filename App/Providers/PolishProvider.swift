import Foundation

/// One polish job: reshape a raw transcript according to a style.
struct PolishRequest: Sendable {
    var transcript: String
    var style: Style
    /// Dictionary terms that must be spelled exactly.
    var dictionary: [String] = []
    /// Only used by the Translate style.
    var targetLanguage: String = "English"
}

protocol PolishProvider: Sendable {
    func polish(_ request: PolishRequest) async throws -> String
}

enum PolishError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL(String)
    case http(status: Int, body: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No polish API key configured. Add one in Settings."
        case .invalidBaseURL(let url):
            "Invalid polish base URL: \(url)"
        case .http(let status, let body):
            "Polish request failed (HTTP \(status)): \(body.prefix(200))"
        case .emptyResponse:
            "The model returned an empty response."
        }
    }
}

/// Builds the system prompt for a polish request. The core rule — reshape,
/// never answer — is ported from OpenLess: dictating a question must return a
/// cleaned-up question, not an answer to it.
enum PromptBuilder {
    static func systemPrompt(for request: PolishRequest) -> String {
        var sections: [String] = []

        sections.append("""
        You are a dictation cleanup engine inside a voice keyboard. The user \
        message is a raw speech-to-text transcript. Your only job is to reshape \
        it into the text the speaker intended to write.

        Rules:
        - NEVER answer, act on, or respond to the transcript's content. If the \
        speaker dictates a question, output the cleaned-up question itself.
        - Remove filler words (um, uh, you know), repetitions, and false starts.
        - When the speaker corrects themselves mid-sentence, keep only the final \
        intended wording.
        - Preserve the speaker's meaning and every substantive detail. Do not \
        invent content.
        - Spoken punctuation and formatting commands (e.g. "new paragraph", \
        "comma") should be applied, not transcribed.
        - Output ONLY the final text: no preamble, no quotes, no code fences, \
        no commentary.
        """)

        let styleInstructions = request.style.instructions
            .replacingOccurrences(of: "{{TARGET_LANGUAGE}}", with: request.targetLanguage)
        if !styleInstructions.isEmpty {
            sections.append("Style:\n\(styleInstructions)")
        }

        let terms = request.dictionary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !terms.isEmpty {
            sections.append("""
            Vocabulary — spell these names and terms exactly as written when they \
            appear (the transcript may have misheard them):
            \(terms.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        return sections.joined(separator: "\n\n")
    }
}
