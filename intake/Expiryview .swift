// ExpiryView.swift
// Handles product lifecycle tracking UI.
// Displays live expiry monitoring cards and history view.
// Designed for offline-first local data processing.
import SwiftUI
import SwiftData

// Represents sub-navigation states inside Expiry module.
enum ExpirySubTab: String, CaseIterable {
    case live = "Live"
    case history = "History"
}
struct ExpiryView: View {
    @Binding var subTab: ExpirySubTab

    var body: some View {
        ZStack {
            backgroundGradient
            if subTab == .live {
                LiveExpiryView()
            } else {
                HistoryView()
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.04, green: 0.10, blue: 0.06), location: 0),
                .init(color: Color(red: 0.02, green: 0.06, blue: 0.04), location: 1)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// LiveExpiryView displays active non-archived scanned items.
// Supports marking items as read and deletion workflows.
// Uses SwiftData Query for local persistence.
struct LiveExpiryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<ScannedItem> { !$0.isArchived && !$0.usedSuccessfully },
        sort: \ScannedItem.expiryDate,
        order: .forward
    ) private var rawItems: [ScannedItem]
    private var items: [ScannedItem] {
        rawItems.filter { $0.daysRemaining >= 0 }
    }

    @State private var showDeleteConfirm   = false
    @State private var showMarkUsedConfirm = false
    @State private var targetItem: ScannedItem?

    var body: some View {
        ZStack {
            if items.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .alert("Mark as Read?", isPresented: $showMarkUsedConfirm) {
            Button("Mark Read", role: .destructive) {
                if let item = targetItem { markUsed(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move \"\(targetItem?.productName ?? "")\" to history as completed.")
        }
        .alert("Remove Item?", isPresented: $showDeleteConfirm) {
            Button("Remove", role: .destructive) {
                if let item = targetItem { deleteItem(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently remove \"\(targetItem?.productName ?? "")\".")
        }
    }
    private var cardList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack {
                    Text("Life Remaining")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(0.3)
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.38))
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                LazyVStack(spacing: 14) {
                    ForEach(items) { item in
                        ExpiryCard(item: item) {
                            HapticManager.shared.medium()
                            targetItem = item
                            showMarkUsedConfirm = true
                        } onDelete: {
                            HapticManager.shared.warning()
                            targetItem = item
                            showDeleteConfirm = true
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                Spacer().frame(height: 110)
            }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 50))
                .foregroundColor(.green.opacity(0.28))

            Text("Nothing tracked yet")
                .font(.system(size: 21, weight: .semibold))
                .tracking(0.3)
                .foregroundColor(.white.opacity(0.55))

            Text("Tap the scan button to add your first item.")
                .font(.system(size: 14))
                .tracking(0.2)
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .padding(36)
    }
    
    // Marks item as successfully used and archives it.
    // Cancels scheduled notifications and persists state locally.
    private func markUsed(_ item: ScannedItem) {
        HapticManager.shared.success()
        NotificationManager.shared.cancelNotifications(for: item)
        withAnimation {
            item.usedSuccessfully   = true
            item.isUsed             = true
            item.acknowledgedByUser = true
            item.isArchived         = true
            try? modelContext.save()
        }
    }

    // Permanently removes item from local database.
    // Ensures notification cleanup before deletion.
    private func deleteItem(_ item: ScannedItem) {
        HapticManager.shared.error()
        NotificationManager.shared.cancelNotifications(for: item)
        modelContext.delete(item)
        try? modelContext.save()
    }
}

// ExpiryCard is a reusable lifecycle dashboard card UI component.
// Displays product plant visualization, expiry metadata, reminders and actions.
struct ExpiryCard: View {
    let item: ScannedItem
    let onMarkUsed: () -> Void
    let onDelete: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                PlantView(state: item.plantState, size: 108)
                    .frame(width: 108, height: 108)
                    .scaleEffect(appeared ? 1.0 : 0.72)
                    .animation(.spring(response: 0.50, dampingFraction: 0.65), value: appeared)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.productName)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(0.2)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(item.statusTitle)
                        .font(.system(size: 14, weight: .medium))
                        .tracking(0.2)
                        .foregroundColor(item.statusColor)

                    Text(item.statusSubtext)
                        .font(.system(size: 12))
                        .tracking(0.1)
                        .foregroundColor(.white.opacity(0.42))
                        .lineLimit(1)

                    if let reminder = item.reminderAt {
                        HStack(spacing: 5) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green.opacity(0.85))
                            Text("Alert: \(reminder.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.60))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.50))
                        .padding(9)
                        .background(Circle().fill(Color.red.opacity(0.09)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.07))
            HStack(spacing: 0) {
                detailCell(
                    label: "Scanned",
                    value: item.scanDate.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
                )
                Divider().frame(height: 32).background(Color.white.opacity(0.08))
                detailCell(
                    label: item.daysRemaining >= 0 ? "Expires" : "Expired",
                    value: item.expiryDate.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
                )
                Divider().frame(height: 32).background(Color.white.opacity(0.08))

                Button(action: onMarkUsed) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                        Text("Mark Read")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.3)
                    }
                    .foregroundColor(.green.opacity(0.88))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .background(Color.white.opacity(0.03))
            .clipShape(
                .rect(topLeadingRadius: 0, bottomLeadingRadius: 14,
                      bottomTrailingRadius: 14, topTrailingRadius: 0)
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(item.statusColor.opacity(0.22), lineWidth: 1)
                )
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { appeared = true }
        }
    }

    private func detailCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.30))
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .tracking(0.1)
                .foregroundColor(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
