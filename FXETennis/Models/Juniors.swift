//
//  Juniors.swift
//  FXETennis
//
//  Juniors phase 1 (decision 0061): a parent's children, the waiver signed
//  for each child, Tara's programs, and Elite approvals. The server decides
//  everything (20261118000001 and 000002); these types only carry its answers
//  and turn its refusals into one plain line each.
//
//  Phase 0's rule (decision 0057) stands: a child is never the session's
//  activePlayer. Children come only from my_children(), never from
//  myPlayers(), which the server keeps adults-only.
//
//  Nothing here books a child into anything: that is phase 2.
//

import Foundation

/// One of the parent's children, as `my_children()` returns it.
struct Child: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    /// Postgres `date`, "yyyy-MM-dd". Kept as the string the server sent:
    /// turning a date-only value into a Date and back moves it a day in some
    /// time zones.
    let dateOfBirth: String
    let age: Int?
    let waiverStatus: ChildWaiverStatus

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    enum CodingKeys: String, CodingKey {
        case id, age
        case firstName = "first_name"
        case lastName = "last_name"
        case dateOfBirth = "date_of_birth"
        case waiverStatus = "waiver_status"
    }

    init(id: UUID, firstName: String, lastName: String, dateOfBirth: String, age: Int?, waiverStatus: ChildWaiverStatus) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.age = age
        self.waiverStatus = waiverStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        dateOfBirth = try c.decodeIfPresent(String.self, forKey: .dateOfBirth) ?? ""
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        let raw = try c.decodeIfPresent(String.self, forKey: .waiverStatus) ?? ""
        waiverStatus = ChildWaiverStatus(rawValue: raw) ?? .notAvailable
    }
}

/// `my_children().waiver_status` / `child_waiver_status()`.
enum ChildWaiverStatus: String, Codable, Sendable {
    /// No parent/guardian text is published yet (decision 0061).
    case notAvailable = "not_available"
    /// A text is published and this child has no signature on it.
    case needed
    /// Signed on the current text.
    case signed
}

/// One of Tara's programs, as `list_junior_programs()` returns it.
struct JuniorProgram: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let ageGuidance: String
    let needsApproval: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case ageGuidance = "age_guidance"
        case needsApproval = "needs_approval"
        case sortOrder = "sort_order"
    }

    init(id: UUID, name: String, description: String, ageGuidance: String, needsApproval: Bool, sortOrder: Int) {
        self.id = id
        self.name = name
        self.description = description
        self.ageGuidance = ageGuidance
        self.needsApproval = needsApproval
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        ageGuidance = try c.decodeIfPresent(String.self, forKey: .ageGuidance) ?? ""
        needsApproval = try c.decodeIfPresent(Bool.self, forKey: .needsApproval) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

/// One row of `my_program_approvals()`.
struct ProgramApproval: Codable, Hashable, Sendable {
    let playerId: UUID
    let programId: UUID
    let status: ProgramApprovalStatus

    enum CodingKeys: String, CodingKey {
        case status
        case playerId = "player_id"
        case programId = "program_id"
    }

    init(playerId: UUID, programId: UUID, status: ProgramApprovalStatus) {
        self.playerId = playerId
        self.programId = programId
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(UUID.self, forKey: .playerId)
        programId = try c.decode(UUID.self, forKey: .programId)
        let raw = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        status = ProgramApprovalStatus(rawValue: raw) ?? .requested
    }
}

enum ProgramApprovalStatus: String, Codable, Sendable {
    case requested, approved, declined
}

/// What a child's page shows for one program.
enum ProgramApprovalState: Equatable {
    /// The program needs no approval: nothing to ask.
    case notNeeded
    /// Needs approval, not asked yet: Request Approval.
    case canRequest
    case requested
    case approved
    case declined

    static func state(program: JuniorProgram, child: UUID, approvals: [ProgramApproval]) -> ProgramApprovalState {
        guard program.needsApproval else { return .notNeeded }
        guard let row = approvals.first(where: { $0.playerId == child && $0.programId == program.id }) else {
            return .canRequest
        }
        switch row.status {
        case .requested: return .requested
        case .approved: return .approved
        case .declined: return .declined
        }
    }
}

/// The words on the juniors screens that are not field labels. Listed for
/// John's sign-off in docs/juniors/copy-for-john-phase1-app.md (hard rule 13).
enum JuniorCopy {
    // Refusals from the server, one plain line each.
    static let childExistsLine = "This child is already on your account."
    static let nameRequiredLine = "Add a first and last name."
    static let invalidBirthdayLine = "Pick a birthday in the past."
    static let notYourChildLine = "Couldn't find this child on your account."
    static let childHasUpcomingLine = "This child has a spot coming up, so they can't be removed yet. Contact Tara."
    static let childLockedLine = "Only Tara can change this child's name or birthday now. Contact Tara."
    static let tooManyChildrenLine = "You can add up to 10 children."
    static let approvalDeclinedLine = "Tara didn't approve this request. Contact Tara."
    static let approvalNotNeededLine = "This program doesn't need approval."
    static let programNotFoundLine = "This program isn't available anymore."
    static let waiverNotAvailableLine = "The waiver for children isn't available yet."
    static let saveFailedLine = "That didn't save. Check your connection and try again."
    static let loadFailedLine = "Couldn't load your children."
    static let programsLoadFailedLine = "Couldn't load the programs."

    // Statuses on a child's row and page.
    static let waiverSignedLine = "Waiver signed"
    static let waiverNeededLine = "Waiver needed"
    static let waiverNotAvailableShortLine = "Waiver not available yet"
    static let approvalRequestedLine = "Approval requested"
    static let approvedLine = "Approved"
    static let notApprovedLine = "Not approved"
    static let editChildLine = "Edit Child"

    /// The server's refusal codes these screens know, in the order they are
    /// checked. The code is the exception's message (`raise exception
    /// 'child_locked'`), which PostgREST returns as the error message.
    static let refusals: [(code: String, line: String)] = [
        ("child_exists", childExistsLine),
        ("name_required", nameRequiredLine),
        ("invalid_birthday", invalidBirthdayLine),
        ("not_your_child", notYourChildLine),
        ("child_has_upcoming", childHasUpcomingLine),
        ("child_locked", childLockedLine),
        ("too_many_children", tooManyChildrenLine),
        ("approval_declined", approvalDeclinedLine),
        ("approval_not_needed", approvalNotNeededLine),
        ("program_not_found", programNotFoundLine),
        ("junior_waiver_not_available", waiverNotAvailableLine),
    ]

    /// The line for a refusal code found in an error's text, or nil.
    static func refusalLine(in text: String) -> String? {
        refusals.first { text.contains($0.code) }?.line
    }

    /// One line for any failure: a known refusal, then no signal, then the
    /// screen's own fallback.
    static func line(for error: Error, fallback: String = saveFailedLine) -> String? {
        let failure = RequestFailure(error)
        if failure == .cancelled { return nil }
        if failure == .other, let line = refusalLine(in: String(describing: error)) { return line }
        return failure.line ?? fallback
    }

    static func waiverLine(_ status: ChildWaiverStatus) -> String {
        switch status {
        case .signed: return waiverSignedLine
        case .needed: return waiverNeededLine
        case .notAvailable: return waiverNotAvailableShortLine
        }
    }

    static func approvalLine(_ state: ProgramApprovalState) -> String? {
        switch state {
        case .notNeeded, .canRequest: return nil
        case .requested: return approvalRequestedLine
        case .approved: return approvedLine
        case .declined: return notApprovedLine
        }
    }

    /// The date-only string the server takes, "yyyy-MM-dd", read on the
    /// phone's own calendar day (a birthday has no time zone).
    static func dateOnly(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The server's "yyyy-MM-dd" as a Date at noon on that day, for the
    /// picker (noon so no time zone can move it to another day).
    static func date(fromDateOnly s: String, calendar: Calendar = .current) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// "March 1, 2017", for a child's birthday line.
    static func birthdayLine(_ s: String) -> String {
        guard let d = date(fromDateOnly: s) else { return s }
        return d.formatted(.dateTime.month(.wide).day().year())
    }
}
