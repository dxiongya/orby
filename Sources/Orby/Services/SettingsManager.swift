import Foundation
import Carbon

struct HotKeyCombination: Codable, Identifiable, Equatable {
    var id = UUID()
    var keyCode: Int         // -1 for mouse-only triggers
    var modifiers: UInt64    // CGEventFlags raw value
    var mouseButton: Int = 0 // 0 = keyboard, 2 = right click

    enum CodingKeys: String, CodingKey {
        case id, keyCode, modifiers, mouseButton
    }

    init(id: UUID = UUID(), keyCode: Int, modifiers: UInt64, mouseButton: Int = 0) {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.mouseButton = mouseButton
    }

    // Backward-compatible decoding (old data has no mouseButton)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        modifiers = try container.decode(UInt64.self, forKey: .modifiers)
        mouseButton = try container.decodeIfPresent(Int.self, forKey: .mouseButton) ?? 0
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers & CGEventFlags.maskSecondaryFn.rawValue != 0 { parts.append("🌐") }
        if modifiers & CGEventFlags.maskControl.rawValue != 0 { parts.append("⌃") }
        if modifiers & CGEventFlags.maskAlternate.rawValue != 0 { parts.append("⌥") }
        if modifiers & CGEventFlags.maskShift.rawValue != 0 { parts.append("⇧") }
        if modifiers & CGEventFlags.maskCommand.rawValue != 0 { parts.append("⌘") }
        if mouseButton == 2 {
            parts.append("右键点击")
        } else if mouseButton > 0 {
            parts.append("鼠标\(mouseButton)")
        } else {
            parts.append(Self.keyCodeToString(keyCode))
        }
        return parts.joined(separator: "")
    }

    static func keyCodeToString(_ keyCode: Int) -> String {
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "⌫", 53: "Esc",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14", 109: "F10",
            111: "F12", 113: "F15", 115: "Home", 116: "PgUp", 117: "⌦",
            118: "F4", 119: "End", 120: "F2", 121: "PgDn", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let storageKey = "hotKeyCombinations"

    @Published var hotKeys: [HotKeyCombination] = []
    @Published var showPreview: Bool = true {
        didSet { UserDefaults.standard.set(showPreview, forKey: "showPreview") }
    }
    @Published var previewDelay: Double = 0.45 {
        didSet { UserDefaults.standard.set(previewDelay, forKey: "previewDelay") }
    }
    @Published var keyboardMode: Bool = false {
        didSet { UserDefaults.standard.set(keyboardMode, forKey: "keyboardMode") }
    }

    private init() {
        showPreview = UserDefaults.standard.object(forKey: "showPreview") as? Bool ?? true
        previewDelay = UserDefaults.standard.object(forKey: "previewDelay") as? Double ?? 0.45
        keyboardMode = UserDefaults.standard.object(forKey: "keyboardMode") as? Bool ?? false
        loadHotKeys()
    }

    func loadHotKeys() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let combos = try? JSONDecoder().decode([HotKeyCombination].self, from: data),
           !combos.isEmpty {
            hotKeys = combos
        } else {
            hotKeys = [HotKeyCombination(keyCode: 48, modifiers: CGEventFlags.maskAlternate.rawValue)]
        }
    }

    func saveHotKeys() {
        if let data = try? JSONEncoder().encode(hotKeys) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func addHotKey(_ combo: HotKeyCombination) {
        if !hotKeys.contains(where: {
            $0.keyCode == combo.keyCode && $0.modifiers == combo.modifiers && $0.mouseButton == combo.mouseButton
        }) {
            hotKeys.append(combo)
            saveHotKeys()
        }
    }

    func removeHotKey(_ combo: HotKeyCombination) {
        hotKeys.removeAll { $0.id == combo.id }
        if hotKeys.isEmpty {
            hotKeys = [HotKeyCombination(keyCode: 48, modifiers: CGEventFlags.maskAlternate.rawValue)]
        }
        saveHotKeys()
    }

    private static let relevantMask: UInt64 =
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskSecondaryFn.rawValue

    /// Match keyboard hotkey
    func matchesKeyHotKey(keyCode: Int64, flags: CGEventFlags) -> Bool {
        for combo in hotKeys where combo.mouseButton == 0 {
            if Int64(combo.keyCode) == keyCode {
                let comboMods = combo.modifiers & Self.relevantMask
                let activeMods = flags.rawValue & Self.relevantMask
                if comboMods == activeMods { return true }
            }
        }
        return false
    }

    /// Match mouse hotkey (e.g. Option + right click)
    func matchesMouseHotKey(button: Int, flags: CGEventFlags) -> Bool {
        for combo in hotKeys where combo.mouseButton == button {
            let comboMods = combo.modifiers & Self.relevantMask
            let activeMods = flags.rawValue & Self.relevantMask
            if comboMods == activeMods { return true }
        }
        return false
    }
}
