# Open Voice Typer

An open-source iOS/iPadOS voice-input keyboard, in the spirit of [Typeless](https://www.typeless.com/) and [Wispr Flow](https://wisprflow.ai/) — the iOS counterpart of [OpenLess](https://github.com/Open-Less/openless). Speak into a custom keyboard in any app and get AI-polished text at your cursor, using **your own API keys**.

## How it works

iOS keyboard extensions cannot access the microphone, so recording happens in the main app:

1. Open the app and start a **dictation session** (the app holds a background audio session).
2. In any app, switch to the **Voice Typer** keyboard and tap **Speak**.
3. The main app records, transcribes (ASR), polishes the text with an LLM, and the keyboard inserts the result at the cursor.

## Providers (bring your own keys)

- **ASR**: any OpenAI-compatible endpoint — OpenAI, Groq, Zhipu **GLM-ASR** (`glm-asr-2512`) — or Apple on-device speech (free, offline, no key).
- **Polish**: any OpenAI-compatible chat endpoint — OpenAI, Groq, **DeepSeek V4** (`deepseek-v4-flash` / `-pro`) — plus native Anthropic and Google Gemini.

Settings includes one-tap presets for OpenAI, Groq, DeepSeek V4, and Zhipu GLM (China + international endpoints).

Keys are stored in the iOS Keychain and only ever read by the main app — never by the keyboard extension.

## Building

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), iOS 26 deployment target.

```sh
xcodegen generate
open OpenVoiceTyper.xcodeproj
```

Or from the CLI:

```sh
xcodebuild -project OpenVoiceTyper.xcodeproj -scheme OpenVoiceTyper \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

The `.xcodeproj` is generated and not committed — `project.yml` is the source of truth.
