//
//  CancelPolicy.swift
//  FXETennis
//
//  Decision 0010 (Tara, 2026-09-12): "before 4 hours anything can be
//  cancelled but after that you have to say it's an emergency to cancel."
//  The number comes from app_settings.cancel_cutoff_hours; the rule itself is
//  the server's (cancel_registration refuses a late cancel without a note).
//  This is only the app's copy of the question "are we inside it?", so the
//  screen can ask for the note before the tap instead of after the refusal.
//

import Foundation

enum CancelPolicy {
    /// True when the clinic starts in less than `cutoffHours` from `now`,
    /// including a clinic that already started.
    static func isInsideCutoff(startsAt: Date, cutoffHours: Int, now: Date = Date()) -> Bool {
        startsAt.timeIntervalSince(now) < TimeInterval(cutoffHours) * 3600
    }
}
