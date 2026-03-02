import SwiftUI

// MARK: - Installed App Info (for app picker)

private struct InstalledAppInfo: Identifiable, Hashable {
    let bundleId: String
    let name: String
    let path: String
    let icon: NSImage

    var id: String { bundleId }

    func hash(into hasher: inout Hasher) { hasher.combine(bundleId) }
    static func == (lhs: InstalledAppInfo, rhs: InstalledAppInfo) -> Bool { lhs.bundleId == rhs.bundleId }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var tagManager = TagManager.shared
    @ObservedObject var quickLaunch = QuickLaunchManager.shared
    @ObservedObject var pinnedManager = PinnedAppsManager.shared
    @ObservedObject var locationProvider = LocationContextProvider.shared
    @State private var selectedTab = 0
    @State private var showClearConfirm = false
    @State private var isRecording = false
    @State private var recordingDisplay = ""
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var isAddingTag = false
    @State private var newTagName = ""
    @State private var newTagColor = "blue"
    @State private var searchText = ""
    @State private var installedApps: [InstalledAppInfo] = []
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onShowKBGuide: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("General", icon: "gearshape.fill", index: 0)
                tabButton("Apps", icon: "square.grid.2x2.fill", index: 1)
                tabButton("Display", icon: "paintbrush.fill", index: 2)
                tabButton("Tags", icon: "tag.fill", index: 3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case 0: generalTab
                    case 1: appsTab
                    case 2: displayTab
                    case 3: tagsTab
                    default: EmptyView()
                    }
                    Spacer(minLength: 16)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 600)
        .onAppear { loadInstalledApps() }
        .onDisappear { stopRecording() }
    }

    // MARK: - Tab Button

    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = index }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(selectedTab == index ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == index ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - General Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            hotkeySection
            Divider().padding(.horizontal, 16)
            keyboardModeSection
            Divider().padding(.horizontal, 16)
            quickLaunchSection
        }
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "keyboard", title: "Hotkey Bindings")

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
            .background(cardBackground)

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

    // MARK: - Keyboard Mode Section

    private var keyboardModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "keyboard.fill", title: "Keyboard Mode")

            Toggle("Pure Keyboard Navigation", isOn: $settings.keyboardMode)
                .font(.system(size: 13))
                .onChange(of: settings.keyboardMode) { _ in
                    if settings.keyboardMode && !UserDefaults.standard.bool(forKey: "kbModeGuideShown") {
                        UserDefaults.standard.set(true, forKey: "kbModeGuideShown")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onShowKBGuide?()
                        }
                    }
                }

            HStack {
                Text("Orby always opens at screen center. Navigate with ←→, expand with ↑↓, press Space to switch, or 1–9 to jump directly.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    onShowKBGuide?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                        Text("Guide")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Quick Launch Section

    private var quickLaunchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "bolt.fill", title: "Quick Launch")

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
                                Text("\u{2325}\(slot)")
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
            .background(cardBackground)

            Text("Right-click apps to bind \u{2325}+Number. Auto-expires when app closes.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Apps Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var appsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Mode picker
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(icon: "square.grid.2x2", title: "App Source")

                Picker("", selection: $settings.appSourceMode) {
                    Text("Running Apps").tag(AppSourceMode.runningApps)
                    Text("Manual Edit").tag(AppSourceMode.manualEdit)
                    Text("Smart").tag(AppSourceMode.smartSuggestions)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: settings.appSourceMode) { _ in
                    SuggestionEngine.shared.invalidateCache()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().padding(.horizontal, 16)

            switch settings.appSourceMode {
            case .runningApps:
                runningAppsInfo
            case .manualEdit:
                manualEditSection
            case .smartSuggestions:
                smartSuggestionsSection
            }
        }
    }

    private var runningAppsInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "play.circle", title: "Running Apps Mode")

            VStack(alignment: .leading, spacing: 8) {
                infoRow(icon: "checkmark.circle.fill", color: .green,
                        text: "Automatically shows all running applications")
                infoRow(icon: "checkmark.circle.fill", color: .green,
                        text: "Apps appear/disappear as they launch/quit")
                infoRow(icon: "checkmark.circle.fill", color: .green,
                        text: "Windows are detected via Accessibility API")
            }
            .padding(12)
            .background(cardBackground)

            Text("This is the default mode. Orby shows all currently running apps with their windows.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Manual Edit Section

    private var manualEditSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Circular preview with drag reorder & delete
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(icon: "circle.grid.3x3", title: "Layout Preview (\(pinnedManager.pinnedApps.count))")
                if pinnedManager.pinnedApps.isEmpty {
                    Text("No apps pinned yet. Search and add apps below.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("Drag to reorder · Hover and click ✕ to remove")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                CircularPreviewView(
                    pinnedManager: pinnedManager,
                    clockwise: settings.subAppSortClockwise
                )
            }

            Divider().padding(.horizontal, 0)

            // Installed apps search
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(icon: "magnifyingglass", title: "Add Apps")

                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("Search installed apps...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(filteredInstalledApps) { app in
                            installedAppRow(app: app)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .padding(4)
                .background(cardBackground)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Smart Suggestions Section

    private var smartSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(icon: "sparkles", title: "Smart Suggestions Mode")

                VStack(alignment: .leading, spacing: 8) {
                    infoRow(icon: "brain.head.profile", color: .purple,
                            text: "Learns from your app usage patterns")
                    infoRow(icon: "clock.fill", color: .blue,
                            text: "Adapts to time of day and day of week")
                    infoRow(icon: "circle.grid.3x3.fill", color: .orange,
                            text: "Always shows at least 6 apps, up to 10")
                    infoRow(icon: "lock.shield.fill", color: .green,
                            text: "All data stored locally on your Mac")
                }
                .padding(12)
                .background(cardBackground)

                if !UsageTracker.shared.hasData {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("Start using Orby to build up usage data. Running apps will fill in until enough patterns are learned.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.08))
                    )
                }
            }

            Divider().padding(.horizontal, 0)

            // Location toggle
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(icon: "location.fill", title: "Location Context")

                Toggle("Use location for better suggestions", isOn: $locationProvider.locationEnabled)
                    .font(.system(size: 13))

                Text("Suggests different apps based on where you are (e.g., work vs. home). Your location data never leaves your Mac.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider().padding(.horizontal, 0)

            // Clear data
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(icon: "trash", title: "Usage Data")

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill").font(.system(size: 12))
                        Text("Clear Usage History").font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .alert("Clear Usage History?", isPresented: $showClearConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) {
                        UsageTracker.shared.clearAllData()
                        SuggestionEngine.shared.invalidateCache()
                    }
                } message: {
                    Text("This will delete all usage data. Smart Suggestions will start fresh.")
                }

                Text("Removes all recorded app usage history used for suggestions.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // Pinned app management is handled directly in CircularPreviewView below

    // MARK: - Installed Apps

    private var filteredInstalledApps: [InstalledAppInfo] {
        let pinned = Set(pinnedManager.pinnedApps.map { $0.bundleId })
        let available = installedApps.filter { !pinned.contains($0.bundleId) }
        if searchText.isEmpty { return available }
        let query = searchText.lowercased()
        return available.filter {
            $0.name.lowercased().contains(query) || $0.bundleId.lowercased().contains(query)
        }
    }

    private func installedAppRow(app: InstalledAppInfo) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    pinnedManager.addApp(PinnedApp(
                        bundleId: app.bundleId,
                        name: app.name,
                        bundlePath: app.path
                    ))
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func loadInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let dirs = [
                "/Applications",
                NSHomeDirectory() + "/Applications",
                "/System/Applications",
                "/System/Library/CoreServices"
            ]
            var apps: [InstalledAppInfo] = []
            var seenBundleIds = Set<String>()
            let fm = FileManager.default

            for dir in dirs {
                guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for item in contents where item.hasSuffix(".app") {
                    let path = (dir as NSString).appendingPathComponent(item)
                    guard let bundle = Bundle(path: path),
                          let bundleId = bundle.bundleIdentifier else { continue }
                    if seenBundleIds.contains(bundleId) { continue }
                    seenBundleIds.insert(bundleId)
                    // Use URL.localizedName for system-language app names (e.g. "备忘录" instead of "Notes")
                    let url = URL(fileURLWithPath: path)
                    let localizedName = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
                    let name: String
                    if let ln = localizedName {
                        name = ln.hasSuffix(".app") ? String(ln.dropLast(4)) : ln
                    } else {
                        name = item.replacingOccurrences(of: ".app", with: "")
                    }
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    icon.size = NSSize(width: 32, height: 32)
                    apps.append(InstalledAppInfo(bundleId: bundleId, name: name, path: path, icon: icon))
                }
            }

            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self.installedApps = apps
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Display Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var displayTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewSection
            Divider().padding(.horizontal, 16)
            animationSpeedSection
            Divider().padding(.horizontal, 16)
            sortDirectionSection
            Divider().padding(.horizontal, 16)
            recentItemsSection
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "eye", title: "Window Preview")

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

    // MARK: - Animation Speed Section

    private var animationSpeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "bolt.horizontal.fill", title: "Animation Speed")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Main App").font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fx", settings.mainAppSpeed))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.mainAppSpeed, in: 0.5...3.0, step: 0.1)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Sub-Window").font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fx", settings.subAppSpeed))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.subAppSpeed, in: 0.5...3.0, step: 0.1)
                    .controlSize(.small)
            }

            Text("Higher value = faster entrance animation")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Sort Direction Section

    private var sortDirectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "arrow.triangle.2.circlepath", title: "Sort Direction")

            Picker("", selection: $settings.subAppSortClockwise) {
                Text("Clockwise").tag(true)
                Text("Counter-clockwise").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(.system(size: 12))

            Text("Controls the arrangement direction for apps and sub-windows in the circle.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Recent Items Section

    private var recentItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "clock.arrow.circlepath", title: "Recent Items")

            Toggle("Show Recent Items Bar", isOn: $settings.showRecentItems)
                .font(.system(size: 13))

            Text("Display a horizontal bar of recently opened files and apps at the bottom of the Orby circle.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Tags Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tagsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tagPresetsSection
        }
    }

    // MARK: - Tag Presets Section

    private var tagPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "tag", title: "Tag Presets")

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
            .background(cardBackground)

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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Shared Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Recording Helpers

    private func modifierParts(from modFlags: NSEvent.ModifierFlags) -> [String] {
        var parts: [String] = []
        if modFlags.contains(.function) { parts.append("\u{1F310}") }
        if modFlags.contains(.control) { parts.append("\u{2303}") }
        if modFlags.contains(.option) { parts.append("\u{2325}") }
        if modFlags.contains(.shift) { parts.append("\u{21E7}") }
        if modFlags.contains(.command) { parts.append("\u{2318}") }
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
                guard hasModifier else { return nil }

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

// MARK: - Circular Preview with Drag Reorder

private struct CircularPreviewView: View {
    @ObservedObject var pinnedManager: PinnedAppsManager
    let clockwise: Bool

    @State private var dragId: String? = nil
    @State private var dragPos: CGPoint = .zero
    @State private var dragStartPos: CGPoint = .zero
    @State private var hoveredId: String? = nil

    private let viewSize: CGFloat = 300
    private let bubbleSize: CGFloat = 50

    private var cx: CGFloat { viewSize / 2 }
    private var cy: CGFloat { viewSize / 2 }

    private var ringR: CGFloat {
        let n = CGFloat(pinnedManager.pinnedApps.count)
        guard n > 1 else { return 0 }
        let spacing = bubbleSize + 12
        let natural = n * spacing / (2 * .pi)
        return min(max(natural, 80), viewSize / 2 - bubbleSize / 2 - 16)
    }

    private func slotPosition(at index: Int) -> CGPoint {
        let n = pinnedManager.pinnedApps.count
        guard n > 0 else { return CGPoint(x: cx, y: cy) }
        if n == 1 { return CGPoint(x: cx, y: cy - 80) }
        let step = 2.0 * .pi / Double(n)
        let a: Double = clockwise
            ? -.pi / 2 + step * Double(index)
            : -.pi / 2 - step * Double(index)
        return CGPoint(x: cx + ringR * CGFloat(cos(a)), y: cy + ringR * CGFloat(sin(a)))
    }

    private func nearestSlot(to pt: CGPoint) -> Int {
        let n = pinnedManager.pinnedApps.count
        guard n > 1 else { return 0 }
        var bestIdx = 0
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for i in 0..<n {
            let p = slotPosition(at: i)
            let d = (pt.x - p.x) * (pt.x - p.x) + (pt.y - p.y) * (pt.y - p.y)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return bestIdx
    }

    private func currentIndex(of id: String) -> Int {
        pinnedManager.pinnedApps.firstIndex(where: { $0.id == id }) ?? 0
    }

    var body: some View {
        let n = pinnedManager.pinnedApps.count
        ZStack {
            // Center X
            previewCenter
                .position(x: cx, y: cy)

            // Empty state
            if n == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.15))
                    Text("Add apps below")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.white.opacity(0.25))
                }
                .position(x: cx, y: cy)
            }

            // Ring guide
            if n > 1 {
                Circle()
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    .frame(width: ringR * 2, height: ringR * 2)
                    .position(x: cx, y: cy)
            }

            // App bubbles
            ForEach(pinnedManager.pinnedApps) { pinned in
                makeBubble(pinned: pinned)
            }
        }
        .frame(width: viewSize, height: viewSize)
        .background(previewBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func makeBubble(pinned: PinnedApp) -> some View {
        let idx = currentIndex(of: pinned.id)
        let pos = slotPosition(at: idx)
        let isDragging = dragId == pinned.id
        let isHovered = hoveredId == pinned.id && dragId == nil

        PreviewBubbleContent(
            pinned: pinned,
            size: bubbleSize,
            isDragging: isDragging,
            isHovered: isHovered,
            onDelete: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    pinnedManager.removeApp(bundleId: pinned.bundleId)
                }
            }
        )
        .onHover { over in
            hoveredId = over ? pinned.id : nil
        }
        .position(isDragging ? dragPos : pos)
        .zIndex(isDragging ? 100 : (isHovered ? 50 : 0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pos)
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    onDrag(pinned: pinned, translation: value.translation)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        dragId = nil
                    }
                }
        )
    }

    private func onDrag(pinned: PinnedApp, translation: CGSize) {
        if dragId == nil {
            let idx = currentIndex(of: pinned.id)
            dragStartPos = slotPosition(at: idx)
            dragId = pinned.id
        }
        let newPos = CGPoint(
            x: dragStartPos.x + translation.width,
            y: dragStartPos.y + translation.height
        )
        dragPos = newPos

        let currentIdx = currentIndex(of: pinned.id)
        let targetIdx = nearestSlot(to: newPos)
        if targetIdx != currentIdx {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                pinnedManager.moveApp(fromIndex: currentIdx, toIndex: targetIdx)
            }
        }
    }

    private var previewCenter: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 22, height: 22)
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.25))
        }
    }

    private var previewBg: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(white: 0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct PreviewBubbleContent: View {
    let pinned: PinnedApp
    let size: CGFloat
    let isDragging: Bool
    let isHovered: Bool
    let onDelete: () -> Void

    var body: some View {
        let icon = NSWorkspace.shared.icon(forFile: pinned.bundlePath)
        let iconSize = size * 0.65
        VStack(spacing: 3) {
            ZStack {
                // Frosted glass circle
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .shadow(
                        color: .black.opacity(isDragging ? 0.25 : 0.12),
                        radius: isDragging ? 12 : 6,
                        x: 0, y: isDragging ? 6 : 3
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                Color.white.opacity(isDragging ? 0.35 : (isHovered ? 0.30 : 0.18)),
                                lineWidth: 1
                            )
                    )

                // App icon
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            }
            .frame(width: size, height: size)
            // Close badge — top-leading, shown on hover
            .overlay(alignment: .topLeading) {
                if isHovered {
                    Button(action: onDelete) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 18, height: 18)
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .offset(x: -4, y: -4)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }

            // Name label
            Text(pinned.name)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: 58)
        }
        .scaleEffect(isDragging ? 1.15 : (isHovered ? 1.08 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isDragging)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
    }
}
