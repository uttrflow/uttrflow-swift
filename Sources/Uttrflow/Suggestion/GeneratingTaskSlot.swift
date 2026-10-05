import Foundation

/// Keeps cancellation and completion attached to the turn that owns the generated task.
struct GeneratingTaskSlot {
    private(set) var turn: Int?
    private var task: Task<[String], any Error>?

    mutating func store(_ task: Task<[String], any Error>, for turn: Int) {
        self.task = task
        self.turn = turn
    }

    mutating func finish(turn: Int) {
        guard self.turn == turn else { return }
        task = nil
        self.turn = nil
    }

    func cancel() {
        task?.cancel()
    }
}
