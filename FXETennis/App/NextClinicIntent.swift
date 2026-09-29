//
//  NextClinicIntent.swift
//  FXETennis
//
//  "Hey Siri, when's my next clinic in FXE Tennis?", and the same answer from
//  Spotlight and the Shortcuts app (roadmap, 2026-09-28). It runs in the app's
//  own process with the session stored on the phone, through the same
//  ClinicsViewModel the screens use: a fresh answer when there is signal, the
//  instant-open snapshot when there is not (decision 0028), and a clinic held
//  beyond the list's five-week edge still counts. The words are NextClinic's.
//

import AppIntents
import Foundation

struct NextClinicIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Clinic"
    static let description = IntentDescription("Your next FXE Tennis clinic and your status in it.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SnapshotStore.currentUserId != nil else {
            return .result(dialog: IntentDialog(stringLiteral: NextClinic.signedOutLine))
        }
        let model = ClinicsViewModel()
        await model.load()
        if let next = NextClinic.pick(clinics: model.clinics,
                                      registrations: Array(model.myRegistrationsByClinic.values),
                                      now: .now) {
            return .result(dialog: IntentDialog(stringLiteral: NextClinic.line(for: next.clinic, status: next.status)))
        }
        // Nothing held: say so only when the list is real, not when nothing
        // could be loaded at all.
        if model.clinics.isEmpty, let failure = model.loadError {
            return .result(dialog: IntentDialog(stringLiteral: failure))
        }
        return .result(dialog: IntentDialog(stringLiteral: NextClinic.noneLine))
    }
}

struct FXETennisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextClinicIntent(),
            phrases: [
                "When's my next clinic in \(.applicationName)",
                "My next \(.applicationName) clinic",
                "Next clinic in \(.applicationName)",
            ],
            shortTitle: "Next Clinic",
            systemImageName: "figure.tennis")
    }
}
