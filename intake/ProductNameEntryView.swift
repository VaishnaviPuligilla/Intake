// This view allows user to confirm product name, expiry date, and reminder schedule.
// Validation rules ensure:
// - Product name must not be empty
// - Expiry date cannot be in the past
// - Reminder must be before expiry day and in future

import SwiftUI

// Handles product metadata entry after expiry detection.
// Supports expiry correction, reminder scheduling, and tracker saving.
struct ProductNameEntryView: View {
    let detectedExpiry: Date
    let onCancel: () -> Void
    let onSave: (String, Date, Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var productName        = ""
    @State private var nameError          = false
    @State private var overrideExpiry:    Date = Date()
    @State private var showExpiryOverride = false
    @State private var selectedReminderDays: Int = 0
    @State private var reminderTime: Date = Date()
    @State private var reminderError = false
    @FocusState private var focused: Bool

    private var resolvedExpiry: Date { showExpiryOverride ? overrideExpiry : detectedExpiry }
    private var isPastExpiry: Bool {
        Calendar.current.startOfDay(for: resolvedExpiry) < Calendar.current.startOfDay(for: Date())
    }

    private var daysUntilExpiry: Int {
        let cal = Calendar.current
        let today     = cal.startOfDay(for: Date())
        let expiryDay = cal.startOfDay(for: resolvedExpiry)
        return cal.dateComponents([.day], from: today, to: expiryDay).day ?? 0
    }

    private var availableReminderChoices: [Int] {
        if daysUntilExpiry <= 0 { return [0] }
        return [3, 2, 1, 0].filter { $0 < daysUntilExpiry }
    }

    private func reminderLabel(_ d: Int) -> String {
        d == 0 ? "On expiry day" : "\(d) day\(d == 1 ? "" : "s") before"
    }

    private var reminderBaseDate: Date {
        let cal = Calendar.current
        let expiryStart = cal.startOfDay(for: resolvedExpiry)
        return cal.date(byAdding: .day, value: -selectedReminderDays, to: expiryStart) ?? expiryStart
    }

    private var endOfExpiryDay: Date {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: resolvedExpiry)
        return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? resolvedExpiry
    }

    private var reminderAt: Date? {
        let cal  = Calendar.current
        let day  = cal.dateComponents([.year, .month, .day], from: reminderBaseDate)
        let time = cal.dateComponents([.hour, .minute], from: reminderTime)
        var merged = DateComponents()
        merged.year = day.year; merged.month = day.month; merged.day = day.day
        merged.hour = time.hour; merged.minute = time.minute
        return cal.date(from: merged)
    }

    private var isReminderValid: Bool {
        guard let reminderAt else { return false }
        return reminderAt > Date() && reminderAt <= endOfExpiryDay
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.10, blue: 0.06).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {

                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Expiry date detected")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundColor(.green.opacity(0.85))
                                    .textCase(.uppercase)
                                Text(detectedExpiry.formatted(date: .long, time: .omitted))
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.green.opacity(0.10))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.green.opacity(0.25), lineWidth: 1))
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Label("What is this product?", systemImage: "tag.fill")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(.white.opacity(0.40))
                                .textCase(.uppercase)
                            TextField("e.g. Milk, Bread, Yogurt…", text: $productName)
                                .font(.system(size: 19))
                                .foregroundColor(.black)
                                .padding(17)
                                .background(
                                    RoundedRectangle(cornerRadius: 13)
                                        .fill(Color.white.opacity(0.96))
                                        .overlay(RoundedRectangle(cornerRadius: 13)
                                            .strokeBorder(
                                                nameError ? Color.red.opacity(0.8) : Color.black.opacity(0.10),
                                                lineWidth: 1.5))
                                )
                                .focused($focused)
                                .onSubmit { save() }
                                .onChange(of: productName) { _, _ in if nameError { nameError = false } }
                            if nameError {
                                Text("Please enter a product name.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.8))
                                    .padding(.leading, 4)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                if !showExpiryOverride { overrideExpiry = detectedExpiry }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showExpiryOverride.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showExpiryOverride ? "chevron.up" : "pencil")
                                        .font(.system(size: 11))
                                    Text(showExpiryOverride ? "Hide date picker" : "Wrong date? Tap to fix")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(.white.opacity(0.35))
                            }
                            if showExpiryOverride {
                                DatePicker("", selection: $overrideExpiry, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .tint(.green)
                                    .colorScheme(.dark)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Reminder schedule", systemImage: "bell.badge")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(.white.opacity(0.40))
                                .textCase(.uppercase)

                            Text("Choose when to alert: before expiry or on expiry day.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.52))

                            HStack(spacing: 8) {
                                ForEach(availableReminderChoices, id: \.self) { d in
                                    Button {
                                        selectedReminderDays = d
                                        reminderError = false
                                    } label: {
                                        Text(reminderLabel(d))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(selectedReminderDays == d ? .black : .white.opacity(0.85))
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 12)
                                            .background(
                                                Capsule()
                                                    .fill(selectedReminderDays == d ? Color.green.opacity(0.95) : Color.white.opacity(0.09))
                                                    .overlay(Capsule().strokeBorder(
                                                        selectedReminderDays == d ? Color.green.opacity(0.95) : Color.white.opacity(0.20),
                                                        lineWidth: 1))
                                            )
                                    }
                                }
                            }

                            DatePicker("Alert time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                .tint(.green)
                                .colorScheme(.dark)
                                .environment(\.locale, Locale(identifier: "en_US"))

                            if let reminderAt {
                                Text("Will alert on \(reminderAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.55))
                            }

                            if isPastExpiry {
                                Text("Out of expiry date. Cannot save to tracker.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red.opacity(0.92))
                            } else if reminderError || !isReminderValid {
                                Text("Selected alert time is not valid. Pick a future time (not beyond expiry day).")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red.opacity(0.9))
                            }
                        }

                        Button { save() } label: {
                            Text("Save to Tracker")
                                .font(.system(size: 17, weight: .semibold))
                                .tracking(0.3)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.15, green: 0.65, blue: 0.30),
                                                     Color(red: 0.08, green: 0.45, blue: 0.20)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ))
                                )
                        }
                        .padding(.top, 4)
                        .disabled(isPastExpiry || !isReminderValid)
                        .opacity((!isPastExpiry && isReminderValid) ? 1 : 0.65)
                    }
                    .padding(22)
                }
            }
            .navigationTitle("Name this item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss(); onCancel() }
                        .foregroundColor(.green)
                }
            }
        }
        .onAppear {
            reminderTime = Date()
            selectedReminderDays = availableReminderChoices.first ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
        .onChange(of: reminderTime) { _, _ in reminderError = false }
        .onChange(of: resolvedExpiry) { _, _ in
            let choices = availableReminderChoices
            if !choices.contains(selectedReminderDays) { selectedReminderDays = choices.first ?? 0 }
            reminderError = false
        }
    }

    private func save() {
        let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            HapticManager.shared.error()
            withAnimation { nameError = true }
            return
        }
        guard !isPastExpiry else {
            HapticManager.shared.error()
            return
        }
        guard isReminderValid else {
            HapticManager.shared.error()
            withAnimation { reminderError = true }
            return
        }
        HapticManager.shared.success()
        onSave(trimmed, resolvedExpiry, reminderAt)
        dismiss()
    }
}
