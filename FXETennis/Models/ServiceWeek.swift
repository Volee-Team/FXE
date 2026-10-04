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

/// Every time the app prints is Charlotte time, wherever the phone is.
/// Tara, 2026-10-04: "The times should not convert to where the phone is. It
/// always needs to be 9 o'clock ... Or whatever time it's at Charlotte time",
/// after a member in Wisconsin saw every clinic an hour early. A clinic is a
/// place on a court in Charlotte, not a moment to convert.
enum ClubTime {
    static let zone = ServiceWeek.timeZone

    /// Makes Charlotte the app's own time zone, so every formatter, every
    /// `.formatted()` and every Calendar.current reads club time. Called once
    /// at launch, before any view exists. Reminders and calendar events are
    /// absolute moments and stay correct either way.
    ///
    /// Both halves are needed. `NSTimeZone.default` moves Calendar and
    /// DateFormatter, but `.formatted()` (most screens) reads the SYSTEM
    /// zone, which ignored it: seen on a simulator launched in Central time,
    /// where the first version of this fix still showed 3:59 PM for a 4:59 PM
    /// clinic. The system zone comes from the process's TZ variable, which is
    /// how the simulator was put in Central in the first place, so setting
    /// TZ to Charlotte before anything reads a zone moves it too.
    static func apply() {
        setenv("TZ", zone.identifier, 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        NSTimeZone.default = zone
    }
}

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
