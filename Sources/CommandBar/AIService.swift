import Foundation

// MARK: - Intent

struct Intent {
    let isAction: Bool
    let query: String
}

// MARK: - AIService (Ollama)

final class AIService {

    static let shared = AIService()

    private var host: String {
        UserDefaults.standard.string(forKey: "ollamaHost") ?? "http://localhost:11434"
    }

    private var model: String {
        UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
    }

    private var chatURL: URL {
        URL(string: "\(host)/api/chat")!
    }

    // MARK: - Shared identity

    /// Single source of truth for what CommandBar is and what it can do.
    /// Injected into every prompt so the model always knows its boundaries.
    private let identity = """
    You are CommandBar, an AI-powered macOS command bar that runs locally via Ollama.
    You are summoned with ⌘⌥A and appear as a floating overlay on the user's screen.

    ## What you CAN do
    - Open, launch, quit, or switch to any installed Mac application
    - Reveal files and folders in Finder
    - Adjust system volume (up, down, mute, unmute)
    - Control media playback (play, pause, next, previous) via AppleScript
    - Run saved workflows (named sequences of the above actions)
    - Answer questions and explain things concisely

    ## What you CANNOT do
    - Browse the internet or fetch live data
    - Send emails, messages, or notifications
    - Read or write files (you can only reveal them in Finder)
    - Control the internal UI of third-party apps beyond launching them
    - Install or uninstall software
    - Access cameras, microphones, or system sensors
    - Anything requiring permissions CommandBar does not hold

    If the user asks for something outside your capabilities, say so clearly in one sentence and suggest the closest thing you *can* do instead.
    """

    // MARK: - Intent Classification

    func classifyIntent(_ query: String) async -> Intent {
        let lower = query.lowercased()
        let actionPrefixes = [
            "open", "launch", "start", "create", "make", "new",
            "move", "copy", "delete", "remove", "play", "pause",
            "close", "quit", "run", "execute", "switch", "show",
            "hide", "enable", "disable", "set up",
            "take a", "empty", "set volume", "mute", "unmute",
        ]
        if actionPrefixes.contains(where: { lower.hasPrefix($0 + " ") || lower == $0 }) {
            return Intent(isAction: true, query: query)
        }

        let system = """
        \(identity)

        Your task right now: classify the user's message as "action" or "question".
        Reply with ONLY one word.
        "action" = the user wants you to DO something on their Mac.
        "question" = the user wants an answer, explanation, or information.
        """
        let result = (try? await sendSingle(system: system, user: query)) ?? "question"
        return Intent(isAction: result.lowercased().hasPrefix("action"), query: query)
    }

    // MARK: - Streaming Answer

    func streamAnswer(
        for query: String,
        appContext: FrontmostApp?,
        selectedText: String?,
        onChunk: @escaping (String) async -> Void
    ) async {
        var system = """
        \(identity)

        ## Response style
        - Be brief (≤150 words unless clearly more is needed).
        - Use markdown sparingly — bold and inline code are fine.
        - Never open with "Certainly", "Sure", or "Of course".
        - Match the user's language.
        - If the request is outside your capabilities, say so in one sentence and suggest what you *can* do.
        """

        if let app = appContext {
            system += "\n\n\(app.contextString)"
        }

        var userContent = query
        if let sel = selectedText, !sel.isEmpty {
            userContent = """
            The user has this text selected:
            \"\"\"
            \(sel)
            \"\"\"

            User's request: \(query)
            """
        }

        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user",   "content": userContent],
        ]

        guard let req = makeRequest(messages: messages, stream: true) else {
            await onChunk("⚠️ Could not build request.")
            return
        }

        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            for try await line in bytes.lines {
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let evt  = try? JSONDecoder().decode(OllamaChunk.self, from: data),
                      !evt.done,
                      let text = evt.message?.content, !text.isEmpty
                else { continue }
                await onChunk(text)
            }
        } catch {
            await onChunk("\n\n⚠️ Stream error: \(error.localizedDescription)")
        }
    }

    // MARK: - Step Generation

    func generateSteps(for query: String) async -> [String] {
        let system = """
        \(identity)

        Your task right now: produce an ordered step plan to carry out the user's request using ONLY your supported capabilities.
        Output ONLY a valid JSON array of short step descriptions (max 8 words each).
        Each step must map to something CommandBar can actually execute: open an app, reveal in Finder, adjust volume, or control media.
        If the request is impossible with your capabilities, return: ["Cannot do that — outside CommandBar's capabilities"]
        No preamble, no markdown, just the JSON array.
        Example: ["Open Finder", "Navigate to Downloads folder", "Sort by date modified"]
        """
        guard let raw  = try? await sendSingle(system: system, user: query),
              let data = raw.data(using: .utf8),
              let steps = try? JSONDecoder().decode([String].self, from: data) else {
            return ["Execute: \(query)"]
        }
        return steps
    }

    // MARK: - Private

    private func sendSingle(system: String, user: String) async throws -> String {
        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user",   "content": user],
        ]
        guard let req = makeRequest(messages: messages, stream: false) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return resp.message?.content ?? ""
    }

    private func makeRequest(messages: [[String: String]], stream: Bool) -> URLRequest? {
        guard let body = try? JSONSerialization.data(withJSONObject: [
            "model":    model,
            "messages": messages,
            "stream":   stream,
        ]) else { return nil }

        var req = URLRequest(url: chatURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }
}

// MARK: - Codable helpers

private struct OllamaChunk: Decodable {
    let done: Bool
    let message: OllamaMessage?
}

private struct OllamaResponse: Decodable {
    let message: OllamaMessage?
}

private struct OllamaMessage: Decodable {
    let role: String?
    let content: String?
}
