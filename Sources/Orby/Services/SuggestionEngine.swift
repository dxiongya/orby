import Cocoa

final class SuggestionEngine {
    static let shared = SuggestionEngine()

    private var cachedApps: [AppItem] = []
    private var cacheTimestamp: Date?
    private static let cacheDuration: TimeInterval = 30 * 60  // 30 minutes

    private init() {}

    // MARK: - Public API

    /// Returns suggested apps (up to 10, at least 6 guaranteed by caller). Uses 30-minute cache; only refreshes isRunning status within cache window.
    func getSuggestedApps() -> [AppItem] {
        if let ts = cacheTimestamp, Date().timeIntervalSince(ts) < Self.cacheDuration, !cachedApps.isEmpty {
            // Within cache window — only refresh isRunning status
            refreshRunningStatus()
            return cachedApps
        }
        // Recompute suggestions
        let suggestions = computeSuggestions()
        cachedApps = suggestions
        cacheTimestamp = Date()
        return suggestions
    }

    /// Force invalidate cache (e.g. when switching modes)
    func invalidateCache() {
        cachedApps = []
        cacheTimestamp = nil
    }

    // MARK: - Scoring Algorithm

    private func computeSuggestions() -> [AppItem] {
        let recordsByApp = UsageTracker.shared.recordsByApp()

        // Cold start: no data → fallback to running apps
        if recordsByApp.isEmpty {
            return []
        }

        let now = Date()
        let currentSlot = TimeSlot.current()
        let adjacentSlots = currentSlot.adjacentSlots()
        let cal = Calendar.current
        let currentDayOfWeek = cal.component(.weekday, from: now)
        let currentIsWeekday = (currentDayOfWeek >= 2 && currentDayOfWeek <= 6)
        let currentLocation = LocationContextProvider.shared.locationEnabled
            ? LocationContextProvider.shared.currentLocationLabel
            : nil

        // Score each app
        var appScores: [(bundleId: String, score: Double)] = []
        for (bundleId, records) in recordsByApp {
            var totalScore: Double = 0
            for record in records {
                let timeSlotWeight: Double
                if record.timeSlot == currentSlot {
                    timeSlotWeight = 3.0
                } else if adjacentSlots.contains(record.timeSlot) {
                    timeSlotWeight = 1.5
                } else {
                    timeSlotWeight = 1.0
                }

                let dayTypeWeight: Double = (record.isWeekday == currentIsWeekday) ? 1.5 : 1.0
                let sameDayWeight: Double = (record.dayOfWeek == currentDayOfWeek) ? 1.3 : 1.0

                let locationWeight: Double
                if let loc = currentLocation, let recLoc = record.locationLabel, loc == recLoc {
                    locationWeight = 2.0
                } else {
                    locationWeight = 1.0
                }

                let daysSince = cal.dateComponents([.day], from: record.timestamp, to: now).day ?? 0
                let recencyWeight: Double
                switch daysSince {
                case 0...3:   recencyWeight = 4.0
                case 4...7:   recencyWeight = 3.0
                case 8...14:  recencyWeight = 2.0
                case 15...21: recencyWeight = 1.5
                default:      recencyWeight = 1.0
                }

                totalScore += timeSlotWeight * dayTypeWeight * sameDayWeight * locationWeight * recencyWeight
            }
            appScores.append((bundleId, totalScore))
        }

        // Sort by score descending, take top 10
        appScores.sort { $0.score > $1.score }
        let topBundleIds = appScores.prefix(10).map { $0.bundleId }

        // Build AppItem list
        let runningApps = AppDiscoveryService.shared.getRunningApps()
        let runningByBundleId = Dictionary(runningApps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let installedApps = scanInstalledApps()

        var result: [AppItem] = []
        for bundleId in topBundleIds {
            if let running = runningByBundleId[bundleId] {
                // App is running — use full data
                result.append(running)
            } else if let installed = installedApps[bundleId] {
                // App is installed but not running — create stub
                result.append(installed)
            }
            // If app is neither running nor installed, skip it
        }
        return result
    }

    // MARK: - Running Status Refresh

    private func refreshRunningStatus() {
        let runningApps = AppDiscoveryService.shared.getRunningApps()
        let runningByBundleId = Dictionary(runningApps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for i in cachedApps.indices {
            if let running = runningByBundleId[cachedApps[i].id] {
                cachedApps[i].isRunning = true
                cachedApps[i].windows = running.windows
            } else {
                cachedApps[i].isRunning = false
                cachedApps[i].windows = []
            }
        }
    }

    // MARK: - App Scanning

    /// Scan /Applications and ~/Applications for installed apps, returns dict by bundleId
    private func scanInstalledApps() -> [String: AppItem] {
        var result: [String: AppItem] = [:]
        let fm = FileManager.default
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for dir in dirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleId = bundle.bundleIdentifier else { continue }
                if result[bundleId] != nil { continue }

                let name = bundle.infoDictionary?["CFBundleName"] as? String
                    ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)

                var app = AppItem(
                    id: bundleId,
                    name: name,
                    icon: icon,
                    pid: 0,
                    bundleURL: url,
                    windows: []
                )
                app.isRunning = false
                result[bundleId] = app
            }
        }
        return result
    }
}
