import Cocoa
import ApplicationServices
import ScreenCaptureKit

final class AppDiscoveryService {
    static let shared = AppDiscoveryService()
    private init() {}

    private static let minWindowSize: CGFloat = 100

    /// Cached ScreenCaptureKit window titles (CGWindowID → title)
    /// Refreshed each time getRunningApps() is called.
    private var scWindowTitles: [CGWindowID: String] = [:]

    // MARK: - Public

    func getRunningApps() -> [AppItem] {
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }

        // Pre-fetch CG windows grouped by PID (for cross-referencing names & IDs)
        let cgByPid = getCGWindowsByPid()

        // Pre-fetch ScreenCaptureKit window titles (works with temporary access on macOS 15)
        refreshSCWindowTitles()

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
                let icon = app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
                icon.size = NSSize(width: 32, height: 32)

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
                WindowItem(id: Int(cg.windowID), name: cg.name, ownerPid: pid,
                           windowNumber: Int(cg.windowID), cgWindowID: cg.windowID)
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
            if let sv = sizeRef { AXValueGetValue(sv as! AXValue, .cgSize, &axSize) }
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
            if let pv = posRef { AXValueGetValue(pv as! AXValue, .cgPoint, &axPos) }

            // Cross-reference with CG window (excluding already-matched IDs)
            let available = cgEntries.filter { !matchedCGIDs.contains($0.windowID) }
            let matched = matchCGWindow(axPos: axPos, axSize: axSize, axTitle: axTitle, cgEntries: available)
            if let m = matched { matchedCGIDs.insert(m.windowID) }

            // Build window name with smart priority:
            // - AX title is usually best (e.g. Chrome shows profile name "大雄 (大雄呀)")
            // - But Electron apps often return just the app name (e.g. "Pencil")
            //   → in that case, SC/CG names give the real title ("doc.pen — Edited")
            let cgID = matched?.windowID ?? 0
            let cgName = matched?.name ?? ""
            let scName = cgID > 0 ? (scWindowTitles[cgID] ?? "") : ""
            let axTitleIsGeneric = axTitle.isEmpty || axTitle == appName

            let finalName: String
            if !axTitle.isEmpty && !axTitleIsGeneric {
                // AX title is specific (e.g. Chrome profile) — use it
                finalName = axTitle
            } else if !cgName.isEmpty {
                finalName = cgName
            } else if !scName.isEmpty {
                finalName = scName
            } else if !axTitle.isEmpty {
                // Generic AX title (same as app name) — still better than nothing
                finalName = axTitle
            } else if let doc = docPath, let url = URL(string: doc) {
                finalName = url.lastPathComponent
            } else {
                finalName = ""
            }

            // Always generate unique ID: use CG window ID if available, otherwise synthetic
            let uniqueID = Int(cgID != 0 ? cgID : UInt32(pid) &* 1000 &+ UInt32(i))

            NSLog("[CircleTabs] AX win[%d]: axTitle='%@' cgName='%@' scName='%@' final='%@' cgID=%d",
                  i, axTitle, cgName, scName, finalName, cgID)

            items.append(WindowItem(
                id: uniqueID,
                name: finalName,
                ownerPid: pid,
                windowNumber: uniqueID,
                cgWindowID: cgID,
                isMinimized: isMinimized
            ))
        }

        // Disambiguate same-name windows (e.g. "Pencil", "Pencil" → "Pencil (1)", "Pencil (2)")
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

        NSLog("[CircleTabs] AX pid=%d valid=%d/%d titles=[%@]",
              pid, items.count, axWindows.count,
              items.map { $0.name.isEmpty ? "(empty)" : $0.name }.joined(separator: ", "))
        return items
    }

    /// Match AX window to CG window by position+size proximity
    private func matchCGWindow(axPos: CGPoint, axSize: CGSize, axTitle: String,
                               cgEntries: [CGEntry]) -> CGEntry? {
        // Try exact title match first
        if !axTitle.isEmpty {
            if let m = cgEntries.first(where: { $0.name == axTitle }) { return m }
        }
        // Then geometry match (within 20pt tolerance)
        let tol: CGFloat = 20
        for cg in cgEntries {
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

    private func refreshSCWindowTitles() {
        scWindowTitles = [:]
        // Run on background queue to avoid main-thread deadlock
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, _ in
                if let windows = content?.windows {
                    var titles: [CGWindowID: String] = [:]
                    for w in windows {
                        if let title = w.title, !title.isEmpty {
                            titles[w.windowID] = title
                        }
                    }
                    self?.scWindowTitles = titles
                }
                group.leave()
            }
        }
        // Wait briefly — ScreenCaptureKit is fast when permission is already granted
        _ = group.wait(timeout: .now() + 0.5)
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

    func captureWindowPreview(cgWindowID: CGWindowID, maxSize: CGFloat = 320) -> NSImage? {
        guard cgWindowID > 0 else { return nil }
        guard let cgImage = CGWindowListCreateImage(
            .null, .optionIncludingWindow, cgWindowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else { return nil }

        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)
        guard pixelW > 0, pixelH > 0 else { return nil }

        // CGWindowListCreateImage with .bestResolution returns Retina pixels.
        // Convert to points first, then scale to fit maxSize.
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let ptW = pixelW / screenScale
        let ptH = pixelH / screenScale
        let scale = min(maxSize / ptW, maxSize / ptH, 1.0)
        let newW = ptW * scale
        let newH = ptH * scale

        let image = NSImage(cgImage: cgImage, size: NSSize(width: newW, height: newH))
        return image
    }

    // MARK: - Activate & Terminate

    func terminateApp(_ app: AppItem) {
        if let runningApp = NSRunningApplication(processIdentifier: app.pid) {
            runningApp.terminate()
        }
    }

    func activateApp(_ app: AppItem) {
        if let runningApp = NSRunningApplication(processIdentifier: app.pid) {
            runningApp.activate(options: [.activateIgnoringOtherApps])
        }
    }

    func closeWindow(_ window: WindowItem) {
        guard let axWindow = findAXWindow(window) else { return }
        var closeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeRef)
        if let closeButton = closeRef {
            AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
        }
    }

    private func findAXWindow(_ window: WindowItem) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(window.ownerPid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let axWindows = windowsRef as? [AXUIElement] else { return nil }

        // Match by title
        if !window.name.isEmpty {
            for axWindow in axWindows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                if let title = titleRef as? String, title == window.name {
                    return axWindow
                }
            }
        }
        // Fallback by index
        let idx = window.id % 1000
        if idx >= 0 && idx < axWindows.count { return axWindows[idx] }
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

        // Match by title
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

        // Fallback: activate by index
        let idx = window.id % 1000
        if idx >= 0 && idx < axWindows.count {
            unminimizeAndRaise(axWindows[idx], pid: window.ownerPid)
        } else if let app = NSRunningApplication(processIdentifier: window.ownerPid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// Unminimize (if needed), raise the AX window, and activate the owning app.
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
