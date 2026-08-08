//
//  NTRPRating.swift
//  FXETennis
//
//  The USTA NTRP rating scale as FXE presents it, behind the "?" explainer.
//
//  MIRRORED FROM VOLEE. Tara wants a player who uses both apps to read the
//  exact same words. The level list and the `detail` copy below are copied
//  verbatim from:
//    Volee/Volee/Models/Profile+Adult.swift  (enum NTRPDescriptions.selfRate)
//    Volee/Volee/Views/TutorialView.swift    (TutorialNTRPPage short blurbs)
//  If Tara changes the wording, change it in BOTH repos in the same pass.
//  Do not "improve" the copy here alone: divergence is the bug.
//
//  Scale note: 5.0 is the ceiling bucket, so it renders as "5.0+". Anyone at
//  or above 5.0 sits in the same row. Volee stores the raw value 5.0 and
//  appends the "+" at display time; we keep that split for the same reason.
//

import Foundation

/// A single USTA NTRP self-rating bucket. Seven levels, 2.0 through 5.0+,
/// in half-point steps.
///
/// The raw value is the numeric rating, which is what Volee persists. Keeping
/// the same raw values means a rating can move between the two systems without
/// a translation table.
enum NTRPRating: Double, CaseIterable, Identifiable, Comparable {
    case level2_0 = 2.0
    case level2_5 = 2.5
    case level3_0 = 3.0
    case level3_5 = 3.5
    case level4_0 = 4.0
    case level4_5 = 4.5
    case level5_0Plus = 5.0

    var id: Double { rawValue }

    /// Ascending display order, 0 for the lowest level. `allCases` is already
    /// declared low to high, so this is the index in that list. Exposed as a
    /// property so sort call sites do not depend on declaration order holding.
    var displayOrder: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    /// All levels lowest to highest. This is the order the chart renders in,
    /// matching Volee's descriptions wall.
    static var displayOrdered: [NTRPRating] {
        allCases.sorted { $0.displayOrder < $1.displayOrder }
    }

    /// Short label for pills and chips, for example "3.5" or "5.0+".
    /// The ceiling bucket gets the "+" suffix; nothing else does.
    var label: String {
        self == .level5_0Plus ? "5.0+" : String(format: "%.1f", rawValue)
    }

    /// Label as shown in a sentence or a row heading, for example "USTA 3.5".
    var displayName: String { "USTA \(label)" }

    /// Full description shown in the "?" chart. Verbatim from Volee's
    /// `NTRPDescriptions.selfRate`.
    var detail: String {
        switch self {
        case .level2_0:
            return "Very new player with minimal experience, learning basic strokes and struggling to sustain a rally"
        case .level2_5:
            return "Beginner with limited consistency, can rally slowly but lacks control, directional intent, and serve reliability"
        case .level3_0:
            return "Developing player who can sustain short rallies with moderate pace, working on consistency, court positioning, and basic strategy"
        case .level3_5:
            return "Intermediate player with improved consistency and directional control, can rally with pace, use some spin, and demonstrate basic match strategy"
        case .level4_0:
            return "Solid player with dependable strokes, can control depth and direction, handle pace, and execute point construction with moderate success"
        case .level4_5:
            return "Advanced player with strong, consistent strokes, can dictate play, use spin and variety effectively, and compete with aggressive strategy"
        case .level5_0Plus:
            return "High-level player with excellent shot tolerance, power, and precision, capable of advanced tactics and competing at elite sectional/national levels"
        }
    }

    /// One-line version of `detail`, for compact rows where the full sentence
    /// will not fit. Verbatim from Volee's TutorialNTRPPage blurbs.
    var summary: String {
        switch self {
        case .level2_0:      return "Very new"
        case .level2_5:      return "Beginner with limited consistency"
        case .level3_0:      return "Developing player, short rallies"
        case .level3_5:      return "Intermediate, directional control"
        case .level4_0:      return "Solid, dependable strokes"
        case .level4_5:      return "Advanced, dictates play"
        case .level5_0Plus:  return "High-level competitor"
        }
    }

    static func < (lhs: NTRPRating, rhs: NTRPRating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Lookup from a stored value

extension NTRPRating {
    /// Resolve a stored numeric rating to a bucket.
    ///
    /// Values above 5.0 collapse into the 5.0+ ceiling, which is why this is
    /// not a plain `init(rawValue:)`. A verified USTA 5.5 player is a real
    /// case, and it must land on a row rather than return nil.
    /// Values below 2.0 return nil: the scale does not go lower here.
    init?(rating: Double) {
        if rating >= 5.0 { self = .level5_0Plus; return }
        // Floor to the nearest half point so 3.7 reads as 3.5, matching how
        // Volee re-buckets a continuous rating.
        let floored = (rating / 0.5).rounded(.down) * 0.5
        guard let match = NTRPRating(rawValue: floored) else { return nil }
        self = match
    }
}
