import Cocoa
import Carbon

final class HotKeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var installedRunLoop: CFRunLoop?
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

    func start() {
        if !HotKeyManager.hasAccessibilityPermission {
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
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout {
                // Timeout is transient — safe to re-enable
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            if type == .tapDisabledByUserInput {
                // System/user revoked access. Clean up SYNCHRONOUSLY here.
                // Using DispatchQueue.main.async would deadlock: the main RunLoop
                // is blocked on the event pipeline, which is blocked on this callback.
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: false)
                }
                if let source = manager.runLoopSource, let loop = manager.installedRunLoop {
                    CFRunLoopRemoveSource(loop, source, .commonModes)
                }
                manager.eventTap = nil
                manager.runLoopSource = nil
                manager.installedRunLoop = nil
                return Unmanaged.passUnretained(event)
            }

            if manager.isPaused {
                return Unmanaged.passUnretained(event)
            }

            let flags = event.flags

            // Keyboard hotkey
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if SettingsManager.shared.matchesKeyHotKey(keyCode: keyCode, flags: flags) {
                    DispatchQueue.main.async { manager.onToggle?() }
                    return nil
                }
            }

            // Mouse hotkey (right click)
            if type == .rightMouseDown {
                if SettingsManager.shared.matchesMouseHotKey(button: 2, flags: flags) {
                    DispatchQueue.main.async { manager.onToggle?() }
                    return nil
                }
            }

            return Unmanaged.passUnretained(event)
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
            return
        }

        eventTap = tap
        installedRunLoop = CFRunLoopGetMain()
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource, let loop = installedRunLoop {
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource, let loop = installedRunLoop {
                CFRunLoopRemoveSource(loop, source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
            installedRunLoop = nil
        }
    }

    deinit { stop() }
}
