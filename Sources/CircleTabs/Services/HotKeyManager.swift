import Cocoa
import Carbon

final class HotKeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onToggle: (() -> Void)?

    /// Set true to pass all events through (during hotkey recording)
    var isPaused = false

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    private static func dbg(_ msg: String) {
        let path = "/tmp/circletabs_debug.txt"
        let line = "[HotKey \(Date())] \(msg)\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); fh.closeFile()
        }
    }

    func start() {
        let hasPerm = HotKeyManager.hasAccessibilityPermission
        Self.dbg("start() hasPerm=\(hasPerm)")
        if !hasPerm {
            HotKeyManager.requestAccessibilityPermission()
            return
        }
        setupEventTap()
    }

    func stop() {
        removeEventTap()
    }

    private func setupEventTap() {
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                HotKeyManager.dbg("tap re-enabled (was disabled)")
                return Unmanaged.passRetained(event)
            }

            if manager.isPaused {
                return Unmanaged.passRetained(event)
            }

            let flags = event.flags

            // Keyboard hotkey
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if SettingsManager.shared.matchesKeyHotKey(keyCode: keyCode, flags: flags) {
                    HotKeyManager.dbg("Key hotkey matched! keyCode=\(keyCode)")
                    DispatchQueue.main.async { manager.onToggle?() }
                    return nil
                }
            }

            // Mouse hotkey (right click)
            if type == .rightMouseDown {
                if SettingsManager.shared.matchesMouseHotKey(button: 2, flags: flags) {
                    HotKeyManager.dbg("Mouse hotkey matched! rightClick flags=\(flags.rawValue)")
                    DispatchQueue.main.async { manager.onToggle?() }
                    return nil
                }
            }

            return Unmanaged.passRetained(event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            Self.dbg("Failed to create CGEventTap!")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Self.dbg("CGEventTap active! Hotkeys ready (keyboard + mouse).")
        }
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    deinit { stop() }
}
