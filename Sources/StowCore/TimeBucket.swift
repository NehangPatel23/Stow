import Foundation

enum TimeBucket: String, CaseIterable, Sendable, Equatable {
    case today
    case yesterday
    case older

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .older: "Older"
        }
    }

    static func bucket(for date: Date, now: Date, calendar: Calendar = .current) -> TimeBucket {
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday {
            return .today
        }
        if let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
           date >= startOfYesterday {
            return .yesterday
        }
        return .older
    }

    static func fromSearchToken(_ token: String) -> TimeBucket? {
        switch token.lowercased() {
        case "today": .today
        case "yesterday": .yesterday
        case "older": .older
        default: nil
        }
    }
}
