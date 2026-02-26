import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var tagManager = TagManager.shared
    @ObservedObject var quickLaunch = QuickLaunchManager.shared
    @State private var isRecording = false
    @State private var recordingDisplay = ""
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var isAddingTag = false
    @State private var newTagName = ""
    @State private var newTagColor = "blue"
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("CircleTabs Settings")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()
                    .padding(.horizontal, 16)

                hotkeySection
                Divider().padding(.horizontal, 16)
                previewSection
                Divider().padding(.horizontal, 16)
                tagPresetsSection
                Divider().padding(.horizontal, 16)
                quickLaunchSection

                Spacer(minLength: 16)
            }
        }
        .frame(width: 360, height: 580)
        .onDisappear { stopRecording() }
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Hotkey Bindings")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }

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
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { settings.removeHotKey(combo) }
                            } label: {
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

            if isRecording {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text(recordingDisplay.isEmpty ? "Press a key or mouse combo..." : recordingDisplay)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") { stopRecording() }
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
                        Image(systemName: "plus.circle.fill").font(.system(size: 14))
                        Text("Add Hotkey").font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }

            Text("Supports keys, right-click & combos. ESC to cancel.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Window Preview")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }

            Toggle("Show Window Preview", isOn: $settings.showPreview)
                .font(.system(size: 13))

            if settings.showPreview {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Preview Delay").font(.system(size: 12)).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1fs", settings.previewDelay))
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
    }

    // MARK: - Tag Presets Section

    private var tagPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Tag Presets")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }

            VStack(spacing: 4) {
                ForEach(tagManager.presetTags) { tag in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tag.color)
                            .frame(width: 12, height: 12)
                        Text(tag.name)
                            .font(.system(size: 13))
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { tagManager.removePresetTag(tag) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )

            if isAddingTag {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(AppTag.availableColors, id: \.self) { colorName in
                            Button {
                                newTagColor = colorName
                            } label: {
                                Text("\(AppTag.emojiFor(colorName)) \(AppTag.displayNameFor(colorName))")
                            }
                        }
                    } label: {
                        Circle()
                            .fill(AppTag.colorFor(newTagColor))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 0.5))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30)

                    TextField("Tag name", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Button("Add") {
                        guard !newTagName.isEmpty else { return }
                        tagManager.addPresetTag(AppTag(name: newTagName, colorName: newTagColor))
                        newTagName = ""
                        isAddingTag = false
                    }
                    .font(.system(size: 12))
                    .disabled(newTagName.isEmpty)

                    Button("Cancel") {
                        isAddingTag = false
                        newTagName = ""
                    }
                    .font(.system(size: 12))
                }
            } else {
                Button { isAddingTag = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 14))
                        Text("Add Tag").font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }

            Text("Right-click on apps to quickly assign tags")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Quick Launch Section

    private var quickLaunchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Quick Launch")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }

            VStack(spacing: 4) {
                let boundSlots = (1...9).filter { quickLaunch.bindings[$0] != nil }
                if boundSlots.isEmpty {
                    Text("No bindings")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(8)
                } else {
                    ForEach(boundSlots, id: \.self) { slot in
                        if let binding = quickLaunch.bindings[slot] {
                            HStack(spacing: 8) {
                                Text("⌥\(slot)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .frame(width: 30, alignment: .leading)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(binding.displayName)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                if binding.cgWindowID != nil {
                                    Image(systemName: "macwindow")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) { quickLaunch.unbind(slot: slot) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )

            Text("Right-click apps to bind ⌥+Number. Auto-expires when app closes.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Recording Helpers

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

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                let keyCode = Int(event.keyCode)
                let modFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let hasModifier = modFlags.contains(.command) || modFlags.contains(.option)
                    || modFlags.contains(.control) || modFlags.contains(.shift)
                    || modFlags.contains(.function)

                if keyCode == 53 && !hasModifier { stopRecording(); return nil }

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

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { event in
            let modFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let combo = HotKeyCombination(
                keyCode: -1, modifiers: cgFlags(from: modFlags), mouseButton: 2
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
