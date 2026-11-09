//
//  PlayerContact.swift
//  FXETennis
//
//  The phone number on Tara's Player page (1.0.3, build 17). Tara,
//  2026-11-09, on her phone's Player page: "Also from app would be great to
//  have their cell number under name. Sure it's there on website" and "Will
//  def need this juniors bc if something happens need to text parents
//  immediate".
//
//  The number is the account's (`accounts.phone`, through `players.account_id`),
//  so a junior's is the parent's. Tara's alone: an admin reads every account
//  under `accounts_self`; a pro or a player reads only their own, and the
//  pro's week shows no phone, by design. No migration: `search_players` keeps
//  its columns, so the 1.0.1 to 1.0.3 apps decode it as before.
//

import Foundation
import Supabase

struct PlayerContact: Decodable, Sendable, Equatable {
    struct Holder: Decodable, Sendable, Equatable {
        let firstName: String?
        let lastName: String?
        let phone: String?
        enum CodingKeys: String, CodingKey {
            case phone
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }
    let accounts: Holder?
}

enum PlayerPhone {
    /// Whose number it is, in words: "Phone" for the account holder,
    /// "Parent's phone (Sarah Lee)" for a junior, and "Phone on Sarah Lee's
    /// account" for another adult on someone's account.
    static func label(kind: String, playerFirst: String, playerLast: String,
                      holderFirst: String?, holderLast: String?) -> String {
        let holder = [holderFirst, holderLast]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let same = holderFirst?.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(playerFirst) == .orderedSame
            && holderLast?.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(playerLast) == .orderedSame
        if kind == "junior" { return holder.isEmpty ? "Parent's phone" : "Parent's phone (\(holder))" }
        if same || holder.isEmpty { return "Phone" }
        return "Phone on \(holder)'s account"
    }

    /// The number as a link target: its digits, with a leading + kept. Nil
    /// when there is nothing to dial.
    static func dialable(_ phone: String?) -> String? {
        guard let phone else { return nil }
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        return (trimmed.hasPrefix("+") ? "+" : "") + digits
    }

    static func textURL(_ phone: String?) -> URL? { dialable(phone).flatMap { URL(string: "sms:\($0)") } }
    static func callURL(_ phone: String?) -> URL? { dialable(phone).flatMap { URL(string: "tel:\($0)") } }
}

extension AdminRepository {
    /// The account behind one player: its holder's name and phone. One row,
    /// by the player's id (RLS bounds what a query may return, never what it
    /// should: the predicate is here, hard-learned 2026-08-15).
    static func playerContact(_ player: UUID) async throws -> PlayerContact? {
        let rows: [PlayerContact] = try await supabase
            .from("players")
            .select("accounts(first_name,last_name,phone)")
            .eq("id", value: player)
            .execute()
            .value
        return rows.first
    }
}
