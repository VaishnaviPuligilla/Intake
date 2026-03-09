// Weekly reflection card component displaying intake risk summary statistics.
    import SwiftUI
    import SwiftData

    struct WeeklyReflectionCard: View {
        // Displays risk distribution summary, dominant risk indicator, and weekly stats.
        let reflection: WeeklyReflection
        let entryCount: Int

        @State private var appeared = false
        @State private var expandBenefits = false

        var body: some View {
            VStack(spacing: 0) {
                headerRow
                Divider().background(Color.white.opacity(0.08))
                statsRow
            }
            .background(cardBackground)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.80).delay(0.1)) {
                    appeared = true
                }
            }
        }
        private var headerRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(dominantColor.opacity(0.16))
                    .frame(width: 56, height: 56)
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 24))
                    .foregroundColor(dominantColor.opacity(0.88))
            }

            VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(dominantColor.opacity(0.80))
                        Text("WEEKLY REFLECTION")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.35))
                    }

                    Text(reflection.summary)
                        .font(.system(size: 13, weight: .medium))
                        .tracking(0.1)
                        .foregroundColor(.white.opacity(0.80))
                        .lineSpacing(3)
                }

                Spacer()
            
                VStack(spacing: 3) {
                    Circle()
                        .fill(dominantColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle().strokeBorder(dominantColor.opacity(0.40), lineWidth: 1.5)
                        )
                        .overlay(
                            Text(dominantEmoji)
                                .font(.system(size: 18))
                        )
                    Text(reflection.dominantRisk.capitalized)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.4)
                        .foregroundColor(dominantColor.opacity(0.70))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }

        private var statsRow: some View {
            HStack(spacing: 0) {
                statCell(count: reflection.safeCount, label: "Safe", color: .green)
                dividerLine
                statCell(count: reflection.moderateCount, label: "Moderate", color: .yellow)
                dividerLine
                statCell(count: reflection.carefulCount, label: "Careful", color: .orange)
            }
            .background(Color.white.opacity(0.03))
        }

        private func statCell(count: Int, label: String, color: Color) -> some View {
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(count > 0 ? color : .white.opacity(0.20))
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.30))
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }

        private var dividerLine: some View {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 10)
        }

        private var cardBackground: some View {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [dominantColor.opacity(0.35), dominantColor.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
        
        private var dominantColor: Color {
            switch reflection.dominantRisk {
            case "careful":  return .orange
            case "moderate": return .yellow
            default:         return .green
            }
        }

        private var dominantEmoji: String {
            switch reflection.dominantRisk {
            case "careful":  return "⚠️"
            case "moderate": return "🍂"
            default:         return "🌿"
            }
        }
    }

    #if DEBUG
    struct WeeklyReflectionCard_Previews: PreviewProvider {
        static var previews: some View {
            ZStack {
                Color(red: 0.04, green: 0.10, blue: 0.06).ignoresSafeArea()
                WeeklyReflectionCard(
                    reflection: WeeklyReflection(
                        dominantRisk: "safe",
                        safeCount: 7,
                        moderateCount: 2,
                        carefulCount: 1,
                        topBenefits: ["Vitamin C", "Fibre", "Anti-inflammatory"],
                        summary: "This week: 7 low-concern products, 2 moderate, 1 worth-watching.",
                        encouragement: "Your plant is thriving 🌿 — 70% of your weekly intake was low-concern."
                    ),
                    entryCount: 10
                )
                .padding(20)
            }
        }
    }
    #endif
