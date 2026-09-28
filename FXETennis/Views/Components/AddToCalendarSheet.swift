//
//  AddToCalendarSheet.swift
//  FXETennis
//
//  Apple's own "New Event" editor, prefilled by ClinicCalendarEvent.make
//  (name, start, end, the club's zone; nothing in location, URL or notes).
//  The player reviews it and taps Add, or Cancel.
//
//  No calendar permission, on purpose. Since iOS 17, EventKitUI's editor
//  runs outside the app and saves on the player's own tap, so the app never
//  reads or writes the calendar and needs no access and no usage sentence in
//  Info.plist (the deployment target is 17.0). Asking for calendar access
//  would be a second system dialog for something this does not need.
//

import SwiftUI
import EventKit
import EventKitUI

struct AddToCalendarSheet: UIViewControllerRepresentable {
    let clinic: ClinicPublic
    /// Called once the editor is finished, saved or canceled.
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let editor = EKEventEditViewController()
        editor.eventStore = context.coordinator.store
        editor.event = ClinicCalendarEvent.make(for: clinic, in: context.coordinator.store)
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ editor: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        /// Held for the editor's lifetime.
        let store = EKEventStore()
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
