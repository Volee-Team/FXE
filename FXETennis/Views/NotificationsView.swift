//
//  NotificationsView.swift
//  FXETennis
//
//  What the bell opens. Every row was written server-side by the RPC that
//  caused it (invite_from_pool, cancel_clinic, send_clinic_message, …), so
//  the words are Tara's; this screen lists them, newest first, and marks
//  them read. Opening a row marks just that row; "Mark all read" is the
//  broom.
//
//  Read state lives in the database (`read_at`), not on the device, so the
//  bell agrees across reinstalls and, later, across the web admin.
//
//  A row opens what it is about through NotificationRouter's resolver, the
//  same one a tapped push uses: a clinic, or the clinic behind a
//  registration (an invitation for a player; a cancellation, an accept or a
//  decline for Tara, on her page for that clinic). Until 2026-09-27 only
//  'clinic' rows opened, so a real invitation was marked read and went
//  nowhere (MVP audit item 12). While this list is open it also takes
//  tapped pushes and reloads when one lands.
//

import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var items: [PlayerNotification] = []
    /// The screen a tapped row (or a tapped push) resolved to; drives navigation.
    @State private var destination: NotificationDestination?
    @State private var loading = true
    @State private var error: String?

    /// Called whenever read state changes so the bell's badge can refresh.
    var onChange: () -> Void = {}

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surfaceGradient.ignoresSafeArea()

                if loading && items.isEmpty {
                    ProgressView().tint(Brand.navy)
                } else if items.isEmpty {
                    VStack(spacing: Brand.Spacing.sm) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(Brand.disabled)
                        Text("No notifications yet")
                            .brandFont(.body)
                            .foregroundStyle(Brand.textSecondary)
                    }
                    .padding(Brand.Spacing.pageMargin)
                    .accessibilityIdentifier("notifications.empty")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                Button {
                                    Task { await open(item) }
                                } label: {
                                    row(item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("notifications.row")
                                .accessibilityLabel("\(item.isUnread ? "Unread. " : "")\(item.body)")
                                if item.id != items.last?.id {
                                    Divider().background(Brand.hairline)
                                }
                            }
                        }
                        .padding(.horizontal, Brand.Spacing.cardPadding)
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                        .padding(Brand.Spacing.pageMargin)

                        if let error {
                            Text(error)
                                .brandFont(.subheadline)
                                .foregroundStyle(Brand.Status.canceled.ink)
                                .padding(.horizontal, Brand.Spacing.pageMargin)
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Notifications")
            // Large, not inline: between Done and Mark all read an inline
            // title is clipped at larger text sizes (audit, 2026-09-28).
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $destination) { shown in
                NotificationDestinationView(destination: shown)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("notifications.done")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark all read") { Task { await markAllRead() } }
                        .disabled(!items.contains(where: \.isUnread))
                        .accessibilityIdentifier("notifications.markAllRead")
                }
            }
        }
        .task { await load() }
        // Taps and arrivals while the list is on screen (NotificationRouter).
        .onAppear { router.bellIsOpen = true }
        .onDisappear { router.bellIsOpen = false }
        .onChange(of: router.pendingTap?.token, initial: true) {
            guard let tap = router.take() else { return }
            Task { await openTap(tap) }
        }
        .onChange(of: router.reloads) { Task { await load() } }
    }

    private let router = NotificationRouter.shared
    private var isAdmin: Bool { session.account?.isAdmin == true }

    private func row(_ item: PlayerNotification) -> some View {
        HStack(alignment: .top, spacing: Brand.Spacing.sm) {
            Circle()
                .fill(item.isUnread ? Brand.navy : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.body)
                    .brandFont(item.isUnread ? .bodyEmphasis : .body)
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .brandFont(.caption)
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Brand.Spacing.sm)
        .contentShape(Rectangle())
    }

    private func load() async {
        do {
            items = try await NotificationRepository.all()
            error = nil
        } catch {
            self.error = "Couldn't load notifications. Pull to try again."
        }
        loading = false
    }

    /// Tap: mark read, then go to what the row is about, if there is still
    /// something to go to. A notification about a clinic that has since ended
    /// stays a note.
    private func open(_ item: PlayerNotification) async {
        if item.isUnread {
            do {
                try await NotificationRepository.markRead(item.id)
                await load()
                onChange()
            } catch {
                self.error = "That didn't save. Check your connection and try again."
            }
        }
        guard let target = NotificationTarget(entityType: item.entityType, entityId: item.entityId) else { return }
        destination = await NotificationResolver.live.destination(for: target, isAdmin: isAdmin)
    }

    /// A push tapped while this list is open: it opens here, on this stack,
    /// rather than in a second sheet that iOS would refuse to present. Its
    /// row is marked read once the screen is set, not before.
    private func openTap(_ tap: PushTap) async {
        let shown = await router.resolve(tap, isAdmin: isAdmin)
        if let shown { destination = shown }
        await router.delivered(tap)
        await load()
        onChange()
    }

    private func markAllRead() async {
        do {
            try await NotificationRepository.markAllRead()
            await load()
            onChange()
        } catch {
            self.error = "That didn't save. Check your connection and try again."
        }
    }
}
