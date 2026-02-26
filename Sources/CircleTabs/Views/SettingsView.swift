import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isRecording = false
    @State private var recordingDisplay = ""
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text("CircleTabs 设置")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 16)

            // Hotkey section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("快捷键绑定")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }

                // Hotkey list
                VStack(spacing: 4) {
                    ForEach(settings.hotKeys) { combo in
                        HStack {
                            Text(combo.displayString)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )

                            Spacer()

                            if settings.hotKeys.count > 1 {
                                Button(action: {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        settings.removeHotKey(combo)
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )

                // Add / Record button
                if isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(recordingDisplay.isEmpty ? "按下按键/鼠标组合..." : recordingDisplay)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("取消") {
                            stopRecording()
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    Button(action: startRecording) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("添加快捷键")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }

                Text("支持按键、鼠标右键及组合键，ESC 取消录制")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .padding(.horizontal, 16)

            // Preview section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("窗口预览")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }

                Toggle("显示窗口预览", isOn: $settings.showPreview)
                    .font(.system(size: 13))

                if settings.showPreview {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("预览延迟")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f 秒", settings.previewDelay))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.previewDelay, in: 0.1...2.0, step: 0.1)
                            .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Spacer()
        }
        .frame(width: 360, height: 440)
        .onDisappear {
            stopRecording()
        }
    }

    private func modifierParts(from modFlags: NSEvent.ModifierFlags) -> [String] {
        var parts: [String] = []
        if modFlags.contains(.function) { parts.append("🌐") }
        if modFlags.contains(.control) { parts.append("⌃") }
        if modFlags.contains(.option) { parts.append("⌥") }
        if modFlags.contains(.shift) { parts.append("⇧") }
        if modFlags.contains(.command) { parts.append("⌘") }
        return parts
    }

    private func cgFlags(from modFlags: NSEvent.ModifierFlags) -> UInt64 {
        var flags: UInt64 = 0
        if modFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
        if modFlags.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
        if modFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
        if modFlags.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
        if modFlags.contains(.function) { flags |= CGEventFlags.maskSecondaryFn.rawValue }
        return flags
    }

    private func startRecording() {
        isRecording = true
        recordingDisplay = ""
        onStartRecording?()

        // Keyboard monitor
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                let keyCode = Int(event.keyCode)
                let modFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let hasModifier = modFlags.contains(.command) || modFlags.contains(.option)
                    || modFlags.contains(.control) || modFlags.contains(.shift)
                    || modFlags.contains(.function)

                // ESC without modifiers cancels
                if keyCode == 53 && !hasModifier {
                    stopRecording()
                    return nil
                }

                let combo = HotKeyCombination(keyCode: keyCode, modifiers: cgFlags(from: modFlags))
                settings.addHotKey(combo)
                stopRecording()
                return nil
            }

            if event.type == .flagsChanged {
                let modFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let parts = modifierParts(from: modFlags)
                recordingDisplay = parts.isEmpty ? "" : parts.joined() + " ..."
            }
            return nil
        }

        // Mouse monitor (right click)
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { event in
            let modFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let parts = modifierParts(from: modFlags)
            let combo = HotKeyCombination(
                keyCode: -1,
                modifiers: cgFlags(from: modFlags),
                mouseButton: 2
            )
            settings.addHotKey(combo)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        recordingDisplay = ""
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        onStopRecording?()
    }
}
