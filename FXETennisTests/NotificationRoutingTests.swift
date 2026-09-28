//
//  NotificationRoutingTests.swift
//  FXETennisTests
//
//  Where a tapped notification goes (MVP audit item 12). Expected values from
//  the rule, not the code:
//
//    'clinic'        opens that clinic: the player's page, or Tara's page
//    'registration'  opens the clinic behind it: the caller's own
//                    registration first (my_registrations), and only an
//                    admin falls back to the roster (registrations_admin)
//    anything else, or no id: stays a note
//
//  The push payload is the one supabase/functions/push/index.ts:73-79 builds,
//  typed out here as JSON so a change on either side shows up as a failure.
//

import XCTest
import UserNotifications
@testable import FXETennis

final class NotificationRoutingTests: XCTestCase {

    private let clinicId = UUID(uuidString: "d0000000-0000-0000-0000-000000000005")!
    private let registrationId = UUID(uuidString: "e0000000-0000-0000-0000-000000000001")!
    private let notificationId = UUID(uuidString: "f0000000-0000-0000-0000-000000000001")!

    // MARK: - the payload

    private func userInfo(_ json: String) -> [AnyHashable: Any] {
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8))
        return (object as? [String: Any]) ?? [:]
    }

    func testTheInvitationPayloadNamesItsRegistration() {
        let tap = PushTap(userInfo: userInfo("""
        {"aps": {"alert": {"body": "A spot opened in Evening Coed. Accept or decline."}, "sound": "default", "badge": 2},
         "notification_id": "f0000000-0000-0000-0000-000000000001",
         "type": "invitation_received",
         "entity_type": "registration",
         "entity_id": "e0000000-0000-0000-0000-000000000001"}
        """))
        XCTAssertEqual(tap.notificationId, notificationId)
        XCTAssertEqual(tap.target, .registration(registrationId))
    }

    func testAClinicPayloadNamesItsClinic() {
        let tap = PushTap(userInfo: userInfo("""
        {"aps": {"alert": {"body": "Courts are wet."}, "sound": "default", "badge": 1},
         "notification_id": "f0000000-0000-0000-0000-000000000001",
         "type": "clinic_message", "entity_type": "clinic",
         "entity_id": "d0000000-0000-0000-0000-000000000005"}
        """))
        XCTAssertEqual(tap.target, .clinic(clinicId))
    }

    /// A row with no entity sends JSON nulls; the tap still names its row so
    /// it can be marked read, and opens nothing.
    func testNullsAreANoteNotACrash() {
        let tap = PushTap(userInfo: userInfo("""
        {"aps": {"alert": {"body": "x"}}, "notification_id": "f0000000-0000-0000-0000-000000000001",
         "type": "push_test", "entity_type": null, "entity_id": null}
        """))
        XCTAssertEqual(tap.notificationId, notificationId)
        XCTAssertNil(tap.target)
    }

    func testAnEntityTheAppDoesNotKnowIsANote() {
        XCTAssertNil(NotificationTarget(entityType: "payment", entityId: registrationId))
        XCTAssertNil(NotificationTarget(entityType: "registration", entityId: nil))
        XCTAssertNil(NotificationTarget(entityType: nil, entityId: registrationId))
    }

    /// The file the lead pushes to the simulator parses to the seeded row.
    /// Skipped where the test process cannot read the repository.
    func testTheSimctlPayloadFileIsTheSeededInvitation() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/push/simctl-invitation.apns")
        guard let data = try? Data(contentsOf: file),
              let info = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XCTSkip("tests/push/simctl-invitation.apns is not readable from here")
        }
        let tap = PushTap(userInfo: info)
        XCTAssertEqual(tap.notificationId, notificationId)
        XCTAssertEqual(tap.target, .registration(registrationId))
    }

    // MARK: - the resolver

    /// Records which reads a resolution made, so a test can assert a player
    /// never asks the admin views.
    private final class Reads: @unchecked Sendable {
        var mine = 0, roster = 0, publicClinic = 0, adminClinic = 0
    }

    private func clinicPublic() -> ClinicPublic {
        let starts = Date(timeIntervalSince1970: 1_790_000_000)
        return ClinicPublic(id: clinicId, name: "Evening Coed", audience: "coed", category: "Clinic",
                            description: nil, startsAt: starts, endsAt: starts.addingTimeInterval(3600),
                            memberOpensAt: nil, publicOpensAt: nil, closesAt: nil, status: "published",
                            canceledAt: nil, memberPriceCents: 1800, nonmemberPriceCents: 2300,
                            durationMinutes: 60)
    }

    private func clinicAdmin() -> ClinicAdmin {
        let starts = Date(timeIntervalSince1970: 1_790_000_000)
        return ClinicAdmin(id: clinicId, name: "Evening Coed", audience: "coed", category: "Clinic",
                           startsAt: starts, endsAt: starts.addingTimeInterval(3600), status: "published",
                           internalCapacity: 8, memberPriceCents: 1800, nonmemberPriceCents: 2300)
    }

    /// `mine` / `roster`: what my_registrations and registrations_admin answer
    /// for the registration id. `ended`: clinics_public has dropped the clinic.
    private func resolver(mine: UUID?, roster: UUID?, ended: Bool = false, reads: Reads) -> NotificationResolver {
        let pub = clinicPublic(), adm = clinicAdmin(), known = clinicId
        return NotificationResolver(
            myRegistrationClinic: { _ in reads.mine += 1; return mine },
            rosterRegistrationClinic: { _ in reads.roster += 1; return roster },
            publicClinic: { id in reads.publicClinic += 1; return (id == known && !ended) ? pub : nil },
            adminClinic: { id in reads.adminClinic += 1; return id == known ? adm : nil }
        )
    }

    func testAPlayersInvitationOpensHerClinicPage() async {
        let reads = Reads()
        let shown = await resolver(mine: clinicId, roster: nil, reads: reads)
            .destination(for: .registration(registrationId), isAdmin: false)
        XCTAssertEqual(shown, .playerClinic(clinicPublic()))
        XCTAssertEqual(reads.roster, 0, "A player must never ask registrations_admin")
        XCTAssertEqual(reads.adminClinic, 0, "A player must never ask clinics_admin")
    }

    func testTaraOpensSomeoneElsesRegistrationOnHerPage() async {
        let reads = Reads()
        let shown = await resolver(mine: nil, roster: clinicId, reads: reads)
            .destination(for: .registration(registrationId), isAdmin: true)
        XCTAssertEqual(shown, .adminClinic(clinicAdmin()))
        XCTAssertEqual(reads.mine, 1, "Her own registrations are asked first")
    }

    func testAnAdminsOwnRegistrationOpensThePlayerPage() async {
        let reads = Reads()
        let shown = await resolver(mine: clinicId, roster: clinicId, reads: reads)
            .destination(for: .registration(registrationId), isAdmin: true)
        XCTAssertEqual(shown, .playerClinic(clinicPublic()))
        XCTAssertEqual(reads.roster, 0)
    }

    func testAPlayerWithSomeoneElsesRegistrationGetsNothing() async {
        let reads = Reads()
        let shown = await resolver(mine: nil, roster: clinicId, reads: reads)
            .destination(for: .registration(registrationId), isAdmin: false)
        XCTAssertNil(shown)
        XCTAssertEqual(reads.roster, 0)
    }

    func testAClinicOpensThePageForWhoeverAsks() async {
        let reads = Reads()
        let player = await resolver(mine: nil, roster: nil, reads: reads)
            .destination(for: .clinic(clinicId), isAdmin: false)
        XCTAssertEqual(player, .playerClinic(clinicPublic()))
        let tara = await resolver(mine: nil, roster: nil, reads: reads)
            .destination(for: .clinic(clinicId), isAdmin: true)
        XCTAssertEqual(tara, .adminClinic(clinicAdmin()))
        XCTAssertEqual(reads.mine + reads.roster, 0, "A clinic needs no registration lookup")
    }

    func testAnEndedClinicStaysANote() async {
        let reads = Reads()
        let viaRegistration = await resolver(mine: clinicId, roster: nil, ended: true, reads: reads)
            .destination(for: .registration(registrationId), isAdmin: false)
        let viaClinic = await resolver(mine: nil, roster: nil, ended: true, reads: reads)
            .destination(for: .clinic(clinicId), isAdmin: false)
        XCTAssertNil(viaRegistration)
        XCTAssertNil(viaClinic)
    }

    /// The bell's navigation and the push sheet key on this identity: the same
    /// clinic as a player page and as Tara's page are different screens.
    func testDestinationsCompareByClinicAndSide() {
        XCTAssertEqual(NotificationDestination.playerClinic(clinicPublic()), .playerClinic(clinicPublic()))
        XCTAssertNotEqual(NotificationDestination.playerClinic(clinicPublic()), .adminClinic(clinicAdmin()))
        XCTAssertEqual(NotificationDestination.adminClinic(clinicAdmin()).id, clinicId)
    }

    // MARK: - a push while the app is open, and a tapped push (review, 2026-09-27)

    /// The rule: a banner shows only while someone is signed in. On a shared
    /// phone, a push that lands after sign-out must not show the previous
    /// account's words.
    func testNoBannerWhileSignedOut() {
        XCTAssertEqual(NotificationRouter.presentationOptions(signedIn: false), [])
        XCTAssertEqual(NotificationRouter.presentationOptions(signedIn: true), [.banner, .list, .sound])
    }

    /// The rule: a tapped push stays pending until its screen is on screen.
    /// Only then is it marked read.
    func testATapIsShownOnlyWhenNothingElseIsPresented() {
        XCTAssertEqual(NotificationRouter.step(tapStillPending: true, bellIsOpen: false,
                                               somethingPresented: false, hasDestination: true), .present)
        XCTAssertEqual(NotificationRouter.step(tapStillPending: true, bellIsOpen: false,
                                               somethingPresented: true, hasDestination: true), .wait,
                       "another sheet is up: iOS would refuse the presentation and the tap would be lost")
    }

    func testTheBellOpeningDuringTheLookupTakesTheTap() {
        XCTAssertEqual(NotificationRouter.step(tapStillPending: true, bellIsOpen: true,
                                               somethingPresented: true, hasDestination: true), .leaveForBell)
    }

    func testATapTakenElsewhereIsNotShownTwice() {
        // The bell took it, or sign-out cleared it.
        XCTAssertEqual(NotificationRouter.step(tapStillPending: false, bellIsOpen: false,
                                               somethingPresented: false, hasDestination: true), .drop)
    }

    func testATapWithNowhereToGoIsOnlyMarkedRead() {
        XCTAssertEqual(NotificationRouter.step(tapStillPending: true, bellIsOpen: false,
                                               somethingPresented: true, hasDestination: false), .markReadOnly)
    }
}
