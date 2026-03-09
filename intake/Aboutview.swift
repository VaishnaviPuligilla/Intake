// AboutView.swift
// This view displays application information including features, privacy philosophy, and technology design.
// The UI follows a modular SwiftUI component approach with reusable featureRow rendering.
// All content is static educational information designed for offline usage.
import SwiftUI
// Main About screen view showing ap description, core features, and privacy information.
struct AboutView: View {
    // Builds the user interface using ZStack background gradient and scrollable content layout.
    var body: some View {
        ZStack {
            // Background gradient with dark green theme representing app identity.
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.04, green: 0.10, blue: 0.06), location: 0),
                    .init(color: Color(red: 0.02, green: 0.06, blue: 0.04), location: 1)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                // Scrollable content container for About page sections.
                // App branding section displaying logo, app name, and version.
                VStack(spacing: 28) {
                    Spacer().frame(height: 16)
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.10, green: 0.40, blue: 0.18),
                                                 Color(red: 0.04, green: 0.20, blue: 0.08)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 90, height: 90)
                                .shadow(color: .green.opacity(0.30), radius: 18, y: 8)
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 42))
                                .foregroundColor(.white.opacity(0.88))
                        }
                        Text("Intake")
                            .font(.system(size: 27, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(.white)

                        Text("Version 1.0")
                            .font(.system(size: 12))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(0.28))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        // Describes application purpose and design philosophy.
                        sectionHeader("About")
                        Text("Intake is an offline lifestyle assistant designed to help you track product expiry, understand ingredient insights, and stay mindful of your consumption. The app focuses on privacy-first local processing with zero internet dependency.")
                            .font(.system(size: 14))
                            .tracking(0.1)
                            .foregroundColor(.white.opacity(0.62))
                            .lineSpacing(5)
                    }
                    .padding(.horizontal, 20)
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Core Features")
                            .padding(.horizontal, 20)
                        // Lists main functionality features of the application.

                        VStack(spacing: 10) {
                            featureRow(
                                icon: "leaf.fill",
                                color: .green,
                                title: "Expiry Lifecycle Tracker",
                                desc: "Track products with a living plant that reflects freshness in real time."
                            )
                            featureRow(
                                icon: "camera.viewfinder",
                                color: .purple,
                                title: "Offline Ingredient Scanning",
                                desc: "Scan any ingredient list using on-device OCR — no internet required."
                            )
                            featureRow(
                                icon: "flask.fill",
                                color: .orange,
                                title: "Ingredient Insight Analysis",
                                desc: "Understand what each ingredient does to your body and its risk level."
                            )
                            featureRow(
                                icon: "bell.fill",
                                color: .yellow,
                                title: "Smart Expiry Alerts",
                                desc: "Sends alerts to users as product expiry approaches."
                            )
                            featureRow(
                                icon: "internaldrive.fill",
                                color: .blue,
                                title: "100% Local Storage",
                                desc: "All data lives on your device. Nothing is uploaded, ever."
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        // Technical implementation details and privacy design explanation.
                        sectionHeader("Technology")
                            .padding(.horizontal, 20)
                        Text("This app is built using SwiftUI and Apple on-device technologies.Ingredient insights are generated from a curated general food knowledge reference set and are intended for educational awareness only. The app does not provide medical diagnosis or external data service integration.")
                            .font(.system(size: 14))
                            .tracking(0.1)
                            .foregroundColor(.white.opacity(0.62))
                            .lineSpacing(5)
                            .padding(.horizontal, 20)
                    }
                    VStack(spacing: 8) {
                        // Privacy-first design statement displayed as highlighted card.
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.green.opacity(0.65))
                        Text("Privacy First")
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(0.70))
                        Text("No personal data or scanned content is sent outside your device.\nAll processing happens locally on-device.")
                            .font(.system(size: 13))
                            .tracking(0.1)
                            .foregroundColor(.white.opacity(0.42))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.green.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.green.opacity(0.18), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 60)
                }
            }
        }
    }
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.35))
            .textCase(.uppercase)
    }
    private func featureRow(icon: String, color: Color, title: String, desc: String) -> some View {
        // Reusable component for displaying feature icon, title, and description rows.
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.2)
                    .foregroundColor(.white.opacity(0.85))
                Text(desc)
                    .font(.system(size: 12))
                    .tracking(0.1)
                    .foregroundColor(.white.opacity(0.38))
                    .lineSpacing(3)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}
#Preview {
    AboutView()
}
