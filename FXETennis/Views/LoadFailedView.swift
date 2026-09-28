//
//  LoadFailedView.swift
//  FXETennis
//
//  Signed in, but who you are could not be loaded (SessionStore `.loadFailed`).
//  Before 2026-09-27 this state did not exist: a profile load that failed for
//  lack of signal was read as "no profile", and a returning member opening the
//  app at the courts was shown the sign-up form ("Almost there!"). Now she is
//  told what happened, in the approved line, with Try again. Coming back to
//  the app also retries on its own (SessionStore.returnedToForeground).
//
//  Sign out stays reachable, so a failure that is not the network (a fault
//  of ours) can never become a screen with no way off it.
//

import SwiftUI

struct LoadFailedView: View {
    @Environment(SessionStore.self) private var session
    @State private var retrying = false

    var body: some View {
        ZStack {
            CourtBackdrop(strength: .front)

            VStack(spacing: 0) {
                BrandHeader(height: 250) {
                    Wordmark()
                        .padding(.top, Brand.Spacing.xxl + Brand.Spacing.sm)
                }

                ScrollView {
                    VStack(spacing: Brand.Spacing.lg) {
                        Text(session.loadFailureLine ?? "Something went wrong. Please try again.")
                            .brandFont(.body)
                            .foregroundStyle(Brand.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("loadFailed.message")

                        Button {
                            Task {
                                retrying = true
                                await session.retry()
                                retrying = false
                            }
                        } label: {
                            Group {
                                if retrying { ProgressView().tint(Brand.textOnNavy) }
                                else { Text("Try again").brandFont(.button) }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Brand.Layout.comfortableTapTarget)
                            .foregroundStyle(Brand.textOnNavy)
                            .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                        }
                        .buttonStyle(.plain)
                        .disabled(retrying)
                        .accessibilityIdentifier("loadFailed.retry")

                        // Off while Try again runs: a sign-out racing the
                        // retry could let its answer land after it (the
                        // session's generation drops it anyway; this keeps
                        // the two taps from crossing at all).
                        AccountExitFooter(signOutID: "loadFailed.signOut", deleteID: nil,
                                          signOutDisabled: retrying)
                    }
                    .padding(Brand.Spacing.pageMargin)
                    .padding(.top, Brand.Spacing.lg)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}
