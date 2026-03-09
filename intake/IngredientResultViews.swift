// IngredientResultView.swift
// Displays scanned ingredient analysis results.
// Allows product naming, insight visualization, and local offline saving.
// Designed for privacy-first on-device processing.

import SwiftUI

struct IngredientResultView: View {
    let ingredientsText: String
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    @State private var productName = ""
    @State private var nameError   = false
    @FocusState private var focused: Bool

    private var insights: [SingleIngredientInsight] {
        IngredientInsightEngine.shared.detailedInsights(ingredients: ingredientsText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.10, blue: 0.06).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Product name", systemImage: "tag.fill")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(.white.opacity(0.40))
                                .textCase(.uppercase)

                            TextField("e.g. Granola Bar, Yogurt…", text: $productName)
                                .font(.system(size: 18))
                                .foregroundColor(.black)
                                .tint(.black)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.96))
                                        .overlay(RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                nameError ? Color.red.opacity(0.75) : Color.black.opacity(0.10),
                                                lineWidth: 1.5))
                                )
                                .focused($focused)
                                .onChange(of: productName) { _, _ in if nameError { nameError = false } }

                            if nameError {
                                Text("Please enter a product name.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.80))
                                    .padding(.leading, 4)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 11))
                                .foregroundColor(.green.opacity(0.70))
                            Text("\(insights.count) ingredient\(insights.count == 1 ? "" : "s") found")
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(0.5)
                                .foregroundColor(.white.opacity(0.45))
                                .textCase(.uppercase)
                        }

                        if insights.isEmpty {
                            rawIngredientsView
                        } else {
                            ForEach(insights) { insight in
                                IngredientDetailCard(insight: insight)
                            }
                        }

                        Button { save() } label: {
                            Text("Save to Health Tracker")
                                .font(.system(size: 16, weight: .semibold))
                                .tracking(0.3)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.15, green: 0.65, blue: 0.30),
                                                     Color(red: 0.08, green: 0.45, blue: 0.20)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                )
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Ingredient Analysis")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }.foregroundColor(.green)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
    }

    private var rawIngredientsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scanned Ingredients")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.40))
                .textCase(.uppercase)
            Text(ingredientsText)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.70))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        }
    }

    private func save() {
        let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            HapticManager.shared.error()
            withAnimation { nameError = true }
            return
        }
        onSave(trimmed)
    }
}

struct IngredientDetailCard: View {
    let insight: SingleIngredientInsight

    private var riskColor: Color {
        switch insight.risk {
        case "careful":  return Color(red: 0.95, green: 0.50, blue: 0.15)
        case "moderate": return Color(red: 0.95, green: 0.80, blue: 0.15)
        default:         return Color(red: 0.25, green: 0.80, blue: 0.40)
        }
    }

    private var riskLabel: String {
        switch insight.risk {
        case "careful":  return "Worth watching"
        case "moderate": return "Moderate"
        default:         return "Generally safe"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.name)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(0.2)
                        .foregroundColor(.white)
                    Text(insight.category)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.42))
                        .textCase(.uppercase)
                }
                Spacer()
                Text(riskLabel)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(riskColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(riskColor.opacity(0.14))
                            .overlay(Capsule().strokeBorder(riskColor.opacity(0.30), lineWidth: 1))
                    )
            }

            Text(insight.insight)
                .font(.system(size: 13))
                .tracking(0.1)
                .foregroundColor(.white.opacity(0.70))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !insight.benefits.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(insight.benefits, id: \.self) { benefit in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.green.opacity(0.80))
                                Text(benefit)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.green.opacity(0.08))
                                    .overlay(Capsule().strokeBorder(Color.green.opacity(0.18), lineWidth: 1))
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(riskColor.opacity(0.18), lineWidth: 1)
                )
        )
    }
}
