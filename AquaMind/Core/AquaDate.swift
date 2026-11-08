import Foundation

/// Consistent Russian formatting regardless of iPhone interface language.
enum AquaDate {
    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    static func heading(_ date: Date, timeZone: TimeZone) -> String {
        formatter("d MMMM, EEEE", timeZone: timeZone).string(from: date)
    }

    static func fullDate(_ date: Date, timeZone: TimeZone) -> String {
        formatter("d MMMM yyyy", timeZone: timeZone).string(from: date)
    }

    static func reminder(_ date: Date, timeZone: TimeZone) -> String {
        formatter("d MMMM, HH:mm", timeZone: timeZone).string(from: date)
    }

    static func time(_ date: Date, timeZone: TimeZone) -> String {
        formatter("HH:mm", timeZone: timeZone).string(from: date)
    }

    static func weekday(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let index = calendar.component(.weekday, from: date) - 1
        return ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"][index]
    }
}
