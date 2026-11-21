//
//  ChildFormView.swift
//  FXETennis
//
//  Add a Child, and editing one (decision 0061). Name and birthday only, as
//  spec 01 asks. The birthday is never used to pick a program: Tara's rule is
//  that "program selection is always manual".
//
//  Once Tara has approved or declined a child for a program, or a waiver is
//  signed for them, the server refuses a change of name or birthday
//  (child_locked) and this sheet says to contact Tara.
//

import SwiftUI

struct ChildFormView: View {
    /// nil adds a child; a child edits that one.
    let child: Child?
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -8, to: Date()) ?? Date()
    /// Adding: Save waits until the birthday has been set on purpose, so the
    /// wheel's starting date is never saved by accident.
    @State private var birthdayChosen = false
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var typing: Field?
    private enum Field { case first, last }

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && birthdayChosen
            && !saving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surfaceGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                        field("First Name", text: $firstName, content: .givenName, id: "child.firstName",
                              name: .first, next: .last)
                        field("Last Name", text: $lastName, content: .familyName, id: "child.lastName",
                              name: .last, next: nil)

                        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
                            Text("Birthday")
                                .brandFont(.subheadline)
                                .foregroundStyle(Brand.textSecondary)
                            DatePicker("Birthday", selection: $birthday, in: ...Date(), displayedComponents: .date)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("child.birthday")
                                .onChange(of: birthday) { _, _ in birthdayChosen = true }
                        }

                        if let error {
                            Text(error)
                                .brandFont(.subheadline)
                                .foregroundStyle(Brand.Status.canceled.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("child.error")
                        }
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .crispTopEdge()
            .navyTitle(child == nil ? "Add a Child" : JuniorCopy.editChildLine)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("child.cancel")
                        .tint(Brand.textOnNavy)
                }
                .onNavy()
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("child.save")
                        .tint(Brand.textOnNavy)
                }
                .onNavy()
            }
            .task {
                guard !loaded else { return }
                if let child {
                    firstName = child.firstName
                    lastName = child.lastName
                    if let d = JuniorCopy.date(fromDateOnly: child.dateOfBirth) { birthday = d }
                }
                loaded = true
                // After the stored birthday is in place: adding starts with
                // none chosen, editing starts with the child's own.
                DispatchQueue.main.async { birthdayChosen = child != nil }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, content: UITextContentType, id: String,
                       name: Field, next: Field?) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
            Text(label)
                .brandFont(.subheadline)
                .foregroundStyle(Brand.textSecondary)
            TextField("", text: text)
                .focused($typing, equals: name)
                .submitLabel(next == nil ? .done : .next)
                .onSubmit { typing = next }
                .brandFont(.body)
                .foregroundStyle(Brand.textPrimary)
                .textContentType(content)
                .autocorrectionDisabled()
                .padding(Brand.Spacing.sm)
                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm).stroke(Brand.border, lineWidth: Brand.Layout.borderWidth))
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
    }

    private func save() {
        typing = nil
        saving = true
        error = nil
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        let dob = JuniorCopy.dateOnly(birthday)
        Task {
            do {
                if let child {
                    try await JuniorsRepository.updateChild(id: child.id, firstName: first, lastName: last, dateOfBirth: dob)
                } else {
                    try await JuniorsRepository.addChild(firstName: first, lastName: last, dateOfBirth: dob)
                }
                dismiss()
            } catch {
                self.error = JuniorCopy.line(for: error)
            }
            saving = false
        }
    }
}
