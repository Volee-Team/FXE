//
//  SavedMessage.swift
//  FXETennis
//
//  One of Tara's saved messages (decision 0030): text she typed, kept to fill
//  the clinic message box again. The words are hers; the app never writes or
//  suggests one (hard rule 13).
//

import Foundation

struct SavedMessage: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let body: String
}

enum SavedMessageRule {
    /// The server keeps 1 to 1000 characters (20260928900001).
    static let maxLength = 1000

    /// The text the server would keep, or nil when "Save this message" should
    /// be off: the text without the whitespace at its two ends, 1 to 1000
    /// characters as Postgres counts them. Postgres length() counts Unicode
    /// scalars, not the grapheme clusters String.count counts, so a flag or a
    /// skin-toned emoji is counted here the way the server counts it.
    static func savable(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = trimmed.unicodeScalars.count
        return (1...maxLength).contains(n) ? trimmed : nil
    }
}
