//
//  PushRegistrar.swift
//  FXETennis
//
//  The client half of decision 0008. Asks iOS for permission (once, with
//  Tara's line), registers with APNs, and hands the token to `register_device`
//  so the sending side has an address. Nothing here sends anything, and the
//  token never leaves the device except to that one RPC.
//
//  Simulators on Apple silicon do receive real APNs tokens; a Debug build on
//  the simulator therefore exercises this whole path except the final hop.
//

import SwiftUI
import UserNotifications

/// UIKit's registration callbacks land on the app delegate, so a tiny one is
/// adapted in. It forwards the token; it owns no other behaviour.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushRegistrar.shared.tokenArrived(token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushRegistrar.shared.registrationFailed(error)
    }
}

@MainActor
@Observable
final class PushRegistrar {
    static let shared = PushRegistrar()

    /// What iOS says right now. `.notDetermined` means we have not asked.
    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// The last token APNs gave us, kept so sign-out can unregister exactly it.
    private(set) var token: String?

    private let tokenKey = "fxe.apns.token"

    private init() {
        token = UserDefaults.standard.string(forKey: tokenKey)
    }

    func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// The one prompt. iOS shows its own system dialog; ours (the sheet with
    /// Tara's line) comes first so the system dialog has context.
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            if granted { registerWithAPNs() }
        } catch {
            await refreshStatus()
        }
    }

    /// Called on every signed-in launch. Cheap, and it is how a rotated token
    /// reaches the server: APNs calls the delegate again with the new one.
    func registerWithAPNs() {
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        NSLog("APNs: registering (status %d)", status.rawValue)
        UIApplication.shared.registerForRemoteNotifications()
    }

    fileprivate func tokenArrived(_ token: String) {
        NSLog("APNs token received (%d chars)", token.count)
        self.token = token
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { try? await ProfileRepository.registerDevice(token) }
    }

    fileprivate func registrationFailed(_ error: Error) {
        // The simulator without an Apple-silicon host, or no network. Not
        // surfaced to the player; the bell still works without a push.
        NSLog("APNs registration failed: %@", error.localizedDescription)
    }

    /// Sign-out: the phone must stop receiving this account's pushes, and a
    /// shared phone must never show the next person someone else's invitation.
    func unregisterForSignOut() async {
        guard let token else { return }
        try? await ProfileRepository.unregisterDevice(token)
    }
}
