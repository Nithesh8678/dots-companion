import XCTest
@testable import DotsCore

final class TaskCoordinatorTests: XCTestCase {
    func testRetryReturnsSameIdentityAndDoesNotCreateNewTask() throws {
        var tasks = TaskCoordinator()
        let session = SessionID()
        let first = try tasks.create(sessionID: session, title: "Open test editor", idempotencyKey: "open-test")
        let retry = try tasks.create(sessionID: session, title: "retry", idempotencyKey: "open-test")
        XCTAssertEqual(first.id, retry.id)
        XCTAssertEqual(tasks.records.count, 1)
    }
    func testCompletionRequiresObservedPostconditionAndResult() throws {
        var tasks = TaskCoordinator()
        let task = try tasks.create(sessionID: SessionID(), title: "Launch", idempotencyKey: "launch")
        XCTAssertEqual(tasks.update(task.id, generation: 0, state: .completed, result: "Dispatched"), .unverifiedResult)
        XCTAssertEqual(tasks.update(task.id, generation: 0, state: .completed, postconditionVerified: true), .unverifiedResult)
        XCTAssertEqual(tasks.update(task.id, generation: 0, state: .completed, result: "Observed running application", postconditionVerified: true), .applied)
        XCTAssertEqual(tasks.update(task.id, generation: 0, state: .running), .invalidTransition)
    }
    func testEndingVoiceDoesNotStopTask() throws {
        var machine = SessionStateMachine(capabilities: [.voiceEvents])
        let session = machine.beginSession()
        var tasks = TaskCoordinator()
        let task = try tasks.create(sessionID: session, title: "Task", idempotencyKey: "task")
        _ = machine.cancel()
        XCTAssertEqual(tasks.update(task.id, generation: 0, state: .running), .applied)
        XCTAssertEqual(tasks.task(task.id)?.state, .running)
    }
    func testStopTracksRealChildrenAndRejectsOldCompletion() throws {
        var tasks = TaskCoordinator()
        let session = SessionID()
        let parent = try tasks.create(sessionID: session, title: "Parent", idempotencyKey: "p")
        let child = try tasks.create(sessionID: session, title: "Child", idempotencyKey: "c", parentID: parent.id)
        let other = try tasks.create(sessionID: SessionID(), title: "Other session", idempotencyKey: "o")
        let tickets = tasks.requestStop(parent.id)
        XCTAssertEqual(Set(tickets.map(\.taskID)), [parent.id, child.id])
        XCTAssertEqual(tasks.task(parent.id)?.state, .stopping)
        XCTAssertEqual(tasks.task(child.id)?.state, .stopping)
        XCTAssertEqual(tasks.task(other.id)?.state, .requested)
        XCTAssertEqual(tasks.update(child.id, generation: 0, state: .completed, result: "Late", postconditionVerified: true), .staleGeneration)
        XCTAssertEqual(tasks.update(child.id, generation: 1, state: .running), .invalidTransition)
        XCTAssertEqual(tasks.update(child.id, generation: 1, state: .cancelled), .applied)
        XCTAssertEqual(tasks.task(parent.id)?.state, .stopping)
        XCTAssertTrue(tasks.requestStop(parent.id).isEmpty)
    }
    func testTaskCapacityDoesNotForgetEarlierRetryIdentity() throws {
        var tasks = TaskCoordinator(capacity: 1)
        let session = SessionID()
        let first = try tasks.create(sessionID: session, title: "First", idempotencyKey: "first")
        XCTAssertThrowsError(try tasks.create(sessionID: session, title: "Second", idempotencyKey: "second"))
        XCTAssertEqual(try tasks.create(sessionID: session, title: "First again", idempotencyKey: "first").id, first.id)
    }
    func testTaskRestoreMarksInterruptedWorkUnverifiedAndPreservesIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.json")
        var original = TaskCoordinator()
        let task = try original.create(sessionID: SessionID(), title: "Observed task", idempotencyKey: "task")
        _ = original.update(task.id, generation: 0, state: .running)
        try original.save(to: url)
        var restored = TaskCoordinator()
        try restored.restore(from: url)
        XCTAssertEqual(restored.records.first?.id, task.id)
        XCTAssertEqual(restored.records.first?.state, .unverified)
        XCTAssertEqual(restored.records.first?.generation, 1)
    }
}

final class MemoryStoreTests: XCTestCase {
    func testMemoryRoundTripEditAndRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("memory.json")
        var memory = MemoryStore()
        let id = UUID()
        try memory.upsert(.init(id: id, title: "Language", content: "Prefer concise Tamil explanations"))
        try memory.save(to: url)
        var loaded = MemoryStore()
        try loaded.load(from: url)
        XCTAssertEqual(loaded.entries, memory.entries)
        try loaded.upsert(.init(id: id, title: "Language", content: "Prefer concise English explanations"))
        XCTAssertEqual(loaded.entries.count, 1)
        loaded.remove(id)
        try loaded.save(to: url)
        try memory.load(from: url)
        XCTAssertTrue(memory.entries.isEmpty)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testCapacityAllowsEditButDoesNotSilentlyDeleteMemory() throws {
        var memory = MemoryStore(capacity: 1)
        let id = UUID()
        try memory.upsert(.init(id: id, title: "First", content: "Keep"))
        XCTAssertThrowsError(try memory.upsert(.init(title: "Second", content: "Do not evict first")))
        try memory.upsert(.init(id: id, title: "First", content: "Edited"))
        XCTAssertEqual(memory.entries.first?.content, "Edited")
    }
    func testInvalidArchiveDoesNotOverwriteExistingMemory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"version\":999,\"entries\":[]}".utf8).write(to: url)
        var memory = MemoryStore()
        try memory.upsert(.init(title: "Keep", content: "Original"))
        XCTAssertThrowsError(try memory.load(from: url))
        XCTAssertEqual(memory.entries.first?.content, "Original")
    }
    func testOversizedInputIsRejectedBeforeDecoding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 32, count: 3_000_001).write(to: url)
        var memory = MemoryStore()
        XCTAssertThrowsError(try memory.load(from: url)) { error in
            XCTAssertEqual(error as? PersistenceError, .archiveTooLarge)
        }
    }
}
