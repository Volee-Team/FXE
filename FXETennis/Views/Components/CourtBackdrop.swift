//
//  CourtBackdrop.swift
//  FXETennis
//
//  The page background from Tara's front-page mockup (2026-09-26): her photo
//  of the FXE courts at dusk, washed with porcelain so text stays readable,
//  heaviest at the top where the greeting and the rows sit and thinnest at
//  the bottom where the court surface shows through. Kat and Tara the same
//  day: "there needs to be more color ... The screens just look really
//  white." "Final Updates" p.1 item 6: "Implement the background in the
//  picture w/ the overlay."
//
//  The photo is the 920-pixel frame Tara sent in a message, so it is soft at
//  full-screen size; the wash hides most of that. The original file is asked
//  for in docs/for-alex.md. Replacing it is one image in the asset catalog.
//
//  Two strengths. `.front` is the mockup (Home, sign-in, onboarding): the
//  court is visible at the bottom. `.page` is for screens that are mostly
//  cards and text (lists, details, Profile): the photo is a tint, not a
//  picture, so a long page of rows never sits on a busy image.
//

import SwiftUI

struct CourtBackdrop: View {
    enum Strength { case front, page }
    var strength: Strength = .page

    var body: some View {
        GeometryReader { geo in
            Image("court-backdrop")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(wash)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var wash: LinearGradient {
        switch strength {
        case .front:
            return LinearGradient(stops: [
                .init(color: Brand.surface.opacity(0.93), location: 0.0),
                .init(color: Brand.surface.opacity(0.86), location: 0.45),
                .init(color: Brand.surface.opacity(0.55), location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
        case .page:
            return LinearGradient(stops: [
                .init(color: Brand.surface.opacity(0.94), location: 0.0),
                .init(color: Brand.surfaceWarm.opacity(0.84), location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}
