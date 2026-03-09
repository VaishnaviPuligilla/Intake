// HistoryView.swift
// Displays archived and completed product lifecycle records.
// Supports manual history cleanup and offline local persistence.
// Designed for privacy-first storage architecture.
import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<ScannedItem> { $0.isUsed || $0.isArchived },
        sort: \ScannedItem.expiryDate,
        order: .reverse
    ) private var history: [ScannedItem]

    @State private var showClearConfirm = false

    var body: some View {
        ZStack {
            if history.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .alert("Clear All History?", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(history.count) archived items.")
        }
    }

    private var listContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack {
                    Text("History")
                        .font(.system(size: 20, weight: .bold))
                        .tracking(0.3)
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        HapticManager.shared.warning()
                        showClearConfirm = true
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 12, weight: .medium))
                            .tracking(0.2)
                            .foregroundColor(.red.opacity(0.65))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.red.opacity(0.10)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                LazyVStack(spacing: 12) {
                    ForEach(history) { item in
                        HistoryCard(item: item) { deleteItem(item) }
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }

                Spacer().frame(height: 80)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.18))
            Text("No history yet")
                .font(.system(size: 18, weight: .semibold))
                .tracking(0.3)
                .foregroundColor(.white.opacity(0.45))
            Text("Items you mark as used will appear here.")
                .font(.system(size: 13))
                .tracking(0.2)
                .foregroundColor(.white.opacity(0.26))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private func deleteItem(_ item: ScannedItem) {
        HapticManager.shared.light()
        withAnimation { modelContext.delete(item); try? modelContext.save() }
    }

    private func clearAll() {
        HapticManager.shared.error()
        withAnimation {
            history.forEach { modelContext.delete($0) }
            try? modelContext.save()
        }
    }
}
struct HistoryCard: View {
    let item: ScannedItem
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Plant: blooming = used well, dead = expired
            PlantView(state: item.usedSuccessfully ? .blooming : .dead, size: 60)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.productName)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(0.2)
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)

                Text(item.usedSuccessfully ? "Used successfully" : "Expired unused")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.3)
                    .foregroundColor(item.usedSuccessfully ? .green.opacity(0.80) : .red.opacity(0.65))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(item.usedSuccessfully
                                  ? Color.green.opacity(0.12)
                                  : Color.red.opacity(0.10))
                    )

                Text(item.expiryDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .tracking(0.1)
                    .foregroundColor(.white.opacity(0.32))

                Text("Added: \(item.scanDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))

                if let reminder = item.reminderAt {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green.opacity(0.80))
                        Text("Alert: \(reminder.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.50))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.45))
                    .padding(9)
                    .background(Circle().fill(Color.red.opacity(0.08)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
