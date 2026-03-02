import Cocoa
import ApplicationServices
import ScreenCaptureKit

final class AppDiscoveryService {
    static let shared = AppDiscoveryService()
    private init() {}

    private static let minWindowSize: CGFloat = 100

    /// Cached ScreenCaptureKit window titles (CGWindowID → title)
    /// Persists across calls — refreshed asynchronously in background.
    private var scWindowTitles: [CGWindowID: String] = [:]

    /// Icon cache — avoids re-fetching and re-sizing app icons every call.
    private var iconCache: [String: NSImage] = [:]

    // MARK: - Public

    func getRunningApps() -> [AppItem] {
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }

        // Pre-fetch CG windows grouped by PID (for cross-referencing names & IDs)
        let cgByPid = getCGWindowsByPid()

        // Kick off async SC title refresh (uses cached titles from previous call for now)
        refreshSCWindowTitlesAsync()

        // Deduplicate by bundleIdentifier — merge windows from multiple processes
        var seen: [String: Int] = [:]
        var appItems: [AppItem] = []

        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            let pid = app.processIdentifier
            let appName = app.localizedName ?? ""
            let cgEntries = cgByPid[pid] ?? []
            let windows = discoverWindows(pid: pid, appName: appName, cgEntries: cgEntries)

            if let existingIdx = seen[bundleId] {
                // Same app, different process — merge windows
                appItems[existingIdx].windows += windows
            } else {
                let icon: NSImage
                if let cached = iconCache[bundleId] {
                    icon = cached
                } else {
                    icon = app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
                    icon.size = NSSize(width: 32, height: 32)
                    iconCache[bundleId] = icon
                }

                seen[bundleId] = appItems.count
                appItems.append(AppItem(
                    id: bundleId,
                    name: app.localizedName ?? "Unknown",
                    icon: icon,
                    pid: pid,
                    bundleURL: app.bundleURL,
                    windows: windows
                ))
            }
        }

        return appItems
    }

    // MARK: - Window Discovery (AX primary, CG for cross-ref)

    private struct CGEntry {
        let windowID: CGWindowID
        let name: String
        let bounds: CGRect
    }

    private func discoverWindows(pid: pid_t, appName: String = "", cgEntries: [CGEntry]) -> [WindowItem] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let axWindows = windowsRef as? [AXUIElement] else {
            // Fallback: use CG windows directly
            return cgEntries.enumerated().map { (i, cg) in
                var w = WindowItem(id: Int(cg.windowID), name: cg.name, ownerPid: pid,
                           windowNumber: Int(cg.windowID), cgWindowID: cg.windowID)
                w.displayName = WindowItem.computeDisplayName(for: cg.name)
                return w
            }
        }

        // Track matched CG IDs to avoid two AX windows matching the same CG window
        var matchedCGIDs: Set<CGWindowID> = []
        var items: [WindowItem] = []

        for (i, axWindow) in axWindows.enumerated() {
            // Filter: role
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &roleRef)
            if let role = roleRef as? String, role != kAXWindowRole as String { continue }

            // Filter: subrole
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef)
            let subrole = subroleRef as? String ?? ""
            let validSubroles: Set<String> = [kAXStandardWindowSubrole as String, kAXDialogSubrole as String]
            if !validSubroles.contains(subrole) { continue }

            // Get AX size for min-size filter
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
            var axSize = CGSize.zero
            if let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() {
                AXValueGetValue(sv as! AXValue, .cgSize, &axSize)
            }
            if axSize.width < Self.minWindowSize || axSize.height < Self.minWindowSize { continue }

            // Check minimized state (include in list but mark it)
            var minRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minRef)
            let isMinimized = (minRef as? Bool) ?? false

            // Get AX title
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            let axTitle = (titleRef as? String) ?? ""

            // Try kAXDocument for file-based apps
            var docRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXDocumentAttribute as CFString, &docRef)
            let docPath = docRef as? String

            // Get AX position for CG matching
            var posRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
            var axPos = CGPoint.zero
            if let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID() {
                AXValueGetValue(pv as! AXValue, .cgPoint, &axPos)
            }

            // Cross-reference with CG window (pass full list; matchCGWindow skips matched IDs)
            let matched = matchCGWindow(axPos: axPos, axSize: axSize, axTitle: axTitle, cgEntries: cgEntries, excludeIDs: matchedCGIDs)
            if let m = matched { matchedCGIDs.insert(m.windowID) }

            // Build window name with smart priority
            let cgID = matched?.windowID ?? 0
            let cgName = matched?.name ?? ""
            let scName = cgID > 0 ? (scWindowTitles[cgID] ?? "") : ""
            let axTitleIsGeneric = axTitle.isEmpty || axTitle == appName

            let finalName: String
            if !axTitle.isEmpty && !axTitleIsGeneric {
                finalName = axTitle
            } else if !cgName.isEmpty {
                finalName = cgName
            } else if !scName.isEmpty {
                finalName = scName
            } else if !axTitle.isEmpty {
                finalName = axTitle
            } else if let doc = docPath, let url = URL(string: doc) {
                finalName = url.lastPathComponent
            } else {
                finalName = ""
            }

            let uniqueID = Int(cgID != 0 ? cgID : UInt32(pid) &* 1000 &+ UInt32(i))

            var win = WindowItem(
                id: uniqueID,
                name: finalName,
                ownerPid: pid,
                windowNumber: uniqueID,
                cgWindowID: cgID,
                isMinimized: isMinimized
            )
            win.displayName = WindowItem.computeDisplayName(for: finalName)
            items.append(win)
        }

        // Disambiguate same-name windows
        var nameCounts: [String: Int] = [:]
        for item in items { nameCounts[item.name, default: 0] += 1 }
        var nameCounters: [String: Int] = [:]
        for i in items.indices {
            let name = items[i].name
            if (nameCounts[name] ?? 0) > 1 {
                let idx = (nameCounters[name] ?? 0) + 1
                nameCounters[name] = idx
                items[i].name = name.isEmpty ? "Window \(idx)" : "\(name) (\(idx))"
            } else if name.isEmpty {
                items[i].name = "Window"
            }
        }

        return items
    }

    /// Match AX window to CG window by position+size proximity, skipping already-matched IDs
    private func matchCGWindow(axPos: CGPoint, axSize: CGSize, axTitle: String,
                               cgEntries: [CGEntry], excludeIDs: Set<CGWindowID> = []) -> CGEntry? {
        if !axTitle.isEmpty {
            if let m = cgEntries.first(where: { !excludeIDs.contains($0.windowID) && $0.name == axTitle }) { return m }
        }
        let tol: CGFloat = 20
        for cg in cgEntries where !excludeIDs.contains(cg.windowID) {
            if abs(cg.bounds.origin.x - axPos.x) < tol
                && abs(cg.bounds.origin.y - axPos.y) < tol
                && abs(cg.bounds.size.width - axSize.width) < tol
                && abs(cg.bounds.size.height - axSize.height) < tol {
                return cg
            }
        }
        return nil
    }

    // MARK: - ScreenCaptureKit Window Titles

    /// Minimum interval between SC refreshes to avoid expensive system queries on every overlay open
    private var lastSCRefresh: Date = .distantPast

    /// Non-blocking async refresh — uses cached titles until new ones arrive.
    /// Only calls SCShareableContent when screen recording permission is confirmed,
    /// to avoid triggering the macOS 15 system dialog during normal usage.
    private func refreshSCWindowTitlesAsync() {
        guard CGPreflightScreenCaptureAccess() else { return }
        guard Date().timeIntervalSince(lastSCRefresh) > 5.0 else { return }
        lastSCRefresh = Date()
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, _ in
            guard let windows = content?.windows else { return }
            var titles: [CGWindowID: String] = [:]
            for w in windows {
                if let title = w.title, !title.isEmpty {
                    titles[w.windowID] = title
                }
            }
            DispatchQueue.main.async {
                self?.scWindowTitles = titles
            }
        }
    }

    // MARK: - CG Window List

    private func getCGWindowsByPid() -> [pid_t: [CGEntry]] {
        var result: [pid_t: [CGEntry]] = [:]
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return result }

        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0
            else { continue }

            var bounds = CGRect.zero
            if let b = info[kCGWindowBounds as String] as? [String: Any] {
                bounds = CGRect(
                    x: (b["X"] as? NSNumber)?.doubleValue ?? 0,
                    y: (b["Y"] as? NSNumber)?.doubleValue ?? 0,
                    width: (b["Width"] as? NSNumber)?.doubleValue ?? 0,
                    height: (b["Height"] as? NSNumber)?.doubleValue ?? 0
                )
            }
            if bounds.width < Double(Self.minWindowSize) || bounds.height < Double(Self.minWindowSize) { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }

            let name = info[kCGWindowName as String] as? String ?? ""
            result[pid, default: []].append(CGEntry(windowID: wid, name: name, bounds: bounds))
        }
        return result
    }

    // MARK: - Preview Capture

    /// Track whether screen capture via CGWindowList is known to work.
    /// Avoids repeated blocking calls that trigger macOS 15 permission dialogs.
    /// Thread-safe access via serial queue.
    private let captureStateQueue = DispatchQueue(label: "com.orby.capture-state")
    private var _cgCaptureAvailable: Bool?
    private var cgCaptureAvailable: Bool? {
        get { captureStateQueue.sync { _cgCaptureAvailable } }
        set { captureStateQueue.sync { _cgCaptureAvailable = newValue } }
    }

    /// Capture window preview asynchronously on a background thread.
    /// Actually downscales the image to avoid loading full-resolution bitmaps into SwiftUI.
    func captureWindowPreviewAsync(cgWindowID: CGWindowID, maxSize: CGFloat = 320, completion: @escaping (NSImage?) -> Void) {
        guard cgWindowID > 0 else { completion(nil); return }

        // If we already know CGWindowList capture is broken (e.g. macOS 15 temporary access only), skip
        if cgCaptureAvailable == false { completion(nil); return }

        let captureCompleted = DispatchSemaphore(value: 0)
        var finished = false
        let lock = NSLock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Use .nominalResolution instead of .bestResolution to get 1x image (faster, smaller)
            let cgImage = CGWindowListCreateImage(
                .null, .optionIncludingWindow, cgWindowID,
                [.boundsIgnoreFraming, .nominalResolution]
            )

            lock.lock()
            let alreadyTimedOut = finished
            if !alreadyTimedOut { finished = true }
            lock.unlock()
            captureCompleted.signal()

            if alreadyTimedOut { return } // timed out, result discarded

            guard let cgImage = cgImage else {
                DispatchQueue.main.async {
                    self?.cgCaptureAvailable = false
                    completion(nil)
                }
                return
            }

            let pixelW = CGFloat(cgImage.width)
            let pixelH = CGFloat(cgImage.height)
            guard pixelW > 0, pixelH > 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Mark capture as working
            if self?.cgCaptureAvailable != true {
                DispatchQueue.main.async { self?.cgCaptureAvailable = true }
            }

            // Actually downscale the image to target size (not just wrapping at display size)
            let scale = min(maxSize / pixelW, maxSize / pixelH, 1.0)
            let newW = pixelW * scale
            let newH = pixelH * scale

            let resized = NSImage(size: NSSize(width: newW, height: newH))
            resized.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            NSRect(x: 0, y: 0, width: newW, height: newH).fill(using: .clear)
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH))
            resized.unlockFocus()

            DispatchQueue.main.async { completion(resized) }
        }

        // Timeout: if CGWindowListCreateImage doesn't complete in 1.5s, give up.
        // This prevents hangs from macOS 15 screen recording re-prompts.
        DispatchQueue.global(qos: .utility).async {
            let result = captureCompleted.wait(timeout: .now() + 1.5)
            if result == .timedOut {
                lock.lock()
                let alreadyDone = finished
                if !alreadyDone { finished = true }
                lock.unlock()

                if !alreadyDone {
                    DispatchQueue.main.async {
                        self.cgCaptureAvailable = false
                        completion(nil)
                    }
                }
            }
        }
    }

    // MARK: - Activate & Terminate

    func terminateApp(_ app: AppItem) {
        if let runningApp = NSRunningApplication(processIdentifier: app.pid) {
            runningApp.terminate()
        }
    }

    func activateApp(_ app: AppItem) {
        if let runningApp = NSRunningApplication(processIdentifier: app.pid) {
            // Check if app has visible windows
            if Self.appHasVisibleWindow(pid: app.pid) {
                runningApp.unhide()
                runningApp.activate()
            } else if let url = app.bundleURL {
                // No visible windows — open(url) triggers reopen/new window
                NSWorkspace.shared.open(url)
            } else {
                runningApp.activate()
            }
        }
    }

    private static func appHasVisibleWindow(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        return list.contains { info in
            guard let wPid = info[kCGWindowOwnerPID as String] as? pid_t, wPid == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let b = info[kCGWindowBounds as String] as? [String: Any],
                  let w = (b["Width"] as? NSNumber)?.doubleValue,
                  let h = (b["Height"] as? NSNumber)?.doubleValue
            else { return false }
            return w > 50 && h > 50
        }
    }

    func closeWindow(_ window: WindowItem) {
        guard let axWindow = findAXWindow(window) else { return }
        var closeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeRef)
        if let closeButton = closeRef {
            // closeButton is a CFTypeRef; AXUIElement is toll-free bridged
            AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
        }
    }

    private func findAXWindow(_ window: WindowItem) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(window.ownerPid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let axWindows = windowsRef as? [AXUIElement] else { return nil }

        // 1. Try matching by name (exact title match)
        if !window.name.isEmpty {
            for axWindow in axWindows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                if let title = titleRef as? String, title == window.name {
                    return axWindow
                }
            }
        }

        // 2. Try matching by cgWindowID via position/size cross-reference
        if window.cgWindowID > 0 {
            let cgEntries = getCGWindowsByPid()[window.ownerPid] ?? []
            if let targetCG = cgEntries.first(where: { $0.windowID == window.cgWindowID }) {
                let tol: CGFloat = 20
                for axWindow in axWindows {
                    var posRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
                    var axPos = CGPoint.zero
                    if let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID() {
                        AXValueGetValue(pv as! AXValue, .cgPoint, &axPos)
                    }
                    var sizeRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
                    var axSize = CGSize.zero
                    if let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() {
                        AXValueGetValue(sv as! AXValue, .cgSize, &axSize)
                    }
                    if abs(axPos.x - targetCG.bounds.origin.x) < tol
                        && abs(axPos.y - targetCG.bounds.origin.y) < tol
                        && abs(axSize.width - targetCG.bounds.size.width) < tol
                        && abs(axSize.height - targetCG.bounds.size.height) < tol {
                        return axWindow
                    }
                }
            }
        }

        return nil
    }

    func activateWindow(_ window: WindowItem) {
        let appElement = AXUIElementCreateApplication(window.ownerPid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let axWindows = windowsRef as? [AXUIElement] else {
            if let app = NSRunningApplication(processIdentifier: window.ownerPid) {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            return
        }

        if !window.name.isEmpty {
            for axWindow in axWindows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                if let title = titleRef as? String, title == window.name {
                    unminimizeAndRaise(axWindow, pid: window.ownerPid)
                    return
                }
            }
        }

        let idx = window.id % 1000
        if idx >= 0 && idx < axWindows.count {
            unminimizeAndRaise(axWindows[idx], pid: window.ownerPid)
        } else if let app = NSRunningApplication(processIdentifier: window.ownerPid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// Activate a specific window by its CGWindowID.
    /// Cross-references AX windows with CG window list to find and raise the exact window.
    func activateWindowByCGID(_ targetCGID: CGWindowID, pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let axWindows = windowsRef as? [AXUIElement] else {
            // Fallback: just activate the app
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            return
        }

        // Get CG windows for this pid to cross-reference
        let cgEntries = getCGWindowsByPid()[pid] ?? []

        for axWindow in axWindows {
            // Get AX position and size
            var posRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
            var axPos = CGPoint.zero
            if let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID() {
                AXValueGetValue(pv as! AXValue, .cgPoint, &axPos)
            }

            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
            var axSize = CGSize.zero
            if let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() {
                AXValueGetValue(sv as! AXValue, .cgSize, &axSize)
            }

            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            let axTitle = (titleRef as? String) ?? ""

            // Match against CG entries to find the one with targetCGID
            let matched = matchCGWindow(axPos: axPos, axSize: axSize, axTitle: axTitle, cgEntries: cgEntries)
            if matched?.windowID == targetCGID {
                unminimizeAndRaise(axWindow, pid: pid)
                return
            }
        }

        // Fallback: activate the app
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func unminimizeAndRaise(_ axWindow: AXUIElement, pid: pid_t) {
        var minRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minRef)
        if let minimized = minRef as? Bool, minimized {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
