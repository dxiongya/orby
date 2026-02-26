import SwiftUI

struct AppTag: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorName: String

    init(id: UUID = UUID(), name: String, colorName: String) {
        self.id = id
        self.name = name
        self.colorName = colorName
    }

    var color: Color {
        Self.colorFor(colorName)
    }

    var emoji: String {
        Self.emojiFor(colorName)
    }

    static let availableColors = ["red", "blue", "green", "orange", "purple", "pink", "yellow", "gray", "cyan", "mint"]

    static func colorFor(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        case "cyan": return .cyan
        case "mint": return .mint
        default: return .blue
        }
    }

    static func emojiFor(_ name: String) -> String {
        switch name {
        case "red": return "\u{1F534}"
        case "blue": return "\u{1F535}"
        case "green": return "\u{1F7E2}"
        case "orange": return "\u{1F7E0}"
        case "purple": return "\u{1F7E3}"
        case "pink": return "\u{1FA77}"
        case "yellow": return "\u{1F7E1}"
        case "gray": return "\u{26AA}"
        case "cyan": return "\u{1FA75}"
        case "mint": return "\u{1F7E9}"
        default: return "\u{26AA}"
        }
    }

    static func displayNameFor(_ name: String) -> String {
        switch name {
        case "red": return "Red"
        case "blue": return "Blue"
        case "green": return "Green"
        case "orange": return "Orange"
        case "purple": return "Purple"
        case "pink": return "Pink"
        case "yellow": return "Yellow"
        case "gray": return "Gray"
        case "cyan": return "Cyan"
        case "mint": return "Mint"
        default: return name
        }
    }
}
