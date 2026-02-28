import Foundation

// MARK: - Time Slot

enum TimeSlot: String, Codable, CaseIterable {
    case earlyMorning  // 05-08
    case morning       // 08-11
    case midday        // 11-14
    case afternoon     // 14-17
    case evening       // 17-20
    case night         // 20-23
    case lateNight     // 23-05

    static func current() -> TimeSlot {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<8:   return .earlyMorning
        case 8..<11:  return .morning
        case 11..<14: return .midday
        case 14..<17: return .afternoon
        case 17..<20: return .evening
        case 20..<23: return .night
        default:      return .lateNight  // 23-04
        }
    }

    /// Returns the adjacent time slots (previous and next)
    func adjacentSlots() -> [TimeSlot] {
        let all = TimeSlot.allCases
        guard let idx = all.firstIndex(of: self) else { return [] }
        let prev = all[(idx - 1 + all.count) % all.count]
        let next = all[(idx + 1) % all.count]
        return [prev, next]
    }
}

// MARK: - Usage Record

struct UsageRecord: Codable {
    let bundleId: String
    let timestamp: Date
    let timeSlot: TimeSlot
    let dayOfWeek: Int       // 1=Sun...7=Sat (Calendar weekday)
    let isWeekday: Bool
    let locationLabel: String?  // nil if location unavailable

    init(bundleId: String, timestamp: Date = Date(), locationLabel: String? = nil) {
        self.bundleId = bundleId
        self.timestamp = timestamp
        self.timeSlot = TimeSlot.current()

        let cal = Calendar.current
        self.dayOfWeek = cal.component(.weekday, from: timestamp)
        let wd = cal.component(.weekday, from: timestamp)
        self.isWeekday = (wd >= 2 && wd <= 6)  // Mon-Fri
        self.locationLabel = locationLabel
    }
}
