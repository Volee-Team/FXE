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

import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PlayerNotification] = []
    @State private var loading = true
    @State private var error: String?

    /// Called whenever read state changes so the bell's badge can refresh.
    var onChange: () -> Void = {}

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surface.ignoresSafeArea()

                if loading && items.isEmpty {
                    ProgressView().tint(Brand.navy)
                } else if items.isEmpty {
                    VStack(spacing: Brand.Spacing.sm) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(Brand.disabled)
                        Text("Nothing yet.")
                            .font(Brand.Typography.body)
                            .foregroundStyle(Brand.textSecondary)
                    }
                    .padding(Brand.Spacing.pageMargin)
                    .accessibilityIdentifier("notifications.empty")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                Button {
                                    Task { await markRead(item) }
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
                                .font(Brand.Typography.subheadline)
                                .foregroundStyle(Brand.Status.canceled.ink)
                                .padding(.horizontal, Brand.Spacing.pageMargin)
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
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
    }

    private func row(_ item: PlayerNotification) -> some View {
        HStack(alignment: .top, spacing: Brand.Spacing.sm) {
            Circle()
                .fill(item.isUnread ? Brand.navy : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.body)
                    .font(item.isUnread ? Brand.Typography.bodyEmphasis : Brand.Typography.body)
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(Brand.Typography.caption)
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

    private func markRead(_ item: PlayerNotification) async {
        guard item.isUnread else { return }
        do {
            try await NotificationRepository.markRead(item.id)
            await load()
            onChange()
        } catch {
            self.error = "That didn't save. Check your connection and try again."
        }
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
