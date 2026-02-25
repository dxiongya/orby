import SwiftUI
import Cocoa

struct PermissionGuideView: View {
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var timer: Timer?

    var onAllGranted: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
                .padding(.top, 8)

            Text("CircleTabs 需要辅助功能权限")
                .font(.system(size: 17, weight: .bold, design: .rounded))

            // Status
            HStack(spacing: 10) {
                Image(systemName: hasAccessibility ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(hasAccessibility ? .green : .red)
                Text(hasAccessibility ? "权限已授予" : "未授权")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(hasAccessibility ? .green : .red)
            }
            .padding(.vertical, 4)

            if hasAccessibility {
                Text("正在启动...")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                // Instructions
                VStack(alignment: .leading, spacing: 10) {
                    Text("请按以下步骤操作：")
                        .font(.system(size: 13, weight: .semibold))

                    instructionRow(step: "1", text: "点击下方按钮打开系统设置")
                    instructionRow(step: "2", text: "点击左下角「+」按钮")
                    instructionRow(step: "3", text: "导航到 ~/Applications，选择 CircleTabs")
                    instructionRow(step: "4", text: "开启 CircleTabs 的开关")
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

                HStack(spacing: 12) {
                    Button(action: openAccessibilitySettings) {
                        Label("打开辅助功能设置", systemImage: "gear")
                    }
                    .controlSize(.large)

                    Button(action: revealInFinder) {
                        Label("在 Finder 中显示 App", systemImage: "folder")
                    }
                    .controlSize(.large)
                }

                Text("授权后会自动检测，无需重启")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 440, height: 400)
        .onAppear { startPolling() }
        .onDisappear { timer?.invalidate() }
    }

    private func instructionRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(step)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
        }
    }

    private func openAccessibilitySettings() {
        // Trigger system prompt first
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Also open Settings directly
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func revealInFinder() {
        let appPath = Bundle.main.bundlePath
        NSWorkspace.shared.selectFile(appPath, inFileViewerRootedAtPath: "")
    }

    private func startPolling() {
        // Trigger system prompt on appear
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let granted = AXIsProcessTrusted()
            if granted != hasAccessibility {
                withAnimation { hasAccessibility = granted }
            }
            if granted {
                timer?.invalidate()
                timer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onAllGranted()
                }
            }
        }
    }
}
