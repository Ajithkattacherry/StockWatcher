import Foundation

/// Helpers for "yyyy-MM-dd" day strings in UTC.
public enum ISODay {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    public static func date(_ string: String) -> Date? {
        let parts = string.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public static func string(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(pad(c.year ?? 0, 4))-\(pad(c.month ?? 0, 2))-\(pad(c.day ?? 0, 2))"
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    public static func days(from start: String, to end: String) -> Int? {
        guard let a = date(start), let b = date(end) else { return nil }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    public static func adding(days: Int, to day: String) -> String? {
        guard let d = date(day) else { return nil }
        return string(d.addingTimeInterval(Double(days) * 86_400))
    }
}
