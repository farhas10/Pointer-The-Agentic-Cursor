import Foundation

/// Tracks multi-step tool batches across an agent session for UI + panic cancel.
@MainActor
final class ActionQueueTracker: ObservableObject {
    @Published private(set) var queuedCount: Int = 0
    @Published private(set) var executedCount: Int = 0
    @Published private(set) var isActive: Bool = false

    var statusLabel: String? {
        guard isActive, queuedCount > 0 else { return nil }
        if executedCount == 0 {
            return "Action queue: \(queuedCount) pending"
        }
        return "Action queue: \(executedCount)/\(queuedCount + executedCount) done"
    }

    func beginSession() {
        queuedCount = 0
        executedCount = 0
        isActive = true
    }

    func enqueue(_ count: Int) {
        queuedCount += count
    }

    func markExecuted(_ count: Int) {
        executedCount += count
        queuedCount = max(0, queuedCount - count)
        if queuedCount == 0 { isActive = false }
    }

    func cancelAll() {
        queuedCount = 0
        isActive = false
    }

    func endSession() {
        queuedCount = 0
        executedCount = 0
        isActive = false
    }
}
