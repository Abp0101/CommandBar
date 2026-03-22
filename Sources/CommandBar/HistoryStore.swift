import Foundation
import Combine

/// Stores the last N distinct queries the user has submitted.
/// Exposed as a simple ordered array; the bar navigates it with ↑ / ↓.
final class HistoryStore: ObservableObject {

    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let maxItems = 200
    private let fileURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CommandBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("history.json")
    }()

    init() { load() }

    // MARK: - Public API

    /// Record a new query (deduplicates — moves to front if already exists).
    func record(_ query: String, wasAction: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.removeAll { $0.query == trimmed }
        entries.insert(HistoryEntry(query: trimmed, wasAction: wasAction), at: 0)
        if entries.count > maxItems { entries = Array(entries.prefix(maxItems)) }
        persist()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Persistence

    private func persist() {
        let data = (try? JSONEncoder().encode(entries)) ?? Data()
        try? data.write(to: fileURL, options: .atomicWrite)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = saved
    }
}

// MARK: - Model

struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let query: String
    let wasAction: Bool
    let timestamp: Date

    init(query: String, wasAction: Bool) {
        self.id        = UUID()
        self.query     = query
        self.wasAction = wasAction
        self.timestamp = Date()
    }
}
