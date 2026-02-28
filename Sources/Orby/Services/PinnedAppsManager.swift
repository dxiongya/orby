import Foundation
import Combine

struct PinnedApp: Codable, Identifiable, Equatable {
    let bundleId: String
    let name: String
    let bundlePath: String

    var id: String { bundleId }
}

final class PinnedAppsManager: ObservableObject {
    static let shared = PinnedAppsManager()

    @Published var pinnedApps: [PinnedApp] = [] {
        didSet { save() }
    }

    private init() { load() }

    // MARK: - Mutations

    func addApp(_ app: PinnedApp) {
        guard !pinnedApps.contains(where: { $0.bundleId == app.bundleId }) else { return }
        pinnedApps.append(app)
    }

    func removeApp(bundleId: String) {
        pinnedApps.removeAll { $0.bundleId == bundleId }
    }

    func reorder(from source: IndexSet, to destination: Int) {
        pinnedApps.move(fromOffsets: source, toOffset: destination)
    }

    func moveApp(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < pinnedApps.count,
              toIndex >= 0, toIndex < pinnedApps.count else { return }
        let app = pinnedApps.remove(at: fromIndex)
        pinnedApps.insert(app, at: toIndex)
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(pinnedApps) {
            UserDefaults.standard.set(data, forKey: "pinnedApps")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "pinnedApps"),
              let apps = try? JSONDecoder().decode([PinnedApp].self, from: data) else { return }
        pinnedApps = apps
    }
}
