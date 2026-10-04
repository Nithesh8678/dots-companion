import Foundation

public struct MemoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let content: String
    public let updatedAt: Date
    public init(id: UUID = UUID(), title: String, content: String, updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.content = content; self.updatedAt = updatedAt
    }
}
public enum MemoryStoreError: Error, Equatable { case capacityReached, entryTooLarge, emptyContent }
public enum PersistenceError: Error, Equatable { case archiveTooLarge, invalidArchive }

/// Explicit, inspectable local notes. This store has no synchronization with a user's OpenAI dot.
/// The owner calls upsert only for an explicit remember/edit instruction, never for passive context.
public struct MemoryStore: Sendable {
    public private(set) var entries: [MemoryEntry] = []
    public let capacity: Int
    public init(capacity: Int = 128) { self.capacity = max(1, capacity) }
    public mutating func upsert(_ entry: MemoryEntry) throws {
        guard !entry.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MemoryStoreError.emptyContent }
        guard entry.title.count <= 160, entry.content.count <= 4_096 else { throw MemoryStoreError.entryTooLarge }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry }
        else {
            guard entries.count < capacity else { throw MemoryStoreError.capacityReached }
            entries.append(entry)
        }
    }
    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func removeAll() { entries.removeAll() }
    public func save(to url: URL) throws {
        try BoundedPersistence.write(JSONEncoder().encode(MemoryArchive(version: 1, entries: entries)), to: url)
    }
    public mutating func load(from url: URL) throws {
        let data = try BoundedPersistence.read(url, maximumBytes: 3_000_000)
        let archive = try JSONDecoder().decode(MemoryArchive.self, from: data)
        guard archive.version == 1, archive.entries.count <= capacity,
              Set(archive.entries.map(\.id)).count == archive.entries.count else { throw PersistenceError.invalidArchive }
        var validated = MemoryStore(capacity: capacity)
        for entry in archive.entries { try validated.upsert(entry) }
        entries = validated.entries
    }
}
private struct MemoryArchive: Codable { let version: Int; let entries: [MemoryEntry] }

enum BoundedPersistence {
    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw PersistenceError.archiveTooLarge }
        return data
    }
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
