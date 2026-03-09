import SwiftUI
import SwiftData

// HealthView.swift
// Displays weekly and historical health logging insights.
// Uses local SwiftData storage for offline ingredient tracking.
// Provides risk-based visualization of consumed products.
struct HealthView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HealthEntry.loggedDate, order: .reverse) private var allEntries: [HealthEntry]

    private var thisWeekEntries: [HealthEntry] {
        let cal  = Calendar.current
        let now  = Date()
        guard let weekRange = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return allEntries.filter { weekRange.contains($0.loggedDate) }
    }

    @State private var selectedEntry: HealthEntry?

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                if thisWeekEntries.isEmpty {
                    emptyState
                } else {
                    thisWeekList
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            IngredientDetailSheetView(entry: entry)
        }
    }
    private var thisWeekList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This Week")
                            .font(.system(size: 22, weight: .bold))
                            .tracking(0.3)
                            .foregroundColor(.white)
                        Text("Tap any product to see ingredient details")
                            .font(.system(size: 12))
                            .tracking(0.2)
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                    Text("\(thisWeekEntries.count) logged")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.38))
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)
                if thisWeekEntries.count >= 2 {
                    weeklyReflectionCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }

                LazyVStack(spacing: 12) {
                    ForEach(thisWeekEntries) { entry in
                        HealthEntryCard(entry: entry)
                            .padding(.horizontal, 16)
                            .onTapGesture {
                                HapticManager.shared.light()
                                selectedEntry = entry
                            }
                    }
                }
                Spacer().frame(height: 110)
            }
        }
    }
    // Reflection insights are derived from local knowledge reference engine.
    private var weeklyReflectionCard: some View {
        let snapshots = thisWeekEntries.map {
            HealthEntrySnapshot(
                productName:     $0.productName,
                ingredientsText: $0.ingredientsText,
                riskLevel:       $0.riskLevel,
                consumedDate:    $0.loggedDate
            )
        }
        let reflection = IngredientInsightEngine.shared.weeklyReflection(from: snapshots)
        return WeeklyReflectionCard(reflection: reflection, entryCount: thisWeekEntries.count)
    }
    private var emptyState: some View {
        VStack(spacing: 22) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 52))
                .foregroundColor(.pink.opacity(0.28))

            Text("No products logged this week")
                .font(.system(size: 20, weight: .semibold))
                .tracking(0.3)
                .foregroundColor(.white.opacity(0.55))

            Text("Tap the scan button to log what you eat and get ingredient insights.")
                .font(.system(size: 14))
                .tracking(0.2)
                .foregroundColor(.white.opacity(0.33))
                .multilineTextAlignment(.center)
        }
        .padding(36)
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
struct HealthEntryCard: View {
    let entry: HealthEntry
    @State private var appeared = false

    private var riskColor: Color {
        switch entry.riskLevel {
        case "careful":  return Color(red: 0.95, green: 0.50, blue: 0.15)
        case "moderate": return Color(red: 0.95, green: 0.80, blue: 0.15)
        default:         return Color(red: 0.25, green: 0.80, blue: 0.40)
        }
    }

    private var riskLabel: String {
        switch entry.riskLevel {
        case "careful":  return "Worth watching"
        case "moderate": return "Moderate"
        default:         return "Low concern"
        }
    }

    private var ingredientCount: Int {
        entry.ingredientsText.components(separatedBy: ",").count
    }

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(riskColor.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(riskColor.opacity(0.85))
            }
            .scaleEffect(appeared ? 1.0 : 0.75)
            .animation(.spring(response: 0.45, dampingFraction: 0.68), value: appeared)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.productName)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(0.2)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(ingredientCount) ingredient\(ingredientCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))

                    Text("·")
                        .foregroundColor(.white.opacity(0.25))

                    Text("Added \(entry.loggedDate.formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))
                }
            }

            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(riskLabel)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(riskColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(riskColor.opacity(0.14))
                    )
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(riskColor.opacity(0.18), lineWidth: 1)
                )
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { appeared = true }
        }
    }
}
struct IngredientDetailSheetView: View {
    let entry: HealthEntry
    @Environment(\.dismiss) private var dismiss

    private var insights: [SingleIngredientInsight] {
        IngredientInsightEngine.shared.detailedInsights(ingredients: entry.ingredientsText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.10, blue: 0.06).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        HStack(spacing: 10) {
                            Image(systemName: "leaf.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.green.opacity(0.80))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.productName)
                                    .font(.system(size: 18, weight: .bold))
                                    .tracking(0.2)
                                    .foregroundColor(.white)
                                Text("Logged \(entry.loggedDate.formatted(.dateTime.weekday().day().month().year()))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.40))
                            }
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white.opacity(0.80))
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.07))
                        )

                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 11))
                                .foregroundColor(.green.opacity(0.70))
                            Text("\(insights.count) ingredient\(insights.count == 1 ? "" : "s") analysed")
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(0.5)
                                .foregroundColor(.white.opacity(0.45))
                                .textCase(.uppercase)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved Ingredient Text")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(.white.opacity(0.40))
                                .textCase(.uppercase)
                            Text(entry.ingredientsText)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.68))
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.06))
                                )
                        }

                        if insights.isEmpty {
                            Text("No analyzed ingredient cards available for this entry.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.58))
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.05))
                                )
                        } else {
                            ForEach(insights) { insight in
                                IngredientDetailCard(insight: insight)
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Ingredient Breakdown")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.green)
                }
            }
        }
    }
}
struct PastHealthView: View {
    @Query(sort: \HealthEntry.loggedDate, order: .reverse) private var allEntries: [HealthEntry]

    private var pastEntries: [HealthEntry] {
        let cal = Calendar.current
        let now = Date()
        guard let currentWeekRange = cal.dateInterval(of: .weekOfYear, for: now) else { return allEntries }
        return allEntries.filter { !currentWeekRange.contains($0.loggedDate) }
    }
    private var grouped: [(String, [HealthEntry])] {
        var dict: [String: [HealthEntry]] = [:]
        let cal = Calendar.current
        for entry in pastEntries {
            let week = cal.component(.weekOfYear, from: entry.loggedDate)
            let year = cal.component(.yearForWeekOfYear, from: entry.loggedDate)
            let key  = "Week \(week), \(year)"
            dict[key, default: []].append(entry)
        }
        return dict.sorted { a, b in
            
            let aFirst = a.value.first?.loggedDate ?? Date.distantPast
            let bFirst = b.value.first?.loggedDate ?? Date.distantPast
            return aFirst > bFirst
        }
    }

    @State private var selectedEntry: HealthEntry?

    var body: some View {
        ZStack {
            backgroundGradient

            if pastEntries.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 46))
                        .foregroundColor(.white.opacity(0.22))
                    Text("No past logs yet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.50))
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Health History")
                                .font(.system(size: 22, weight: .bold))
                                .tracking(0.3)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 14)

                        ForEach(grouped, id: \.0) { (weekLabel, entries) in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(weekLabel)
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.0)
                                    .foregroundColor(.white.opacity(0.35))
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 20)

                                ForEach(entries) { entry in
                                    HealthEntryCard(entry: entry)
                                        .padding(.horizontal, 16)
                                        .onTapGesture {
                                            HapticManager.shared.light()
                                            selectedEntry = entry
                                        }
                                }
                            }
                            .padding(.bottom, 16)
                        }
                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            IngredientDetailSheetView(entry: entry)
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
