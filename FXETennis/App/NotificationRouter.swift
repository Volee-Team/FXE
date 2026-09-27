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
import UserNotifications

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
    /// by the bell if its list is on screen, otherwise shown by the sheet at
    /// the root (pushTapRouting), which leaves it here until its screen has
    /// actually appeared. Waits through launch and sign-in.
    private(set) var pendingTap: PushTap?
    /// Someone is signed in (SessionStore.phase). A push that lands while
    /// nobody is shows no banner.
    var signedIn = false
    /// Moves when a push lands while the app is open, when a tapped push
    /// changes what is unread, and when someone answers from a notification's
    /// screen. Home and the bell reload on it.
    private(set) var reloads = 0
    /// The bell's list is on screen. It opens taps itself then, because a
    /// second sheet cannot be presented over it.
    var bellIsOpen = false

    func tapped(_ tap: PushTap) { pendingTap = tap }

    /// What the root does with a tapped push once its lookup has returned.
    enum TapStep: Equatable, Sendable {
        case present        // show it now
        case wait           // another sheet or alert is up; iOS would refuse a second one
        case leaveForBell   // the bell opened meanwhile; it takes the tap
        case drop           // taken elsewhere, or cleared at sign-out
        case markReadOnly   // nothing to open (a note, or a clinic that has ended)
    }

    /// Review, 2026-09-27: the root used to take the tap, mark it read, look
    /// it up and then present, and iOS refuses a sheet while another is up
    /// (the waiver, the card step, a confirmation), so the tap was lost and
    /// already read. Now it waits, re-checks the bell after the lookup, and
    /// is marked read only once its screen appears (`delivered`).
    nonisolated static func step(tapStillPending: Bool, bellIsOpen: Bool,
                                 somethingPresented: Bool, hasDestination: Bool) -> TapStep {
        guard tapStillPending else { return .drop }
        if bellIsOpen { return .leaveForBell }
        guard hasDestination else { return .markReadOnly }
        return somethingPresented ? .wait : .present
    }

    /// A push landing while the app is open: a banner only while someone is
    /// signed in (PushAppDelegate.willPresent).
    nonisolated static func presentationOptions(signedIn: Bool) -> UNNotificationPresentationOptions {
        signedIn ? [.banner, .list, .sound] : []
    }

    func take() -> PushTap? {
        let tap = pendingTap
        pendingTap = nil
        return tap
    }

    func requestReload() { reloads &+= 1 }

    /// Sign-out: a tap meant for this account must not open for the next one.
    func reset() { pendingTap = nil }

    /// The screen a tapped push names, looked up with the caller's grants.
    /// Marks nothing read: that waits until the screen is shown.
    func resolve(_ tap: PushTap, isAdmin: Bool) async -> NotificationDestination? {
        guard let target = tap.target else { return nil }
        return await NotificationResolver.live.destination(for: target, isAdmin: isAdmin)
    }

    /// The tap's screen is on screen, or it had none to open: it is no longer
    /// pending, its row is read, and the icon and Home follow.
    func delivered(_ tap: PushTap) async {
        if pendingTap?.token == tap.token { pendingTap = nil }
        if let id = tap.notificationId { try? await NotificationRepository.markRead(id) }
        await PushRegistrar.shared.syncBadge()
        requestReload()
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
///
/// The tap stays pending in the router until its screen has appeared
/// (review, 2026-09-27). While another sheet or alert is up, iOS refuses a
/// second presentation, so this waits and looks again every 0.7 seconds; if
/// the bell opens meanwhile, the bell takes it. Nothing is marked read until
/// the sheet's content appears.
private struct PushTapRouting: ViewModifier {
    @Environment(SessionStore.self) private var session
    @State private var destination: NotificationDestination?
    /// The tap whose screen `destination` holds, until that screen appears.
    @State private var showing: PushTap?
    private let router = NotificationRouter.shared

    private struct Trigger: Equatable {
        let tap: UUID?
        let bellIsOpen: Bool
    }

    func body(content: Content) -> some View {
        content
            // Keyed on the pending tap: `delivered` clears it, which ends this
            // task; the bell opening restarts it, and it steps aside.
            .task(id: Trigger(tap: router.pendingTap?.token, bellIsOpen: router.bellIsOpen)) {
                guard !router.bellIsOpen, let tap = router.pendingTap else { return }
                let found = await router.resolve(tap, isAdmin: session.account?.isAdmin == true)
                while !Task.isCancelled {
                    let step = NotificationRouter.step(
                        tapStillPending: router.pendingTap?.token == tap.token,
                        bellIsOpen: router.bellIsOpen,
                        somethingPresented: Self.somethingIsPresented,
                        hasDestination: found != nil)
                    switch step {
                    case .drop, .leaveForBell:
                        return
                    case .markReadOnly:
                        await router.delivered(tap)
                        return
                    case .present:
                        if destination == nil {
                            showing = tap
                            destination = found
                        } else {
                            // An earlier attempt iOS refused: clear it, then
                            // present again on the next look.
                            destination = nil
                        }
                    case .wait:
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(700))
                }
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
                .onAppear {
                    guard let tap = showing else { return }
                    showing = nil
                    Task { await router.delivered(tap) }
                }
            }
    }

    /// Whether the key window already presents something (a sheet, a
    /// confirmation, Stripe's card sheet, this modifier's own sheet).
    private static var somethingIsPresented: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
    }
}

extension View {
    /// Tapped pushes open their clinic in a sheet (decision 0008, client half).
    func pushTapRouting() -> some View { modifier(PushTapRouting()) }
}
