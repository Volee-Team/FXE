//
//  NotificationPermissionView.swift
//  FXETennis
//
//  Shown once, after the profile exists, before iOS's own permission dialog.
//  The sentence is Tara's (Developer Guide, Screen 3). Two buttons and no
//  dark pattern: "Not now" is the same size as "Turn on notifications".
//

import SwiftUI

struct NotificationPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    let registrar = PushRegistrar.shared

    var body: some View {
        VStack(spacing: Brand.Spacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: "bell.badge")
                .font(.system(size: 44))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Brand.accent, Brand.navy)
            Text("Clinic updates come through the app. Keep notifications on so you don't miss them.")
                .font(Brand.Typography.body)
                .foregroundStyle(Brand.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Brand.Spacing.pageMargin)
            Spacer(minLength: 0)

            Button {
                Task { await registrar.requestPermission(); dismiss() }
            } label: {
                Text("Turn on notifications")
                    .font(Brand.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Brand.Layout.comfortableTapTarget)
                    .foregroundStyle(Brand.textOnNavy)
                    .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("push.turnOn")

            Button {
                dismiss()
            } label: {
                Text("Not now")
                    .font(Brand.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Brand.Layout.comfortableTapTarget)
                    .foregroundStyle(Brand.navy)
                    .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("push.notNow")
        }
        .padding(Brand.Spacing.pageMargin)
        .background(Brand.surfaceGradient.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

/// Decision 13 (Tara, 2026-08-02) and decision 0008 item 3: whenever the
/// permission is denied, the app states persistently that clinic updates come
/// through it, with the one useful action (iOS Settings). Tara never sees who
/// has notifications off; this is the app talking to its own user. The
/// sentence is the same approved line the sign-up screen and the permission
/// sheet use.
struct NotificationsOffLine: View {
    @Environment(\.scenePhase) private var scenePhase
    let registrar = PushRegistrar.shared

    var body: some View {
        Group {
            if registrar.status == .denied {
                VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
                    Text("Clinic updates come through the app. Keep notifications on so you don't miss them.")
                        .font(Brand.Typography.body)
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Turn on notifications")
                            .font(Brand.Typography.button)
                            .foregroundStyle(Brand.navy)
                            .frame(minHeight: Brand.Layout.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.turnOnNotifications")
                }
                .padding(Brand.Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.Status.responseNeeded.tint, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.Status.responseNeeded.ink.opacity(0.4), lineWidth: Brand.Layout.borderWidth))
                .accessibilityIdentifier("home.notificationsOff")
            }
        }
        .task { await registrar.refreshStatus() }
        // Coming back from Settings must clear the line without a relaunch.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await registrar.refreshStatus() } }
        }
    }
}

/// Ask once per install, only when iOS has not been asked yet, only when
/// signed in with a profile. UI tests never see it: they launch with
/// UITEST_SIGNED_OUT and sign in fresh, and the sheet is suppressed in that
/// mode so every existing test keeps its element tree.
private struct PushPermissionPrompt: ViewModifier {
    @State private var show = false
    let registrar = PushRegistrar.shared

    func body(content: Content) -> some View {
        content
            .task {
                await registrar.refreshStatus()
                let uiTest = ProcessInfo.processInfo.environment["UITEST_SIGNED_OUT"] != nil
                if registrar.status == .notDetermined && !uiTest {
                    show = true
                } else {
                    registrar.registerWithAPNs()
                }
            }
            .sheet(isPresented: $show) { NotificationPermissionView() }
    }
}

extension View {
    func pushPermissionPrompt() -> some View { modifier(PushPermissionPrompt()) }
}
