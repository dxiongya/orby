import Cocoa
import SwiftUI
import ScreenCaptureKit

extension Notification.Name {
    static let escapePressed = Notification.Name("CircleTabsEscapePressed")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayPanel: OverlayPanel?
    private var hotKeyManager = HotKeyManager()
    private var isOverlayVisible = false
    private var escapeMonitor: Any?
    private var permissionWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupEscapeMonitor()

        let hasAX = HotKeyManager.hasAccessibilityPermission

        // CGPreflightScreenCaptureAccess() doesn't detect temporary access on macOS 15.
        // Check permanent access first; if not, try ScreenCaptureKit (detects temporary access).
        if hasAX && CGPreflightScreenCaptureAccess() {
            startApp()
            return
        }

        if hasAX {
            // AX is fine, check screen recording via ScreenCaptureKit
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, _ in
                DispatchQueue.main.async {
                    if content != nil {
                        self?.startApp()
                    } else {
                        self?.showPermissionGuide()
                    }
                }
            }
        } else {
            resetAccessibilityTCC()
            showPermissionGuide()
        }
    }

    /// Start hotkey after permission is confirmed
    private func startApp() {
        setupHotKey()
        QuickLaunchManager.shared.startMonitoring()
        closePermissionGuide()
    }

    // MARK: - Permission Guide

    private func showPermissionGuide() {
        // Don't trigger system dialogs here — PermissionGuideView handles it on button click
        let guideView = PermissionGuideView {
            DispatchQueue.main.async { [weak self] in
                self?.startApp()
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
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
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
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

    // MARK: - Settings

    @objc private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            onStartRecording: { [weak self] in
                self?.hotKeyManager.isPaused = true
            },
            onStopRecording: { [weak self] in
                self?.hotKeyManager.isPaused = false
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CircleTabs Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
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
            if event.keyCode == 53 {
                guard self?.isOverlayVisible == true else { return event }
                // Post notification — CircleTabsView decides whether to exit close mode or dismiss
                NotificationCenter.default.post(name: .escapePressed, object: nil)
                return nil
            }
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

    @objc private func quitApp() {
        hotKeyManager.stop()
        QuickLaunchManager.shared.stopMonitoring()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.stop()
        if let m = escapeMonitor { NSEvent.removeMonitor(m) }
    }
}
