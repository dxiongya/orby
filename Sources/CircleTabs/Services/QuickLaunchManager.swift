import Cocoa

final class QuickLaunchManager: ObservableObject {
    static let shared = QuickLaunchManager()

    struct Binding: Codable, Equatable {
        let bundleId: String
        let cgWindowID: UInt32?      // nil = app-level, non-nil = specific window
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

    func bind(slot: Int, bundleId: String, cgWindowID: CGWindowID? = nil, displayName: String) {
        // Remove old binding for the same target
        for (s, b) in bindings where b.bundleId == bundleId && b.cgWindowID == cgWindowID {
            bindings[s] = nil
        }
        bindings[slot] = Binding(
            bundleId: bundleId,
            cgWindowID: cgWindowID.map { UInt32($0) },
            displayName: displayName
        )
    }

    func unbind(slot: Int) {
        bindings[slot] = nil
    }

    /// Find the slot bound to a specific app or window.
    func slot(for bundleId: String, cgWindowID: CGWindowID? = nil) -> Int? {
        if let wid = cgWindowID {
            // Exact window match
            for (slot, b) in bindings where b.bundleId == bundleId && b.cgWindowID == UInt32(wid) {
                return slot
            }
        }
        // App-level match
        for (slot, b) in bindings where b.bundleId == bundleId && b.cgWindowID == nil {
            return slot
        }
        return nil
    }

    // MARK: - Activate

    func activate(slot: Int) {
        guard let binding = bindings[slot] else { return }
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == binding.bundleId && $0.activationPolicy == .regular
        }
        guard let app = runningApps.first else { return }

        if let wid = binding.cgWindowID {
            // Activate specific window by cgWindowID
            AppDiscoveryService.shared.activateWindowByCGID(
                CGWindowID(wid), pid: app.processIdentifier
            )
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
            UserDefaults.standard.set(data, forKey: "quickLaunchBindings2") // new key for new format
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "quickLaunchBindings2"),
              let raw = try? JSONDecoder().decode([String: Binding].self, from: data)
        else { return }
        bindings = Dictionary(uniqueKeysWithValues: raw.compactMap {
            guard let slot = Int($0.key) else { return nil }
            return (slot, $0.value)
        })
    }
}
