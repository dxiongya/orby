import SwiftUI
import Cocoa
import ScreenCaptureKit

struct PermissionGuideView: View {
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var hasScreenRecording = CGPreflightScreenCaptureAccess()
    @State private var timer: Timer?
    @State private var activationObserver: Any?
    /// Tracks whether the user has clicked "Grant Screen Recording" at least once.
    /// Only after this do we use SCShareableContent in polling/activation checks,
    /// to avoid triggering the system dialog unexpectedly.
    @State private var srGrantAttempted = false

    var onAllGranted: () -> Void

    private var allGranted: Bool { hasAccessibility && hasScreenRecording }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
                .padding(.top, 8)

            Text("Orby needs the following permissions")
                .font(.system(size: 17, weight: .bold, design: .rounded))

            // Status list
            VStack(spacing: 10) {
                permissionRow(
                    name: "Accessibility",
                    detail: "For global hotkey and window management",
                    icon: "hand.raised",
                    granted: hasAccessibility
                )
                permissionRow(
                    name: "Screen Recording",
                    detail: "For window preview screenshots",
                    icon: "rectangle.dashed.badge.record",
                    granted: hasScreenRecording
                )
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            if allGranted {
                Text("All permissions granted. Starting...")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
            } else {
                // Show buttons only for missing permissions
                VStack(spacing: 8) {
                    if !hasAccessibility {
                        Button(action: grantAccessibility) {
                            HStack {
                                Image(systemName: "hand.raised")
                                Text("Grant Accessibility")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                    }

                    if !hasScreenRecording {
                        Button(action: grantScreenRecording) {
                            HStack {
                                Image(systemName: "rectangle.dashed.badge.record")
                                Text("Grant Screen Recording")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                    }

                    Button(action: revealInFinder) {
                        HStack {
                            Image(systemName: "folder")
                            Text("Reveal App in Finder")
                        }
                    }
                    .controlSize(.regular)
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
                .frame(maxWidth: 260)

                Text("Click the button, then allow in the system dialog. Auto-starts after granting.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 360)
        .onAppear {
            if allGranted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onAllGranted() }
            } else {
                startPolling()
                observeAppActivation()
            }
        }
        .onDisappear {
            timer?.invalidate()
            if let observer = activationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    private func permissionRow(name: String, detail: String, icon: String, granted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(granted ? .green : .red)
        }
    }

    // MARK: - Actions (only trigger system dialogs when user clicks)

    private func grantAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func grantScreenRecording() {
        srGrantAttempted = true
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            DispatchQueue.main.async {
                if content != nil {
                    UserDefaults.standard.set(true, forKey: "srPreviouslyGranted")
                    withAnimation { hasScreenRecording = true }
                    checkAllGranted()
                    // Warm up CGWindowList access on a background thread
                    DispatchQueue.global(qos: .utility).async {
                        _ = CGWindowListCreateImage(.null, .optionOnScreenOnly, kCGNullWindowID, .nominalResolution)
                    }
                } else {
                    openScreenRecordingSettings()
                }
            }
        }
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "")
    }

    // MARK: - Polling & Activation Observer

    /// Re-check permissions when user switches back from System Settings.
    private func observeAppActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            recheckPermissions()
        }
    }

    private func recheckPermissions() {
        let ax = AXIsProcessTrusted()
        if ax != hasAccessibility { withAnimation { hasAccessibility = ax } }

        if !hasScreenRecording {
            // Fast sync check — detects permanent access reliably
            if CGPreflightScreenCaptureAccess() {
                withAnimation { hasScreenRecording = true }
            } else if srGrantAttempted {
                // User already interacted with the screen recording dialog.
                // Use SCShareableContent to detect temporary access (macOS 15 Sequoia).
                // Safe: won't trigger a new dialog after the initial interaction.
                SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
                    DispatchQueue.main.async {
                        if content != nil {
                            withAnimation { hasScreenRecording = true }
                        }
                        checkAllGranted()
                    }
                }
                return // checkAllGranted will run in the async callback
            }
        }

        checkAllGranted()
    }

    private func checkAllGranted() {
        if hasAccessibility && hasScreenRecording {
            timer?.invalidate()
            timer = nil
            if let observer = activationObserver {
                NotificationCenter.default.removeObserver(observer)
                activationObserver = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onAllGranted()
            }
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            recheckPermissions()
        }
    }
}
