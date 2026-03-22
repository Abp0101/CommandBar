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

    // MARK: - Intent Classification

    func classifyIntent(_ query: String) async -> Intent {
        let lower = query.lowercased()
        let actionPrefixes = [
            "open", "launch", "start", "create", "make", "new",
            "move", "copy", "delete", "remove", "play", "pause",
            "close", "quit", "run", "execute", "switch", "show",
            "hide", "enable", "disable", "install", "set up",
            "take a", "empty", "set volume", "mute", "unmute",
        ]
        if actionPrefixes.contains(where: { lower.hasPrefix($0 + " ") || lower == $0 }) {
            return Intent(isAction: true, query: query)
        }

        let system = """
        You are a one-word classifier embedded in a macOS command bar.
        Reply with ONLY one word: "action" or "question".
        "action" = user wants the computer to DO something.
        "question" = user wants an answer or information.
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
        You are a concise, helpful AI assistant embedded in a macOS command bar overlay.
        - Be brief (≤150 words unless more is clearly needed).
        - Use markdown sparingly (bold and inline code are fine).
        - Never open with "Certainly", "Sure", or "Of course".
        - Match the user's language.
        """

        if let app = appContext {
            system += "\n\n\(app.contextString)"
        }

        var userContent = query
        if let sel = selectedText, !sel.isEmpty {
            userContent = """
            The user has this text selected:
            \"\"\"\
            \(sel)
            \"\"\"

            User's request: \(query)
            """
        }

        let messages: [[String: String]] = [
            ["role": "system",    "content": system],
            ["role": "user",      "content": userContent],
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
        You produce step plans for a macOS automation agent.
        Output ONLY a valid JSON array of short step descriptions (max 8 words each).
        No preamble, no markdown, just the array.
        Example: ["Open Finder","Navigate to Downloads","Sort by date modified"]
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
