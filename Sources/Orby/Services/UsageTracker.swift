import Foundation

final class UsageTracker {
    static let shared = UsageTracker()

    private var records: [UsageRecord] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.orby.usagetracker", qos: .utility)
    private static let maxAgeDays = 30

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let orbyDir = appSupport.appendingPathComponent("Orby")
        try? FileManager.default.createDirectory(at: orbyDir, withIntermediateDirectories: true)
        fileURL = orbyDir.appendingPathComponent("usage_records.json")
        loadSync()
        purgeOldRecords()
    }

    // MARK: - Public API

    /// Record an app activation event
    func recordActivation(bundleId: String) {
        let locationLabel = LocationContextProvider.shared.locationEnabled
            ? LocationContextProvider.shared.currentLocationLabel
            : nil
        let record = UsageRecord(bundleId: bundleId, locationLabel: locationLabel)
        queue.async { [weak self] in
            self?.records.append(record)
            self?.saveAsync()
        }
    }

    /// Returns all records grouped by bundleId
    func recordsByApp() -> [String: [UsageRecord]] {
        return Dictionary(grouping: records, by: { $0.bundleId })
    }

    /// Returns true if there are any usage records
    var hasData: Bool { !records.isEmpty }

    /// Clear all usage history
    func clearAllData() {
        queue.async { [weak self] in
            self?.records.removeAll()
            self?.saveAsync()
        }
        records.removeAll()
    }

    // MARK: - Persistence

    private func loadSync() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([UsageRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func saveAsync() {
        let snapshot = records
        let url = fileURL
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Silent fail — usage tracking is non-critical
        }
    }

    private func purgeOldRecords() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.maxAgeDays, to: Date()) ?? Date()
        let before = records.count
        records.removeAll { $0.timestamp < cutoff }
        if records.count != before {
            queue.async { [weak self] in self?.saveAsync() }
        }
    }
}
