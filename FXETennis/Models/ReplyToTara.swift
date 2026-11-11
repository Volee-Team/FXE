//
//  ReplyToTara.swift
//  FXETennis
//
//  A player answering one of Tara's messages. A player wrote to her, 2026-11-10,
//  that they "can't figure out how to message you back" after her message
//  reached them as an alert, and answered by email instead. John: "do the
//  quick reply button in build 17". The quick version is an email to her
//  address (the one Contact Tara opens, decision 0024) with her message
//  quoted, so she knows what is being answered. Replies kept in the app, with
//  an inbox for her, are the fuller version and are not built.
//

import Foundation

enum ReplyToTara {
    /// Tara's address: Contact Tara, the privacy policy and the App Store
    /// listing show the same one.
    static let email = "fersctennispro@gmail.com"

    /// Contact Tara's plain address.
    static var contactURL: URL { URL(string: "mailto:\(email)")! }

    /// An email to Tara answering `message`. The subject names the clinic
    /// when there is one; the body leaves room to write, then quotes her.
    static func url(replyingTo message: String, clinic: String? = nil) -> URL? {
        let clinicName = clinic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subject = clinicName.isEmpty ? "Re: your message" : "Re: \(clinicName)"
        let quoted = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = quoted.isEmpty ? "" : "\n\nYou wrote:\n\(quoted)"
        return URL(string: "mailto:\(email)?subject=\(encode(subject))&body=\(encode(body))")
    }

    /// Every character but the unreserved ones escaped: a mail app reads "+"
    /// as a space and "&" as the next field, and URLComponents leaves both.
    private static func encode(_ s: String) -> String {
        // ASCII only: CharacterSet.alphanumerics would let "é" through unescaped.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
