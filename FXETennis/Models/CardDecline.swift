//
//  CardDecline.swift
//  FXETennis
//
//  A declined card, in the words the player is shown (decision 0024, Tara's
//  question 78: "App needs to tell them why their card isn’t working").
//
//  The words are the ones she approved for her own screens (DeclineReason,
//  the same map as the web admin's DECLINE), after "Declined: " as her Money
//  tab writes them: "Declined: Insufficient funds (NSF)". Two differences
//  from her screens, both toward saying less:
//    * a card reported lost or stolen, and a charge Stripe stopped as fraud,
//      reads as a plain decline. Stripe asks for exactly that ("present as
//      you would the generic_decline"), so the person holding a card that is
//      not theirs is not told they were caught. The database already keeps
//      these five as generic_decline on the account (20260928700001); this
//      set is the same five, in case a code ever arrives unsanitised. Tara
//      still sees the reason;
//    * a code with no approved words is a plain decline too, never Stripe's
//      raw code, which her screens show and a player should not.
//  Whether a player should hear "Card reported lost" after all is hers to
//  decide (decision 0026); it is one line to change here.
//
//  The server sends the code (accounts.card_decline_code on Profile, the
//  refusal's hint on a clinic page, 20260928700001); this only words it.
//

import Foundation

enum CardDecline {
    /// Shown as a plain decline, whatever her screens call them.
    static let toldAsDeclined: Set<String> = ["lost_card", "stolen_card", "fraudulent", "merchant_blacklist", "pickup_card"]

    /// The line under the card on Profile, and the refusal on a clinic page.
    static func line(_ code: String?) -> String {
        "Declined: " + reason(code)
    }

    static func reason(_ code: String?) -> String {
        let plain = DeclineReason.labels["generic_decline"] ?? "Card declined"
        guard let code, !code.isEmpty, !toldAsDeclined.contains(code),
              let words = DeclineReason.labels[code] else { return plain }
        return words
    }
}
