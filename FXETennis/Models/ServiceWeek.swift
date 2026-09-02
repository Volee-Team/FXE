//
//  ServiceWeek.swift
//  FXETennis
//
//  The service week is Sunday through Saturday in America/New_York, and
//  registration windows hang off it (decision 0001, `service_week_start` in
//  20260802000001). This is the same arithmetic on the client, used only to
//  GROUP the clinic list under "This week" / "Next week" / "Week of …".
//  Nothing here decides whether registration is open; the database does that.
//

import Foundation

enum ServiceWeek {
    static let timeZone = TimeZone(identifier: "America/New_York")!

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 1 // Sunday, matching extract(dow) = 0 in the SQL
        return c
    }

    /// Midnight (New York) on the Sunday that starts the week containing `date`.
    static func start(of date: Date) -> Date {
        let c = calendar
        let day = c.startOfDay(for: date)
        let weekday = c.component(.weekday, from: day) // 1 = Sunday
        return c.date(byAdding: .day, value: -(weekday - 1), to: day)!
    }

    /// "This week", "Next week", or "Week of Sep 13".
    static func label(forWeekStarting start: Date, now: Date = .now) -> String {
        let c = calendar
        let thisWeek = self.start(of: now)
        let weeksAhead = c.dateComponents([.weekOfYear], from: thisWeek, to: start).weekOfYear ?? 0
        switch weeksAhead {
        case 0: return "This week"
        case 1: return "Next week"
        default:
            // Built from nothing, not from `.abbreviated`: a base date style
            // keeps its year even after .month().day() are added.
            let f = Date.FormatStyle(timeZone: timeZone).month(.abbreviated).day()
            return "Week of \(start.formatted(f))"
        }
    }

    /// Clinics grouped by week start, weeks ascending, order within a week
    /// preserved from the input (which the repository already sorts by start).
    static func grouped<T>(_ items: [T], startsAt: (T) -> Date) -> [(start: Date, items: [T])] {
        var buckets: [Date: [T]] = [:]
        for item in items {
            buckets[start(of: startsAt(item)), default: []].append(item)
        }
        return buckets.keys.sorted().map { (start: $0, items: buckets[$0]!) }
    }
}
