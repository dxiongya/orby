import SwiftUI
import Cocoa
import ScreenCaptureKit

struct PermissionGuideView: View {
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var hasScreenRecording = CGPreflightScreenCaptureAccess()
    @State private var timer: Timer?

    var onAllGranted: () -> Void

    private var allGranted: Bool { hasAccessibility && hasScreenRecording }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
                .padding(.top, 8)

            Text("CircleTabs 需要以下权限")
                .font(.system(size: 17, weight: .bold, design: .rounded))

            // Status list
            VStack(spacing: 10) {
                permissionRow(
                    name: "辅助功能",
                    detail: "用于全局快捷键和窗口管理",
                    icon: "hand.raised",
                    granted: hasAccessibility
                )
                permissionRow(
                    name: "屏幕录制",
                    detail: "用于窗口预览截图",
                    icon: "rectangle.dashed.badge.record",
                    granted: hasScreenRecording
                )
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            if allGranted {
                Text("所有权限已授予，正在启动...")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
            } else {
                // Show buttons only for missing permissions
                VStack(spacing: 8) {
                    if !hasAccessibility {
                        Button(action: grantAccessibility) {
                            HStack {
                                Image(systemName: "hand.raised")
                                Text("授权辅助功能")
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
                                Text("授权屏幕录制")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                    }

                    Button(action: revealInFinder) {
                        HStack {
                            Image(systemName: "folder")
                            Text("在 Finder 中显示 App")
                        }
                    }
                    .controlSize(.regular)
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
                .frame(maxWidth: 260)

                Text("点击按钮后在系统弹窗中允许，授权后自动启动")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 360)
        .onAppear { startPolling() }
        .onDisappear { timer?.invalidate() }
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
        // CGRequestScreenCaptureAccess() is unreliable on macOS 15 Sequoia — use ScreenCaptureKit instead.
        // SCShareableContent triggers the proper system permission dialog on first use.
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            DispatchQueue.main.async {
                if content != nil {
                    // Permission granted (temporary or permanent)
                    withAnimation { hasScreenRecording = true }
                } else {
                    // Dialog was dismissed / denied — open System Settings as fallback
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

    // MARK: - Polling (no system dialogs here, just check status)

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let ax = AXIsProcessTrusted()
            if ax != hasAccessibility { withAnimation { hasAccessibility = ax } }

            // Screen recording: only upgrade false → true, never downgrade.
            // CGPreflightScreenCaptureAccess() doesn't detect temporary access on macOS 15,
            // but SCShareableContent callback in grantScreenRecording() does.
            if !hasScreenRecording {
                let sr = CGPreflightScreenCaptureAccess()
                if sr { withAnimation { hasScreenRecording = true } }
            }

            if ax && hasScreenRecording {
                timer?.invalidate()
                timer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onAllGranted()
                }
            }
        }
    }
}
