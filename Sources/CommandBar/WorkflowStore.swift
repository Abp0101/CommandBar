import Foundation
import Combine

// MARK: - Workflow model

struct Workflow: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var trigger: String   // Natural-language phrase that activates this workflow
    var steps: [String]   // Ordered step descriptions
    var createdAt: Date

    init(name: String, trigger: String, steps: [String]) {
        self.id = UUID()
        self.name = name
        self.trigger = trigger
        self.steps = steps
        self.createdAt = Date()
    }
}

// MARK: - Store

final class WorkflowStore: ObservableObject {

    static let shared = WorkflowStore()

    @Published private(set) var workflows: [Workflow] = []

    private let fileURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CommandBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("workflows.json")
    }()

    init() { load() }

    // MARK: - CRUD

    func save(_ workflow: Workflow) {
        workflows.removeAll { $0.id == workflow.id }
        workflows.append(workflow)
        persist()
    }

    func delete(_ workflow: Workflow) {
        workflows.removeAll { $0.id == workflow.id }
        persist()
    }

    func rename(_ workflow: Workflow, to name: String) {
        guard let i = workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        workflows[i].name = name
        persist()
    }

    /// Returns the first workflow whose trigger phrase appears in the query.
    func match(for query: String) -> Workflow? {
        let lower = query.lowercased()
        return workflows.first { lower.contains($0.trigger.lowercased()) }
    }

    // MARK: - Persistence

    private func persist() {
        let data = (try? JSONEncoder().encode(workflows)) ?? Data()
        try? data.write(to: fileURL, options: .atomicWrite)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([Workflow].self, from: data) else { return }
        workflows = saved
    }
}
