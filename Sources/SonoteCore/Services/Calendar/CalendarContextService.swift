import Foundation
import EventKit

public struct CalendarMeetingContext: Identifiable, Equatable, Sendable {
    public var id: String { "\(title)|\(Int(startDate.timeIntervalSince1970))" }
    public var title: String
    public var attendees: [String]
    public var startDate: Date
    public var endDate: Date

    public init(title: String, attendees: [String], startDate: Date, endDate: Date) {
        self.title = title
        self.attendees = attendees
        self.startDate = startDate
        self.endDate = endDate
    }

    public var isInProgressNow: Bool {
        let now = Date()
        return startDate <= now && endDate >= now
    }

    public var formattedTimeRange: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return "\(df.string(from: startDate))–\(df.string(from: endDate))"
    }

    public var asrHotwordHint: String {
        var terms: [String] = []
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty { terms.append(cleanTitle) }
        terms.append(contentsOf: attendees.prefix(15))
        return terms.joined(separator: ", ")
    }
}

/// Reads active or imminent macOS Calendar events (EventKit) to auto-name meetings
/// and inject attendee names as hotwords into Qwen3-ASR.
public final class CalendarContextService: @unchecked Sendable {
    public static let shared = CalendarContextService()

    private let store = EKEventStore()

    public init() {}

    public func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    public func isAuthorized() -> Bool {
        authorizationStatus() == .fullAccess
    }

    public func requestAccessIfNeeded() async -> Bool {
        if isAuthorized() { return true }
        let status = authorizationStatus()
        guard status == .notDetermined else { return false }

        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    /// Finds an active or starting-within-15-min non-all-day calendar event around `date`.
    public func currentMeetingContext(at date: Date = Date()) -> CalendarMeetingContext? {
        guard isAuthorized() else { return nil }

        let windowStart = date.addingTimeInterval(-15 * 60)
        let windowEnd = date.addingTimeInterval(15 * 60)
        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && !($0.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }

        guard !events.isEmpty else { return nil }

        // Prefer an event currently in progress; otherwise closest upcoming within 15 min
        let chosen = events.first(where: { $0.startDate <= date && $0.endDate >= date })
            ?? events.min(by: { abs($0.startDate.timeIntervalSince(date)) < abs($1.startDate.timeIntervalSince(date)) })

        guard let event = chosen, let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        var attendeeNames: [String] = []
        if let attendees = event.attendees {
            for person in attendees {
                if let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty,
                   !name.contains("@"),
                   !attendeeNames.contains(name) {
                    attendeeNames.append(name)
                }
            }
        }

        return CalendarMeetingContext(
            title: title,
            attendees: attendeeNames,
            startDate: event.startDate,
            endDate: event.endDate
        )
    }

    /// Returns currently active and upcoming non-all-day meetings remaining today (sorted chronologically).
    public func upcomingTodayEvents(from date: Date = Date(), limit: Int = 3) -> [CalendarMeetingContext] {
        guard isAuthorized(), limit > 0 else { return [] }
        let cal = Calendar.current
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date.addingTimeInterval(12 * 3600)
        let windowStart = date.addingTimeInterval(-30 * 60)
        let predicate = store.predicateForEvents(withStart: windowStart, end: endOfDay, calendars: nil)

        let rawEvents = store.events(matching: predicate)
            .filter { event in
                !event.isAllDay
                    && event.endDate > date
                    && !(event.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            .sorted { $0.startDate < $1.startDate }

        var results: [CalendarMeetingContext] = []
        var seenIDs: Set<String> = []
        for event in rawEvents {
            guard let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { continue }
            var attendeeNames: [String] = []
            if let attendees = event.attendees {
                for person in attendees {
                    if let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !name.isEmpty,
                       !name.contains("@"),
                       !attendeeNames.contains(name) {
                        attendeeNames.append(name)
                    }
                }
            }
            let ctx = CalendarMeetingContext(
                title: title,
                attendees: attendeeNames,
                startDate: event.startDate,
                endDate: event.endDate
            )
            if seenIDs.insert(ctx.id).inserted {
                results.append(ctx)
                if results.count >= limit { break }
            }
        }
        return results
    }

    // MARK: - Apple Reminders Sync (EventKit)

    public func isRemindersAuthorized() -> Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    public func requestRemindersAccessIfNeeded() async -> Bool {
        if isRemindersAuthorized() { return true }
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .notDetermined else { return false }
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    /// Exports one or more meeting action items into the user's default Apple Reminders list.
    public func exportActionItemsToReminders(
        _ items: [(meetingTitle: String, item: ActionItem)]
    ) async throws -> Int {
        guard !items.isEmpty else { return 0 }
        let granted = await requestRemindersAccessIfNeeded()
        guard granted else {
            throw NSError(
                domain: "Sonote.Reminders",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "未获得 macOS「提醒事项」权限。请在「系统设置 → 隐私与安全性 → 提醒事项」中允许「Sonote」。"]
            )
        }
        guard let targetCalendar = store.defaultCalendarForNewReminders() else {
            throw NSError(
                domain: "Sonote.Reminders",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "未找到默认的「提醒事项」列表。"]
            )
        }

        var exported = 0
        for entry in items where !entry.item.isCompleted {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = targetCalendar
            let ownerPrefix = (!entry.item.owner.isEmpty && entry.item.owner != "待定") ? "[\(entry.item.owner)] " : ""
            reminder.title = "\(ownerPrefix)\(entry.item.task)"
            var notes = ["来自 Sonote（声记）：\(entry.meetingTitle)"]
            if !entry.item.dueDate.isEmpty {
                notes.append("截止时间：\(entry.item.dueDate)")
            }
            reminder.notes = notes.joined(separator: "\n")
            try store.save(reminder, commit: false)
            exported += 1
        }
        if exported > 0 {
            try store.commit()
        }
        return exported
    }
}
