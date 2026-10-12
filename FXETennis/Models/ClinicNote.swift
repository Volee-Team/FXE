import Foundation

/// The private note a player leaves for Tara at Register (decision 0039).
/// Tara, 2026-10-11: "That only I will see so make sure it says only Tara can
/// see this." Who can read it is the database's business (registrations_admin
/// and my_registrations only); this is the box's arithmetic, kept pure so it
/// is unit-tested.
enum ClinicNote {
    /// The server's limit: 300 characters as Postgres counts them, which is
    /// Unicode scalars, not the grapheme clusters Swift's `count` gives (one
    /// family emoji is several scalars).
    static let limit = 300

    /// What gets sent: trimmed, and nil when nothing is left.
    static func cleaned(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The box stops taking characters at the server's limit, dropping whole
    /// characters so an emoji is never cut in half.
    static func limited(_ text: String) -> String {
        guard text.unicodeScalars.count > limit else { return text }
        var out = ""
        var scalars = 0
        for ch in text {
            let n = ch.unicodeScalars.count
            if scalars + n > limit { break }
            out.append(ch)
            scalars += n
        }
        return out
    }

    /// One edit to the box: a typed return ends the note (the keyboard goes)
    /// and is not kept, then the limit. Returns the text to show and whether
    /// she pressed return.
    static func edited(_ text: String) -> (text: String, finished: Bool) {
        let finished = text.contains("\n")
        let flat = finished ? text.replacingOccurrences(of: "\n", with: "") : text
        return (limited(flat), finished)
    }

    /// Whether the clinic page shows the box: before the start, on a clinic
    /// that is not canceled, either beside Register or while she holds a
    /// live spot (You're In!, Player Pool, Response Needed), which is when
    /// the server lets her change it.
    static func offered(status: RegistrationStatus?, door: RegistrationDoor,
                        isCanceled: Bool, startsAt: Date, now: Date) -> Bool {
        if isCanceled || now >= startsAt { return false }
        if let status {
            return status == .in_ || status == .pool || status == .responseNeeded
        }
        if case .register = door { return true }
        return false
    }
}
