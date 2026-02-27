import Foundation
import Combine

final class SubAppOrderManager: ObservableObject {
    static let shared = SubAppOrderManager()

    /// Key: app bundle ID, Value: ordered list of window names
    @Published private(set) var orderMap: [String: [String]] = [:] {
        didSet { save() }
    }

    private init() { load() }

    // MARK: - Apply & Save

    /// Reorder windows according to saved order. Unknown/new windows are appended at the end.
    func applyOrder(bundleId: String, windows: [WindowItem]) -> [WindowItem] {
        guard let savedOrder = orderMap[bundleId], !savedOrder.isEmpty else {
            return windows
        }

        var ordered: [WindowItem] = []
        var remaining = windows

        for name in savedOrder {
            if let idx = remaining.firstIndex(where: { $0.name == name }) {
                ordered.append(remaining.remove(at: idx))
            }
        }

        // New/unknown windows go at the end
        ordered.append(contentsOf: remaining)
        return ordered
    }

    /// Persist the current window order for an app
    func saveOrder(bundleId: String, windows: [WindowItem]) {
        orderMap[bundleId] = windows.map { $0.name }
    }

    /// Clear saved order (revert to OS default)
    func clearOrder(bundleId: String) {
        orderMap[bundleId] = nil
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(orderMap) {
            UserDefaults.standard.set(data, forKey: "subAppOrder")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "subAppOrder"),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        orderMap = map
    }
}
