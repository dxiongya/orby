import Cocoa
import SwiftUI
import ScreenCaptureKit

extension Notification.Name {
    static let escapePressed = Notification.Name("OrbyEscapePressed")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayPanel: OverlayPanel?
    private var hotKeyManager = HotKeyManager()
    private var isOverlayVisible = false
    private var escapeMonitor: Any?
    private var permissionWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var permissionMonitorTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupEscapeMonitor()

        let hasAX = HotKeyManager.hasAccessibilityPermission

        // Fast path: both permissions confirmed (permanent access)
        if hasAX && CGPreflightScreenCaptureAccess() {
            startApp()
            return
        }

        // Only probe SCShareableContent if user has previously granted screen recording.
        // On first launch, calling SCShareableContent triggers the system dialog immediately,
        // which is confusing — the user should see our permission guide first and click
        // "Grant Screen Recording" to trigger the dialog intentionally.
        let srPreviouslyGranted = UserDefaults.standard.bool(forKey: "srPreviouslyGranted")

        if hasAX && srPreviouslyGranted {
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
            showPermissionGuide()
        }
    }

    private func startApp() {
        UserDefaults.standard.set(true, forKey: "srPreviouslyGranted")
        setupHotKey()
        QuickLaunchManager.shared.startMonitoring()
        closePermissionGuide()
        startPermissionMonitor()

        if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            showOnboarding()
        }
    }

    // MARK: - Permission Monitor

    /// Periodically check if accessibility was revoked at runtime.
    /// Gracefully tear down the event tap and re-show the permission guide.
    private func startPermissionMonitor() {
        permissionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            if !HotKeyManager.hasAccessibilityPermission {
                self?.permissionMonitorTimer?.invalidate()
                self?.permissionMonitorTimer = nil
                self?.hotKeyManager.stop()
                self?.hideOverlay()
                self?.showPermissionGuide()
            }
        }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let view = OnboardingView {
            DispatchQueue.main.async { [weak self] in
                UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Orby"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    // MARK: - Permission Guide

    private func showPermissionGuide() {
        // Avoid opening multiple permission windows
        if let existing = permissionWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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
        window.title = "Orby"
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

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        if let logoImage = NSImage(named: "OrbyLogo") {
            logoImage.size = NSSize(width: 18, height: 18)
            logoImage.isTemplate = true
            button.image = logoImage
        } else {
            button.image = NSImage(systemSymbolName: "circle.grid.3x3.fill", accessibilityDescription: "Orby")
        }

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Orby", action: #selector(toggleOverlay), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let guideItem = NSMenuItem(title: "Usage Guide...", action: #selector(openOnboarding), keyEquivalent: "")
        guideItem.target = self
        menu.addItem(guideItem)
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
        window.title = "Orby Settings"
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
                NotificationCenter.default.post(name: .escapePressed, object: nil)
                return nil
            }
            return event
        }
    }

    // MARK: - Overlay

    @objc private func toggleOverlay() {
        if !HotKeyManager.hasAccessibilityPermission {
            hotKeyManager.stop()
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
        panel.contentView = NSHostingView(rootView: OrbyView(isVisible: binding))
        panel.showOverlay()
        overlayPanel = panel
    }

    private func hideOverlay() {
        guard isOverlayVisible else { return }
        isOverlayVisible = false
        overlayPanel?.hideOverlay()
        overlayPanel = nil
    }

    @objc private func openOnboarding() {
        showOnboarding()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        permissionMonitorTimer?.invalidate()
        hotKeyManager.stop()
        QuickLaunchManager.shared.stopMonitoring()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionMonitorTimer?.invalidate()
        hotKeyManager.stop()
        if let m = escapeMonitor { NSEvent.removeMonitor(m) }
    }
}
