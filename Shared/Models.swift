import Foundation

// MARK: - Styles

/// An output style: how dictated speech is reshaped into text.
/// Ported from OpenLess's output modes (raw / light / structured / formal)
/// plus translation and user-defined style packs.
struct Style: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    /// Style-specific instructions appended to the base polish prompt.
    /// Empty for `raw`, which skips the LLM entirely.
    var instructions: String
    var isBuiltIn: Bool

    static let raw = Style(
        id: "builtin.raw",
        name: "Raw",
        instructions: "",
        isBuiltIn: true
    )

    static let light = Style(
        id: "builtin.light",
        name: "Light",
        instructions: """
        Lightly clean up the transcript. Fix punctuation, casing, and obvious \
        transcription mistakes. Remove filler words and false starts. Keep the \
        speaker's wording, tone, and sentence structure as-is otherwise.
        """,
        isBuiltIn: true
    )

    static let structured = Style(
        id: "builtin.structured",
        name: "Structured",
        instructions: """
        Reorganize the transcript into clear, well-structured text. Group related \
        points, use short paragraphs, and use bullet lists where the speaker \
        enumerates items. Preserve every substantive detail; do not add new content.
        """,
        isBuiltIn: true
    )

    static let formal = Style(
        id: "builtin.formal",
        name: "Formal",
        instructions: """
        Rewrite the transcript in a polished, professional register suitable for \
        business communication. Complete sentences, precise wording, no slang. \
        Preserve the speaker's meaning and all substantive details.
        """,
        isBuiltIn: true
    )

    static let translate = Style(
        id: "builtin.translate",
        name: "Translate",
        instructions: """
        Translate the transcript into {{TARGET_LANGUAGE}}. Produce natural phrasing \
        a native speaker would write, not a literal word-for-word translation. \
        Clean up fillers and false starts as part of translating.
        """,
        isBuiltIn: true
    )

    /// The fun one: rambling speech in, Papa's prose out.
    static let hemingway = Style(
        id: "builtin.hemingway",
        name: "Hemingway",
        instructions: """
        Rewrite the transcript in the voice of Ernest Hemingway. Short, declarative \
        sentences. Plain, concrete words — cut adverbs, qualifiers, and ornament. \
        Prefer simple verbs and the active voice. Let facts stand without \
        sentimentality; understatement carries the feeling. Keep the speaker's \
        meaning and every substantive detail. It should read true and clean, \
        like a telegram from a war correspondent who cares about the words.
        """,
        isBuiltIn: true
    )

    static let builtIns: [Style] = [.raw, .light, .structured, .formal, .hemingway, .translate]
}

// MARK: - Dictionary

/// A proper noun or phrase the ASR/polish steps should spell correctly (hotword).
struct DictionaryEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var term: String
    var note: String = ""
    var createdAt: Date = .now
}

// MARK: - Bridge payloads (keyboard <-> app)

/// Command sent from the keyboard extension to the main app.
struct KeyboardCommand: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case startDictation
        case stopDictation
        case cancelDictation
    }

    var id: UUID = UUID()
    var kind: Kind
    var styleID: String
    var issuedAt: Date = .now
}

/// Pipeline status the app publishes for the keyboard to render.
struct PipelineState: Codable, Sendable {
    enum Phase: String, Codable, Sendable {
        case idle
        case recording
        case transcribing
        case polishing
    }

    var phase: Phase = .idle
    /// Which keyboard command this state answers, if any.
    var commandID: UUID?
    /// 0...1 microphone level, only meaningful while recording.
    var audioLevel: Float = 0
    var updatedAt: Date = .now
}

/// Final outcome of one dictation, published by the app for the keyboard to insert.
struct DictationResult: Codable, Sendable {
    var commandID: UUID
    var styleID: String
    var rawText: String
    /// Equals `rawText` for the Raw style or when polish is skipped.
    var polishedText: String
    var errorMessage: String?
    var finishedAt: Date = .now

    var isError: Bool { errorMessage != nil }
}

/// Heartbeat proving the main app's dictation session is alive.
struct SessionHeartbeat: Codable, Sendable {
    var startedAt: Date
    var lastBeatAt: Date
    /// The session is considered dead if the last beat is older than this.
    static let staleAfter: TimeInterval = 5

    var isAlive: Bool {
        Date.now.timeIntervalSince(lastBeatAt) < Self.staleAfter
    }
}
