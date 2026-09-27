//
//  NotificationRouter.swift
//  FXETennis
//
//  Where a notification goes when it is tapped, in the bell or on the lock
//  screen. One resolver serves both (MVP audit item 12, 2026-09-27).
//
//  Every notification row names what it is about in two columns, written by
//  the RPC that caused it: entity_type 'clinic' with a clinic id, or
//  'registration' with a registration id (invite_from_pool,
//  respond_to_invitation, cancel_registration). The bell used to open only
//  'clinic', so the row a player most needs to act on, "A spot opened in ...
//  Accept or decline.", was marked read and opened nothing.
//  tests/sql/notification_targets.sql pins that every producer names one of
//  these two, and that each resolves with the recipient's own grants:
//
//    a player  registration -> my_registrations -> clinics_public -> ClinicDetailView
//    Tara      registration -> registrations_admin -> clinics_admin -> AdminClinicDetailView
//
//  Tara's rows are about other people (a cancellation, an accept, a decline,
//  a late request), so they open her page for that clinic, where she acts on
//  them. A registration is looked up as the caller's own first, so an admin
//  who also plays still lands on her own invitation. Nothing here decides
//  anything: it opens the screen where the person decides.
//

import SwiftUI
import Supabase

// MARK: - What a notification is about

/// A notification's entity_type and entity_id, as one of the two kinds the
/// app opens. Anything else is a note with nowhere to go.
enum NotificationTarget: Equatable, Sendable {
    case clinic(UUID)
    case registration(UUID)

    init?(entityType: String?, entityId: UUID?) {
        guard let entityId else { return nil }
        switch entityType {
        case "clinic": self = .clinic(entityId)
        case "registration": self = .registration(entityId)
        default: return nil
        }
    }
}

/// A tapped push, read from the payload supabase/functions/push/index.ts
/// builds: `notification_id`, `type`, `entity_type` and `entity_id` beside
/// `aps`. A JSON null arrives as NSNull and reads as nil here.
struct PushTap: Equatable, Sendable {
    /// Each tap is its own event, even a second tap on the same push.
    let token = UUID()
    let notificationId: UUID?
    let target: NotificationTarget?

    init(userInfo: [AnyHashable: Any]) {
        func uuid(_ key: String) -> UUID? { (userInfo[key] as? String).flatMap(UUID.init(uuidString:)) }
        notificationId = uuid("notification_id")
        target = NotificationTarget(entityType: userInfo["entity_type"] as? String, entityId: uuid("entity_id"))
    }
}

/// The screen a tap opens.
enum NotificationDestination: Identifiable, Hashable {
    case playerClinic(ClinicPublic)
    case adminClinic(ClinicAdmin)

    var id: UUID {
        switch self {
        case .playerClinic(let clinic): return clinic.id
        case .adminClinic(let clinic): return clinic.id
        }
    }

    private var isAdmin: Bool {
        if case .adminClinic = self { return true }
        return false
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.isAdmin == b.isAdmin }
    func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(isAdmin) }
}

// MARK: - The one resolver

/// Turns a target into a screen with the caller's own grants. The four reads
/// are parameters so the choice of branch is unit-tested without a network
/// (FXETennisTests/NotificationRoutingTests.swift); `.live` is the app's.
struct NotificationResolver: Sendable {
    /// The clinic behind one of the caller's own registrations (my_registrations).
    var myRegistrationClinic: @Sendable (UUID) async throws -> UUID?
    /// The clinic behind anyone's registration; answers only an admin (registrations_admin).
    var rosterRegistrationClinic: @Sendable (UUID) async throws -> UUID?
    /// A clinic as a player sees it; nil once it has ended (clinics_public).
    var publicClinic: @Sendable (UUID) async throws -> ClinicPublic?
    /// A clinic as Tara sees it (clinics_admin).
    var adminClinic: @Sendable (UUID) async throws -> ClinicAdmin?

    func destination(for target: NotificationTarget, isAdmin: Bool) async -> NotificationDestination? {
        switch target {
        case .clinic(let id):
            if isAdmin {
                guard let clinic = try? await adminClinic(id) else { return nil }
                return .adminClinic(clinic)
            }
            guard let clinic = try? await publicClinic(id) else { return nil }
            return .playerClinic(clinic)

        case .registration(let id):
            // The caller's own first: an invitation, an answer, a cancellation.
            if let clinicId = try? await myRegistrationClinic(id) {
                guard let clinic = try? await publicClinic(clinicId) else { return nil }
                return .playerClinic(clinic)
            }
            // Someone else's registration only ever reaches an admin. A
            // player never asks the roster; it would answer nothing anyway.
            guard isAdmin,
                  let clinicId = try? await rosterRegistrationClinic(id),
                  let clinic = try? await adminClinic(clinicId) else { return nil }
            return .adminClinic(clinic)
        }
    }
}

extension NotificationResolver {
    static let live = NotificationResolver(
        myRegistrationClinic: { try await RegistrationRepository.myRegistrationClinicId($0) },
        rosterRegistrationClinic: { try await AdminRepository.rosterRegistrationClinicId($0) },
        publicClinic: { try await ClinicRepository.clinic(id: $0) },
        adminClinic: { try await AdminRepository.adminClinic(id: $0) }
    )
}

// MARK: - The reads it needs

private struct ClinicIdRow: Decodable {
    let clinicId: UUID
    enum CodingKeys: String, CodingKey { case clinicId = "clinic_id" }
}

extension RegistrationRepository {
    /// The clinic of one of MY registrations, or nil when it is not mine:
    /// my_registrations is scoped by owns_player, admins included.
    static func myRegistrationClinicId(_ id: UUID) async throws -> UUID? {
        let rows: [ClinicIdRow] = try await supabase
            .from("my_registrations")
            .select("clinic_id")
            .eq("id", value: id)
            .execute()
            .value
        return rows.first?.clinicId
    }
}

extension AdminRepository {
    /// The clinic of any registration, for Tara. Zero rows to a non-admin.
    static func rosterRegistrationClinicId(_ id: UUID) async throws -> UUID? {
        let rows: [ClinicIdRow] = try await supabase
            .from("registrations_admin")
            .select("clinic_id")
            .eq("id", value: id)
            .execute()
            .value
        return rows.first?.clinicId
    }

    /// One clinic as Tara sees it, ended ones included. Zero rows to a non-admin.
    static func adminClinic(id: UUID) async throws -> ClinicAdmin? {
        let rows: [ClinicAdmin] = try await supabase
            .from("clinics_admin")
            .select("id,name,audience,category,starts_at,ends_at,status,internal_capacity,member_price_cents,nonmember_price_cents")
            .eq("id", value: id)
            .execute()
            .value
        return rows.first
    }
}

// MARK: - Shared state between the push delegate and the screens

@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    private init() {}

    /// A tapped push no screen has opened yet. Set by PushAppDelegate; taken
    /// by the bell if its list is on screen, otherwise by the sheet at the
    /// root (pushTapRouting). Waits there through launch and sign-in.
    private(set) var pendingTap: PushTap?
    /// Moves when a push lands while the app is open, when a tapped push
    /// changes what is unread, and when someone answers from a notification's
    /// screen. Home and the bell reload on it.
    private(set) var reloads = 0
    /// The bell's list is on screen. It opens taps itself then, because a
    /// second sheet cannot be presented over it.
    var bellIsOpen = false

    func tapped(_ tap: PushTap) { pendingTap = tap }

    func take() -> PushTap? {
        let tap = pendingTap
        pendingTap = nil
        return tap
    }

    func requestReload() { reloads &+= 1 }

    /// Sign-out: a tap meant for this account must not open for the next one.
    func reset() { pendingTap = nil }

    /// A tapped push: its row is read now, so the icon and Home follow, then
    /// the screen it names.
    func open(_ tap: PushTap, isAdmin: Bool) async -> NotificationDestination? {
        if let id = tap.notificationId { try? await NotificationRepository.markRead(id) }
        await PushRegistrar.shared.syncBadge()
        requestReload()
        guard let target = tap.target else { return nil }
        return await NotificationResolver.live.destination(for: target, isAdmin: isAdmin)
    }
}

// MARK: - The screens

/// What a resolved notification shows: the player's clinic page, or Tara's.
/// Used by the bell (pushed on its stack) and by a tapped push (in a sheet).
struct NotificationDestinationView: View {
    @Environment(SessionStore.self) private var session
    let destination: NotificationDestination

    var body: some View {
        switch destination {
        case .playerClinic(let clinic):
            ClinicDetailView(clinic: clinic, isMember: session.activePlayer?.isMember ?? false,
                             onChanged: { @MainActor in NotificationRouter.shared.requestReload() })
        case .adminClinic(let clinic):
            AdminClinicDetailView(clinic: clinic,
                                  onChanged: { @MainActor in NotificationRouter.shared.requestReload() })
        }
    }
}

/// Opens a tapped push over whatever is showing, once signed in. Applied in
/// RootView; the bell handles taps itself while its list is open.
private struct PushTapRouting: ViewModifier {
    @Environment(SessionStore.self) private var session
    @State private var destination: NotificationDestination?
    private let router = NotificationRouter.shared

    private struct Trigger: Equatable {
        let tap: UUID?
        let bellIsOpen: Bool
    }

    func body(content: Content) -> some View {
        content
            // Initial: a tap that launched the app is waiting before this view
            // exists. onChange rather than task(id:): take() changes the
            // trigger, and a task keyed on it would cancel its own work.
            .onChange(of: Trigger(tap: router.pendingTap?.token, bellIsOpen: router.bellIsOpen), initial: true) {
                guard !router.bellIsOpen, let tap = router.take() else { return }
                let isAdmin = session.account?.isAdmin == true
                Task { destination = await router.open(tap, isAdmin: isAdmin) }
            }
            .sheet(item: $destination) { shown in
                NavigationStack {
                    NotificationDestinationView(destination: shown)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { destination = nil }
                                    .accessibilityIdentifier("push.done")
                            }
                        }
                }
            }
    }
}

extension View {
    /// Tapped pushes open their clinic in a sheet (decision 0008, client half).
    func pushTapRouting() -> some View { modifier(PushTapRouting()) }
}
