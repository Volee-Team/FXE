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
//  Receiving (MVP audit item 12, 2026-09-27). The app delegate is also the
//  notification center's delegate: without one, iOS shows nothing for a push
//  that lands while the app is open, a tap opens the app wherever it was, and
//  the number the server put on the icon stays after everything is read. A
//  push landing in the foreground shows as a banner and reloads Home; a tap
//  is handed to NotificationRouter, which opens its clinic; the icon's number
//  is set to the bell's own count wherever that count is refreshed.
//  tests/push/simctl-push.sh shows a push on the simulator with the payload
//  supabase/functions/push/index.ts sends.
//

import SwiftUI
import UserNotifications

/// UIKit's registration callbacks land on the app delegate, so a tiny one is
/// adapted in. It forwards the token, and as the notification center's
/// delegate it passes arrivals and taps to NotificationRouter. It decides
/// nothing itself.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Before launch finishes, or the tap that launched the app is never delivered.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushRegistrar.shared.tokenArrived(token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushRegistrar.shared.registrationFailed(error)
    }

    // iOS may call these off the main thread; each hands a Sendable value to
    // the main actor and answers at once.

    /// A push while the app is open: show it as it would show on the lock
    /// screen, and reload Home so the bell and the clinic list move with it.
    /// No .badge here: Home's reload sets the icon from the fresh count.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in NotificationRouter.shared.requestReload() }
        completionHandler([.banner, .list, .sound])
    }

    /// A tap on a push, from the lock screen, a banner or Notification Center.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let tap = PushTap(userInfo: response.notification.request.content.userInfo)
            Task { @MainActor in NotificationRouter.shared.tapped(tap) }
        }
        completionHandler()
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
    /// shared phone must never show the next person someone else's invitation,
    /// nor their unread number on the icon.
    func unregisterForSignOut() async {
        setBadge(0)
        NotificationRouter.shared.reset()
        guard let token else { return }
        try? await ProfileRepository.unregisterDevice(token)
    }

    // MARK: - The icon's number

    /// The icon shows the bell's count. The push function sets it to the
    /// unread count when it sends; nothing cleared it after that, so a number
    /// stayed on the icon once everything was read (MVP audit item 12). Home
    /// calls this each time it refreshes the count.
    func setBadge(_ unread: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, unread), withCompletionHandler: nil)
    }

    /// For a path that does not hold the count itself: a tapped push.
    func syncBadge() async {
        if let unread = try? await NotificationRepository.unreadCount() { setBadge(unread) }
    }
}
