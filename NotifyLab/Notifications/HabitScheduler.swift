import Foundation
import UserNotifications

struct Habit: Codable, Identifiable, Hashable, Sendable {
    enum Level: String, Codable, CaseIterable, Sendable {
        case passive, active, timeSensitive

        var title: String {
            switch self {
            case .passive: "Passive"
            case .active: "Active"
            case .timeSensitive: "Time-sensitive"
            }
        }

        var interruptionLevel: UNNotificationInterruptionLevel {
            switch self {
            case .passive: .passive
            case .active: .active
            case .timeSensitive: .timeSensitive   // needs the Time Sensitive capability
            }
        }
    }

    var id = UUID()
    var name: String
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>          // Calendar weekdays: 1 = Sunday … 7 = Saturday
    var level: Level = .active

    var timeText: String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    var daysText: String {
        if weekdays.count == 7 { return "Every day" }
        if weekdays == [2, 3, 4, 5, 6] { return "Weekdays" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: " ")
    }
}

struct PendingReminder: Identifiable, Hashable {
    let id: String
    let title: String
    let date: Date?
}

/// Habit reminders with a ROLLING WINDOW instead of repeating triggers.
///
/// Why: iOS keeps at most 64 pending local notifications per app and silently drops the rest.
/// A repeating trigger also can't skip "today" when the habit is already done.
/// So every time the app runs we schedule the next occurrences (up to 14 days, max 60
/// requests), soonest first, and skip today's if the habit is already done.
@MainActor @Observable
final class HabitScheduler {
    static let systemLimit = 64
    static let budget = 60            // leave 4 slots for snoozes and test notifications
    static let windowDays = 14
    private static let prefix = "habit."

    private(set) var habits: [Habit] = []
    private(set) var pending: [PendingReminder] = []
    private(set) var droppedCount = 0
    private var completions: [String: Set<String>] = [:]   // habit id → "yyyy-MM-dd"

    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.current

    init() {
        load()
        if habits.isEmpty {
            habits = [
                Habit(name: "Stretch", hour: 8, minute: 0, weekdays: [2, 3, 4, 5, 6]),
                Habit(name: "Drink water", hour: 11, minute: 30, weekdays: Set(1...7)),
                Habit(name: "Read 10 pages", hour: 21, minute: 30, weekdays: Set(1...7), level: .passive),
            ]
            save()
        }
    }

    // MARK: - Editing

    func add(_ habit: Habit) async {
        habits.append(habit)
        save()
        await replan()
    }

    func delete(_ habit: Habit) async {
        habits.removeAll { $0.id == habit.id }
        completions[habit.id.uuidString] = nil
        save()
        await replan()
    }

    func markDone(_ habitID: UUID) async {
        completions[habitID.uuidString, default: []].insert(dayKey(.now))
        save()
        // Clean up: a reminder for something already done shouldn't sit in Notification Center.
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix("\(Self.prefix)\(habitID)") }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
        await replan()   // also drops today's pending reminder for this habit
    }

    func isDoneToday(_ habit: Habit) -> Bool {
        completions[habit.id.uuidString]?.contains(dayKey(.now)) ?? false
    }

    /// Consecutive days done, counting back from today (or yesterday if today isn't done yet).
    func streak(for habit: Habit) -> Int {
        let done = completions[habit.id.uuidString] ?? []
        var day = isDoneToday(habit) ? Date.now : calendar.date(byAdding: .day, value: -1, to: .now)!
        var count = 0
        while done.contains(dayKey(day)) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    func habit(id: UUID) -> Habit? { habits.first { $0.id == id } }

    // MARK: - Scheduling

    /// Rebuilds all habit reminders. Cheap enough to call on every launch and every change.
    func replan() async {
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.prefix) && !$0.hasSuffix(".snooze") }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        let upcoming = upcomingOccurrences().sorted { $0.date < $1.date }
        let planned = upcoming.prefix(Self.budget)
        droppedCount = upcoming.count - planned.count

        for occurrence in planned {
            try? await center.add(request(for: occurrence.habit, at: occurrence.date))
        }
        await refreshPending()
    }

    func snooze(_ habitID: UUID, minutes: Int = 10) async {
        guard let habit = habit(id: habitID) else { return }
        let content = makeContent(for: habit)
        content.body = "Snoozed reminder. Tap Done when you've finished."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let request = UNNotificationRequest(identifier: "\(Self.prefix)\(habit.id).snooze", content: content, trigger: trigger)
        try? await center.add(request)
        await refreshPending()
    }

    /// Fires a sample in a few seconds, so you can lock the screen and compare the levels.
    func fireTest(level: Habit.Level, after seconds: TimeInterval = 5) async {
        let content = UNMutableNotificationContent()
        content.title = "\(level.title) notification"
        content.body = switch level {
        case .passive: "No sound, no screen wake. Check Notification Center."
        case .active: "The default: sound, banner, lights up the screen."
        case .timeSensitive: "Breaks through Focus if the user allows it."
        }
        content.sound = level == .passive ? nil : .default
        content.interruptionLevel = level.interruptionLevel
        content.categoryIdentifier = CategoryID.habit
        content.threadIdentifier = "tests"
        if let first = habits.first { content.userInfo = [PayloadKey.habitID: first.id.uuidString] }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "test.\(level.rawValue).\(UUID())", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func refreshPending() async {
        pending = await center.pendingNotificationRequests()
            .map { request in
                let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                return PendingReminder(id: request.identifier, title: request.content.title, date: date)
            }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    // MARK: - Private

    private struct Occurrence {
        let habit: Habit
        let date: Date
    }

    private func upcomingOccurrences(from now: Date = .now) -> [Occurrence] {
        let today = calendar.startOfDay(for: now)
        var result: [Occurrence] = []
        for offset in 0..<Self.windowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            for habit in habits where habit.weekdays.contains(weekday) {
                guard let fire = calendar.date(bySettingHour: habit.hour, minute: habit.minute, second: 0, of: day),
                      fire > now else { continue }
                if offset == 0 && isDoneToday(habit) { continue }
                result.append(Occurrence(habit: habit, date: fire))
            }
        }
        return result
    }

    private func request(for habit: Habit, at date: Date) -> UNNotificationRequest {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        // One stable identifier per habit per day: re-adding the same id replaces it.
        let id = "\(Self.prefix)\(habit.id).\(dayKey(date))"
        return UNNotificationRequest(identifier: id, content: makeContent(for: habit), trigger: trigger)
    }

    private func makeContent(for habit: Habit) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = habit.name
        let streak = streak(for: habit)
        content.body = streak > 0
            ? "Keep your \(streak)-day streak going."
            : "Tap Done when you've finished."
        content.sound = habit.level == .passive ? nil : .default
        content.categoryIdentifier = CategoryID.habit      // Done / Snooze / Note buttons
        content.threadIdentifier = "habit-\(habit.id)"     // groups this habit's reminders
        content.interruptionLevel = habit.level.interruptionLevel
        content.relevanceScore = habit.level == .passive ? 0.2 : 0.6   // ordering in Scheduled Summary
        content.userInfo = [PayloadKey.habitID: habit.id.uuidString]
        return content
    }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "habits.v1"),
           let saved = try? JSONDecoder().decode([Habit].self, from: data) {
            habits = saved
        }
        if let data = defaults.data(forKey: "habitCompletions.v1"),
           let saved = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            completions = saved
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(habits), forKey: "habits.v1")
        defaults.set(try? JSONEncoder().encode(completions), forKey: "habitCompletions.v1")
    }
}
