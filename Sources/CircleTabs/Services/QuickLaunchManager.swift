import Cocoa

final class QuickLaunchManager: ObservableObject {
    static let shared = QuickLaunchManager()

    struct Binding: Codable, Equatable {
        let bundleId: String
        let windowName: String?
        let displayName: String
    }

    @Published var bindings: [Int: Binding] = [:] {
        didSet { save() }
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Key codes for number keys 1–9 on standard US keyboard
    static let keyMap: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    private init() { load() }

    // MARK: - Bind / Unbind

    func bind(slot: Int, bundleId: String, windowName: String?, displayName: String) {
        // Remove old binding for the same target
        for (s, b) in bindings where b.bundleId == bundleId && b.windowName == windowName {
            bindings[s] = nil
        }
        bindings[slot] = Binding(bundleId: bundleId, windowName: windowName, displayName: displayName)
    }

    func unbind(slot: Int) {
        bindings[slot] = nil
    }

    func slot(for bundleId: String, windowName: String? = nil) -> Int? {
        for (slot, b) in bindings where b.bundleId == bundleId && b.windowName == windowName {
            return slot
        }
        return nil
    }

    func nextAvailableSlot() -> Int? {
        for i in 1...9 where bindings[i] == nil { return i }
        return nil
    }

    // MARK: - Activate

    func activate(slot: Int) {
        guard let binding = bindings[slot] else { return }
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == binding.bundleId && $0.activationPolicy == .regular
        }
        guard let app = runningApps.first else { return }

        if let windowName = binding.windowName {
            let win = WindowItem(id: 0, name: windowName, ownerPid: app.processIdentifier, windowNumber: 0)
            AppDiscoveryService.shared.activateWindow(win)
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // MARK: - Global Monitor

    func startMonitoring() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true { return nil }
            return event
        }
    }

    func stopMonitoring() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let relevantMods: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let activeMods = event.modifierFlags.intersection(relevantMods)
        guard activeMods == .option else { return false }
        guard let slot = Self.keyMap[event.keyCode] else { return false }
        guard bindings[slot] != nil else { return false }

        DispatchQueue.main.async { [weak self] in
            self?.activate(slot: slot)
        }
        return true
    }

    // MARK: - Persistence

    private func save() {
        let serializable = Dictionary(uniqueKeysWithValues: bindings.map { ("\($0.key)", $0.value) })
        if let data = try? JSONEncoder().encode(serializable) {
            UserDefaults.standard.set(data, forKey: "quickLaunchBindings")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "quickLaunchBindings"),
              let raw = try? JSONDecoder().decode([String: Binding].self, from: data)
        else { return }
        bindings = Dictionary(uniqueKeysWithValues: raw.compactMap {
            guard let slot = Int($0.key) else { return nil }
            return (slot, $0.value)
        })
    }
}
