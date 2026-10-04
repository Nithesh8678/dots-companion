import Foundation

public enum TaskState: String, Codable, Sendable, CaseIterable {
    case requested, dispatched, running, waiting, stopping, completed, failed, cancelled, unverified
    public var isTerminal: Bool { [.completed, .failed, .cancelled, .unverified].contains(self) }
}
public struct TaskRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: TaskID
    public let sessionID: SessionID
    public let parentID: TaskID?
    public let idempotencyKey: String
    public let title: String
    public let createdAt: Date
    public fileprivate(set) var state: TaskState
    public fileprivate(set) var generation: UInt64
    public fileprivate(set) var progress: String
    public fileprivate(set) var result: String?
    public fileprivate(set) var updatedAt: Date
}
public struct TaskCancellation: Equatable, Sendable {
    public let taskID: TaskID
    public let generation: UInt64
}
public enum TaskCoordinatorError: Error, Equatable { case capacityReached, invalidKey, unknownParent }
public enum TaskUpdateResult: Equatable, Sendable { case applied, unknownTask, staleGeneration, invalidTransition, unverifiedResult }

/// Contains local, observed tasks only. It cannot infer the existence or cancellation of host tasks.
public struct TaskCoordinator: Sendable {
    public private(set) var records: [TaskRecord] = []
    public let capacity: Int
    public init(capacity: Int = 128) { self.capacity = max(1, capacity) }

    @discardableResult public mutating func create(sessionID: SessionID, title: String,
                                                   idempotencyKey: String, parentID: TaskID? = nil,
                                                   now: Date = Date()) throws -> TaskRecord {
        guard !idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              idempotencyKey.utf8.count <= 256 else { throw TaskCoordinatorError.invalidKey }
        if let existing = records.first(where: { $0.sessionID == sessionID && $0.idempotencyKey == idempotencyKey }) { return existing }
        guard records.count < capacity else { throw TaskCoordinatorError.capacityReached }
        if let parentID, !records.contains(where: { $0.id == parentID && $0.sessionID == sessionID }) {
            throw TaskCoordinatorError.unknownParent
        }
        let record = TaskRecord(id: TaskID(), sessionID: sessionID, parentID: parentID,
                                idempotencyKey: idempotencyKey, title: String(title.prefix(200)), createdAt: now,
                                state: .requested, generation: 0, progress: "Requested", result: nil, updatedAt: now)
        records.append(record); return record
    }

    public func task(_ id: TaskID) -> TaskRecord? { records.first { $0.id == id } }

    @discardableResult public mutating func update(_ id: TaskID, generation: UInt64, state: TaskState,
                                                   progress: String = "", result: String? = nil,
                                                   postconditionVerified: Bool = false,
                                                   now: Date = Date()) -> TaskUpdateResult {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return .unknownTask }
        guard records[index].generation == generation else { return .staleGeneration }
        let previous = records[index].state
        guard !previous.isTerminal, state != .requested, state != .stopping else { return .invalidTransition }
        if previous == .stopping && state != .cancelled && state != .failed { return .invalidTransition }
        if state == .cancelled && previous != .stopping { return .invalidTransition }
        if state == .completed && (!postconditionVerified || result?.isEmpty != false) { return .unverifiedResult }
        records[index].state = state
        records[index].progress = String(progress.prefix(1_024))
        records[index].result = result.map { String($0.prefix(8_192)) }
        records[index].updatedAt = now
        return .applied
    }

    @discardableResult public mutating func requestStop(_ id: TaskID, includeChildren: Bool = true,
                                                       now: Date = Date()) -> [TaskCancellation] {
        guard records.contains(where: { $0.id == id }) else { return [] }
        var targets: Set<TaskID> = [id]
        if includeChildren {
            var changed = true
            while changed {
                let before = targets.count
                for record in records where record.parentID.map(targets.contains) ?? false { targets.insert(record.id) }
                changed = before != targets.count
            }
        }
        var tickets: [TaskCancellation] = []
        for index in records.indices where targets.contains(records[index].id) {
            guard !records[index].state.isTerminal, records[index].state != .stopping else { continue }
            records[index].generation &+= 1; records[index].state = .stopping
            records[index].progress = "Stopping…"; records[index].updatedAt = now
            tickets.append(TaskCancellation(taskID: records[index].id, generation: records[index].generation))
        }
        return tickets
    }

    public mutating func requestStop(sessionID: SessionID, now: Date = Date()) -> [TaskCancellation] {
        let ids = records.filter { $0.sessionID == sessionID }.map(\.id)
        return ids.flatMap { requestStop($0, now: now) }
    }

    /// On process restart, persisted in-flight work is unverified until an adapter reconciles it.
    public mutating func restore(from url: URL) throws {
        let data = try BoundedPersistence.read(url, maximumBytes: 2_000_000)
        let saved = try JSONDecoder().decode(TaskArchive.self, from: data)
        guard saved.version == 1, saved.records.count <= capacity,
              Set(saved.records.map(\.id)).count == saved.records.count,
              Set(saved.records.map { "\($0.sessionID):\($0.idempotencyKey)" }).count == saved.records.count,
              saved.records.allSatisfy({ $0.title.count <= 200 && $0.progress.count <= 1_024 && ($0.result?.count ?? 0) <= 8_192 }) else {
            throw PersistenceError.invalidArchive
        }
        records = saved.records.map { record in
            var restored = record
            if !restored.state.isTerminal {
                restored.state = .unverified; restored.progress = "Interrupted by app restart; result not verified"
                restored.generation &+= 1
            }
            return restored
        }
    }

    public func save(to url: URL) throws {
        try BoundedPersistence.write(JSONEncoder().encode(TaskArchive(version: 1, records: records)), to: url)
    }
}
private struct TaskArchive: Codable { let version: Int; let records: [TaskRecord] }
