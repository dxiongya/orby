import Cocoa

struct AppItem: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage
    let pid: pid_t
    let bundleURL: URL?
    var windows: [WindowItem]

    // Layout properties (computed by CircularLayoutEngine)
    var position: CGPoint = .zero
    var ringIndex: Int = 0
    var angle: Double = 0
    var bubbleScale: CGFloat = 1.0

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.id == rhs.id
        && lhs.position == rhs.position
        && lhs.angle == rhs.angle
        && lhs.ringIndex == rhs.ringIndex
        && lhs.bubbleScale == rhs.bubbleScale
        && lhs.windows == rhs.windows
    }
}

struct WindowItem: Identifiable, Equatable {
    let id: Int
    var name: String
    let ownerPid: pid_t
    let windowNumber: Int
    var cgWindowID: CGWindowID = 0  // real CG window ID for preview capture
    var isMinimized: Bool = false   // window is in Dock (minimized)

    // Pre-computed display name (avoids repeated string parsing in hot paths)
    var displayName: String = ""

    // Layout properties
    var position: CGPoint = .zero
    var angle: Double = 0
    var ringIndex: Int = 0
    // Preview image (captured on hover)
    var previewImage: NSImage?

    /// Parse display name from window title (strips app name suffixes like " — AppName")
    static func computeDisplayName(for title: String) -> String {
        guard !title.isEmpty else { return "Window" }
        for sep in [" — ", "—", " \u{2013} ", "\u{2013}"] {
            if let range = title.range(of: sep, options: .backwards) {
                let workspace = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !workspace.isEmpty { return workspace }
            }
        }
        if let range = title.range(of: " - ", options: .backwards) {
            let workspace = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !workspace.isEmpty { return workspace }
        }
        return title
    }

    static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id
        && lhs.position == rhs.position
        && lhs.angle == rhs.angle
        && lhs.ringIndex == rhs.ringIndex
        && (lhs.previewImage != nil) == (rhs.previewImage != nil)
    }
}
