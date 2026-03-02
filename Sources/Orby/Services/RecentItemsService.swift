import Cocoa
import Combine

final class RecentItemsService: ObservableObject {
    static let shared = RecentItemsService()

    @Published var recentItems: [RecentItem] = []

    // Real-time app activation tracking
    private struct ActivationRecord {
        let bundleURL: URL
        let name: String
        let date: Date
    }
    private var activationHistory: [ActivationRecord] = []
    private static let maxHistory = 30

    // Spotlight for recent files
    private var query: NSMetadataQuery?
    private let workQueue = DispatchQueue(label: "com.orby.recentItems", qos: .userInitiated)
    private var cachedFileItems: [RecentItem] = []
    private var lastFileQueryTime: Date = .distantPast
    private static let fileCacheInterval: TimeInterval = 60 // 1 minute for files
    private static let maxItems = 25

    private init() {
        startObservingAppActivations()
    }

    // MARK: - Real-time App Activation Tracking

    private func startObservingAppActivations() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // Seed with currently running regular apps (sorted by nothing — just populate)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let url = app.bundleURL else { continue }
            if Self.isAgentApp(at: url) { continue }
            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            activationHistory.append(ActivationRecord(bundleURL: url, name: name, date: Date()))
        }
    }

    @objc private func appDidActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular,
              let url = app.bundleURL else { return }
        if Self.isAgentApp(at: url) { return }

        let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent

        // Remove old entry for same app, push to front
        activationHistory.removeAll { $0.bundleURL == url }
        activationHistory.insert(ActivationRecord(bundleURL: url, name: name, date: Date()), at: 0)

        // Trim
        if activationHistory.count > Self.maxHistory {
            activationHistory = Array(activationHistory.prefix(Self.maxHistory))
        }
    }

    // MARK: - Fetch (called when overlay opens)

    func fetchRecentItems() {
        // Always rebuild from real-time app data + cached/fresh file data
        let needFileRefresh = Date().timeIntervalSince(lastFileQueryTime) > Self.fileCacheInterval
            || cachedFileItems.isEmpty

        if needFileRefresh {
            queryRecentFiles()
        } else {
            rebuildList()
        }
    }

    private func rebuildList() {
        workQueue.async { [weak self] in
            guard let self else { return }
            let merged = self.buildMergedList()
            DispatchQueue.main.async {
                self.recentItems = merged
            }
        }
    }

    private func buildMergedList() -> [RecentItem] {
        // 1) Apps from real-time activation history (most recent first, skip self)
        let selfBundleId = Bundle.main.bundleIdentifier ?? ""
        var items: [RecentItem] = []
        var seenPaths = Set<String>()

        for record in activationHistory {
            let path = record.bundleURL.path
            if seenPaths.contains(path) { continue }
            // Skip self
            if let b = Bundle(url: record.bundleURL), b.bundleIdentifier == selfBundleId { continue }

            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 36, height: 36)

            items.append(RecentItem(
                id: path,
                name: record.name,
                icon: icon,
                url: record.bundleURL,
                lastUsedDate: record.date,
                kind: .application
            ))
            seenPaths.insert(path)
        }

        // 2) Files from Spotlight cache
        for fileItem in cachedFileItems {
            if seenPaths.contains(fileItem.id) { continue }
            items.append(fileItem)
            seenPaths.insert(fileItem.id)
            if items.count >= Self.maxItems { break }
        }

        // Already sorted: apps by activation time, files by lastUsedDate
        // Trim to max
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        return items
    }

    // MARK: - Spotlight Query for Files

    private func queryRecentFiles() {
        stopQuery()

        let mdQuery = NSMetadataQuery()
        mdQuery.searchScopes = [NSMetadataQueryLocalComputerScope]

        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        mdQuery.predicate = NSPredicate(
            format: "kMDItemLastUsedDate >= %@ AND kMDItemContentType != 'com.apple.application-bundle'",
            sevenDaysAgo as NSDate
        )
        mdQuery.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fileQueryDidFinish(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: mdQuery
        )

        self.query = mdQuery
        DispatchQueue.main.async { mdQuery.start() }
    }

    @objc private func fileQueryDidFinish(_ notification: Notification) {
        guard let mdQuery = notification.object as? NSMetadataQuery else { return }
        mdQuery.stop()

        NotificationCenter.default.removeObserver(
            self,
            name: .NSMetadataQueryDidFinishGathering,
            object: mdQuery
        )

        let results = mdQuery.results as? [NSMetadataItem] ?? []

        workQueue.async { [weak self] in
            guard let self else { return }
            self.cachedFileItems = self.processFileResults(results)
            self.lastFileQueryTime = Date()
            let merged = self.buildMergedList()
            DispatchQueue.main.async {
                self.recentItems = merged
                self.query = nil
            }
        }
    }

    private func processFileResults(_ results: [NSMetadataItem]) -> [RecentItem] {
        let hiddenPrefixes = ["/Library/", "/System/", "/usr/", "/bin/", "/sbin/", "/private/"]

        var items: [RecentItem] = []
        for result in results {
            guard items.count < Self.maxItems else { break }

            guard let path = result.value(forAttribute: kMDItemPath as String) as? String,
                  let lastUsed = result.value(forAttribute: kMDItemLastUsedDate as String) as? Date
            else { continue }

            let url = URL(fileURLWithPath: path)
            if url.lastPathComponent.hasPrefix(".") { continue }
            if hiddenPrefixes.contains(where: { path.hasPrefix($0) }) { continue }
            // Skip .app bundles (handled by activation tracking)
            if path.hasSuffix(".app") { continue }

            let name = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 36, height: 36)

            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            let kind: RecentItemKind = isDir.boolValue ? .folder : .file

            items.append(RecentItem(
                id: path,
                name: name,
                icon: icon,
                url: url,
                lastUsedDate: lastUsed,
                kind: kind
            ))
        }
        return items
    }

    // MARK: - Helpers

    private static func isAgentApp(at bundleURL: URL) -> Bool {
        guard let bundle = Bundle(url: bundleURL),
              let info = bundle.infoDictionary else { return false }
        if info["LSUIElement"] as? Bool == true { return true }
        if info["LSUIElement"] as? String == "1" { return true }
        if info["LSBackgroundOnly"] as? Bool == true { return true }
        if info["LSBackgroundOnly"] as? String == "1" { return true }
        return false
    }

    private func stopQuery() {
        query?.stop()
        if let q = query {
            NotificationCenter.default.removeObserver(
                self,
                name: .NSMetadataQueryDidFinishGathering,
                object: q
            )
        }
        query = nil
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopQuery()
    }
}
