import Foundation
import Combine

// MARK: - Suggestion model

struct Suggestion: Identifiable, Hashable {
    enum Kind { case history, workflow, example }

    let id: UUID
    let text: String
    let kind: Kind
    let icon: String   // SF Symbol name

    init(_ text: String, kind: Kind) {
        self.id   = UUID()
        self.text = text
        self.kind = kind
        self.icon = switch kind {
            case .history:  "clock"
            case .workflow: "bolt"
            case .example:  "sparkles"
        }
    }
}

// MARK: - Engine

final class SuggestionEngine: ObservableObject {

    static let shared = SuggestionEngine()

    @Published private(set) var suggestions: [Suggestion] = []

    private let history   = HistoryStore.shared
    private let workflows = WorkflowStore.shared

    private static let examples: [String] = [
        "Open Xcode",
        "Open Finder at ~/Downloads",
        "Play music on Spotify",
        "Summarise my clipboard",
        "Explain this error",
        "Draft a reply to this email",
        "Move files to Archive",
        "Take a screenshot",
        "Set volume to 50%",
        "Empty the trash",
        "Start my coding environment",
    ]

    // MARK: - Public

    func update(for query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if q.isEmpty {
            // Show most recent 6 history items when bar first opens
            let recent = history.entries.prefix(6).map {
                Suggestion($0.query, kind: .history)
            }
            suggestions = Array(recent)
            return
        }

        let lower = q.lowercased()

        let fromHistory = history.entries
            .filter { fuzzy($0.query, matches: lower) }
            .prefix(4)
            .map { Suggestion($0.query, kind: .history) }

        let fromWorkflows = workflows.workflows
            .filter { fuzzy($0.trigger, matches: lower) || fuzzy($0.name, matches: lower) }
            .prefix(3)
            .map { Suggestion($0.trigger, kind: .workflow) }

        let fromExamples = Self.examples
            .filter { fuzzy($0, matches: lower) }
            .prefix(2)
            .map { Suggestion($0, kind: .example) }

        var merged = Array(fromHistory) + Array(fromWorkflows) + Array(fromExamples)
        // Deduplicate by text
        var seen = Set<String>()
        merged = merged.filter { seen.insert($0.text.lowercased()).inserted }
        suggestions = Array(merged.prefix(8))
    }

    func clear() {
        suggestions = []
    }

    // MARK: - Fuzzy match (all chars of needle appear in haystack in order)

    private func fuzzy(_ haystack: String, matches needle: String) -> Bool {
        var remaining = haystack.lowercased()[...]
        for ch in needle {
            guard let idx = remaining.firstIndex(of: ch) else { return false }
            remaining = remaining[remaining.index(after: idx)...]
        }
        return true
    }
}
