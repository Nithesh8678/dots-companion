import Foundation
import Darwin

enum DiagnosticMetric: String, Codable, CaseIterable {
    case summonToVisible, capture, dictationFinalization, action, cancellation, firstResponse, networkRoundTrip
}
enum DiagnosticCounter: String, Codable, CaseIterable {
    case summons, cancellationRequests, staleEventsRejected, actionsRefused, permissionDenials, networkErrors
}
struct TimingSummary: Codable {
    let count: Int
    let minimumMilliseconds: Double
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
}
struct DiagnosticsSnapshot: Codable {
    let capturedAt: Date
    let operatingSystem: String
    let hardwareModel: String
    let processorCount: Int
    let physicalMemoryBytes: UInt64
    let timings: [String: TimingSummary]
    let counters: [String: UInt64]
}

/// In-memory numeric diagnostics only: no prompts, transcripts, paths, window titles, audio,
/// screenshots, tokens or user identifiers. Nothing is uploaded or persisted automatically.
@MainActor
final class Diagnostics {
    private struct Pending { let metric: DiagnosticMetric; let started: UInt64 }
    private var pending: [UUID: Pending] = [:]
    private var samples: [DiagnosticMetric: [Double]] = [:]
    private var counters: [DiagnosticCounter: UInt64] = [:]
    private let sampleLimit: Int
    init(sampleLimit: Int = 500) { self.sampleLimit = min(max(sampleLimit, 10), 10_000) }

    @discardableResult func begin(_ metric: DiagnosticMetric) -> UUID {
        let id = UUID()
        // An abandoned measurement cannot grow memory without bound.
        if pending.count >= 128, let oldest = pending.min(by: { $0.value.started < $1.value.started })?.key {
            pending.removeValue(forKey: oldest)
        }
        pending[id] = Pending(metric: metric, started: DispatchTime.now().uptimeNanoseconds)
        return id
    }

    @discardableResult func end(_ id: UUID) -> Double? {
        guard let measurement = pending.removeValue(forKey: id) else { return nil }
        let elapsed = DispatchTime.now().uptimeNanoseconds - measurement.started
        let milliseconds = Double(elapsed) / 1_000_000
        recordDuration(name: measurement.metric, milliseconds: milliseconds)
        return milliseconds
    }

    func abandon(_ id: UUID) { pending.removeValue(forKey: id) }

    func recordDuration(name: DiagnosticMetric, milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        var retained = samples[name, default: []]
        retained.append(milliseconds)
        if retained.count > sampleLimit { retained.removeFirst(retained.count - sampleLimit) }
        samples[name] = retained
    }

    func increment(_ counter: DiagnosticCounter) { counters[counter, default: 0] &+= 1 }

    func snapshot() -> DiagnosticsSnapshot {
        var summaries: [String: TimingSummary] = [:]
        for (metric, values) in samples {
            guard !values.isEmpty else { continue }
            let sorted = values.sorted()
            summaries[metric.rawValue] = TimingSummary(count: sorted.count, minimumMilliseconds: sorted[0],
                                                       p50Milliseconds: Self.percentile(0.50, sorted: sorted),
                                                       p95Milliseconds: Self.percentile(0.95, sorted: sorted),
                                                       maximumMilliseconds: sorted[sorted.count - 1])
        }
        return DiagnosticsSnapshot(capturedAt: Date(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                                   hardwareModel: Self.hardwareModel(), processorCount: ProcessInfo.processInfo.processorCount,
                                   physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                                   timings: summaries, counters: Dictionary(uniqueKeysWithValues: counters.map { ($0.key.rawValue, $0.value) }))
    }

    func reset() { samples.removeAll(); counters.removeAll(); pending.removeAll() }

    /// Nearest-rank percentiles; a warm animation timing is not an assistant response measurement.
    private static func percentile(_ percentile: Double, sorted: [Double]) -> Double {
        sorted[min(sorted.count - 1, max(0, Int(ceil(percentile * Double(sorted.count))) - 1))]
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size < 256 else { return "Unknown Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Unknown Mac" }
        return String(cString: buffer)
    }
}
