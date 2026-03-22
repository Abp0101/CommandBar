import Foundation

// MARK: - ActionStep

struct ActionStep: Identifiable, Equatable {
    let id: UUID
    let description: String
    var status: Status

    enum Status: Equatable {
        case pending, running, done, failed(String)

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending), (.running, .running), (.done, .done): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    init(description: String, status: Status = .pending) {
        self.id = UUID()
        self.description = description
        self.status = status
    }

    static func == (lhs: ActionStep, rhs: ActionStep) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }
}
