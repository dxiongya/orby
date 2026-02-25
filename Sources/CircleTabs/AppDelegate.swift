import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayPanel: OverlayPanel?
    private var hotKeyManager = HotKeyManager()
    private var isOverlayVisible = false
    private var escapeMonitor: Any?
    private var permissionWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupEscapeMonitor()

        if HotKeyManager.hasAccessibilityPermission {
            startApp()
        } else {
            // Reset stale TCC entry (code signature changed after rebuild),
            // then re-prompt so the app appears in the Accessibility list.
            resetAccessibilityTCC()
            showPermissionGuide()
        }
    }

    /// Start hotkey after permission is confirmed
    private func startApp() {
        setupHotKey()
        closePermissionGuide()
    }

    // MARK: - Permission Guide

    private func showPermissionGuide() {
        // Prompt the system dialog
        HotKeyManager.requestAccessibilityPermission()

        let guideView = PermissionGuideView {
            DispatchQueue.main.async { [weak self] in
                self?.startApp()
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CircleTabs"
        window.contentView = NSHostingView(rootView: guideView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow = window
    }

    private func closePermissionGuide() {
        permissionWindow?.close()
        permissionWindow = nil
    }

    /// Clear stale TCC entry for this app so macOS re-prompts with the new code signature.
    private func resetAccessibilityTCC() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.circletabs.app"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "circle.grid.3x3.fill", accessibilityDescription: "CircleTabs")

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show CircleTabs", action: #selector(toggleOverlay), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(NSMenuItem.separator())
        let perm = NSMenuItem(title: "Open Accessibility Settings...", action: #selector(openAccessibility), keyEquivalent: "")
        perm.target = self
        menu.addItem(perm)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    // MARK: - Hot Key

    private func setupHotKey() {
        hotKeyManager.onToggle = { [weak self] in
            self?.toggleOverlay()
        }
        hotKeyManager.start()
    }

    private func setupEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hideOverlay(); return nil }
            return event
        }
    }

    // MARK: - Overlay

    @objc private func toggleOverlay() {
        if !HotKeyManager.hasAccessibilityPermission {
            showPermissionGuide()
            return
        }
        if isOverlayVisible { hideOverlay() } else { showOverlay() }
    }

    private func showOverlay() {
        guard !isOverlayVisible else { return }
        isOverlayVisible = true

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main!

        let panel = OverlayPanel(screen: screen)
        let binding = Binding<Bool>(
            get: { [weak self] in self?.isOverlayVisible ?? false },
            set: { [weak self] v in if !v { DispatchQueue.main.async { self?.hideOverlay() } } }
        )
        panel.contentView = NSHostingView(rootView: CircleTabsView(isVisible: binding))
        panel.showOverlay()
        overlayPanel = panel
    }

    private func hideOverlay() {
        guard isOverlayVisible else { return }
        isOverlayVisible = false
        overlayPanel?.hideOverlay()
        overlayPanel = nil
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quitApp() { hotKeyManager.stop(); NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.stop()
        if let m = escapeMonitor { NSEvent.removeMonitor(m) }
    }
}
