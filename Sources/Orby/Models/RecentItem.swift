import Cocoa

enum RecentItemKind: String {
    case file
    case folder
    case application
}

struct RecentItem: Identifiable, Equatable {
    let id: String          // file path
    let name: String
    let icon: NSImage
    let url: URL
    let lastUsedDate: Date
    let kind: RecentItemKind
    static func == (lhs: RecentItem, rhs: RecentItem) -> Bool {
        lhs.id == rhs.id && lhs.lastUsedDate == rhs.lastUsedDate
    }
}
