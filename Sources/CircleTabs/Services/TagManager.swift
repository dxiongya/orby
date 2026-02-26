import Foundation
import Combine

final class TagManager: ObservableObject {
    static let shared = TagManager()

    @Published var presetTags: [AppTag] = [] {
        didSet { save() }
    }

    /// Key: bundleId for apps, "bundleId::windowName" for windows
    @Published var assignments: [String: Set<UUID>] = [:] {
        didSet { save() }
    }

    private init() { load() }

    // MARK: - Keys

    static func key(for bundleId: String) -> String { bundleId }
    static func key(for bundleId: String, windowName: String) -> String { "\(bundleId)::\(windowName)" }

    // MARK: - Query

    func tags(for key: String) -> [AppTag] {
        guard let ids = assignments[key] else { return [] }
        return presetTags.filter { ids.contains($0.id) }
    }

    // MARK: - Mutate

    func toggleTag(_ tag: AppTag, for key: String) {
        if assignments[key]?.contains(tag.id) == true {
            assignments[key]?.remove(tag.id)
            if assignments[key]?.isEmpty == true { assignments[key] = nil }
        } else {
            assignments[key, default: []].insert(tag.id)
        }
    }

    func clearTags(for key: String) {
        assignments[key] = nil
    }

    func addPresetTag(_ tag: AppTag) {
        presetTags.append(tag)
    }

    func removePresetTag(_ tag: AppTag) {
        presetTags.removeAll { $0.id == tag.id }
        for key in assignments.keys {
            assignments[key]?.remove(tag.id)
            if assignments[key]?.isEmpty == true { assignments[key] = nil }
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(presetTags) {
            UserDefaults.standard.set(data, forKey: "tagPresets")
        }
        let serializable = assignments.mapValues { Array($0.map { $0.uuidString }) }
        if let data = try? JSONEncoder().encode(serializable) {
            UserDefaults.standard.set(data, forKey: "tagAssignments")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "tagPresets"),
           let tags = try? JSONDecoder().decode([AppTag].self, from: data) {
            presetTags = tags
        } else {
            presetTags = [
                AppTag(name: "Work", colorName: "blue"),
                AppTag(name: "Personal", colorName: "green"),
                AppTag(name: "Dev", colorName: "purple"),
                AppTag(name: "Design", colorName: "orange"),
                AppTag(name: "Chat", colorName: "pink"),
            ]
        }

        if let data = UserDefaults.standard.data(forKey: "tagAssignments"),
           let raw = try? JSONDecoder().decode([String: [String]].self, from: data) {
            assignments = raw.mapValues { Set($0.compactMap { UUID(uuidString: $0) }) }
        }
    }
}
