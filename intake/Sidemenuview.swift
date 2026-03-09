// SideMenuView.swift
// Responsible for navigation drawer UI.
// Supports expandable expiry and health tracker sections.
// Maintains tab selection state and smooth animated transitions.

import SwiftUI
import SwiftData

// MARK: - Side Menu Destinations
enum SideMenuDestination {
    case expiryLive
    case expiryHistory
    case healthThisWeek
    case healthPastWeek
    case about
}

// MARK: - View Layout
struct SideMenuView: View {
    @Binding var isShowing: Bool
    @Binding var selectedTab: AppTab
    @Binding var expirySubTab: ExpirySubTab
    @Binding var healthSubTab: HealthSubTab

    @State private var expiryExpanded = true
    @State private var healthExpanded = true
    @State private var destination: SideMenuDestination = .expiryLive

    var body: some View {
        ZStack(alignment: .leading) {
            // Dim background
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture {
                    HapticManager.shared.light()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isShowing = false
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                menuHeader

                Divider().background(Color.white.opacity(0.10)).padding(.horizontal, 20)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        expirySection
                        healthSection
                        menuItem(icon: "info.circle.fill", label: "About", color: .blue, tab: .about)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                Spacer()
                menuFooter
            }
            .frame(width: 284)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.05, green: 0.12, blue: 0.07), location: 0),
                        .init(color: Color(red: 0.03, green: 0.07, blue: 0.04), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .ignoresSafeArea()
        }
        .transition(.move(edge: .leading))
    }

    private var menuHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.10, green: 0.40, blue: 0.18),
                                 Color(red: 0.04, green: 0.20, blue: 0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 50, height: 50)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.90))
            }
            .shadow(color: .green.opacity(0.30), radius: 10)

            Text("Intake")
                .font(.system(size: 22, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white)
            Text("Your living food tracker")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 20)
    }

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            Button {
                HapticManager.shared.light()
                if selectedTab != .expiry {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selectedTab = .expiry
                        isShowing   = false
                    }
                } else {
                    withAnimation(.spring(response: 0.28)) { expiryExpanded.toggle() }
                }
            } label: {
                menuRowLabel(
                    icon: "leaf.fill",
                    label: "Expiry",
                    color: .green,
                    isActive: selectedTab == .expiry,
                    expandable: true,
                    expanded: expiryExpanded
                )
            }

            if expiryExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    subItem(icon: "dot.radiowaves.right", label: "Live", description: "Active tracked items") {
                        expirySubTab = .live
                        selectedTab = .expiry
                        isShowing   = false
                    }
                    subItem(icon: "clock.arrow.circlepath", label: "History", description: "Used & expired items") {
                        expirySubTab = .history
                        selectedTab  = .expiry
                        isShowing    = false
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.shared.light()
                if selectedTab != .health {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        healthSubTab = .thisWeek
                        selectedTab = .health
                        isShowing   = false
                    }
                } else {
                    withAnimation(.spring(response: 0.28)) { healthExpanded.toggle() }
                }
            } label: {
                menuRowLabel(
                    icon: "heart.fill",
                    label: "Health Tracker",
                    color: .pink,
                    isActive: selectedTab == .health,
                    expandable: true,
                    expanded: healthExpanded
                )
            }

            if healthExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    subItem(icon: "calendar.day.timeline.left", label: "This Week", description: "Recent ingredient logs") {
                        healthSubTab = .thisWeek
                        selectedTab = .health
                        isShowing   = false
                    }
                    subItem(icon: "calendar.badge.clock", label: "Past History", description: "All previous weeks") {
                        healthSubTab = .pastHistory
                        selectedTab = .health
                        isShowing = false
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    private func menuRowLabel(
        icon: String, label: String, color: Color,
        isActive: Bool, expandable: Bool, expanded: Bool
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(isActive ? 0.22 : 0.10))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(color.opacity(isActive ? 1.0 : 0.65))
            }
            Text(label)
                .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                .tracking(0.3)
                .foregroundColor(isActive ? .white : .white.opacity(0.72))
            Spacer()
            if expandable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.28))
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                    .animation(.spring(response: 0.28), value: expanded)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.09) : Color.clear)
        )
    }

    private func subItem(
        icon: String, label: String, description: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.light()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                action()
            }
        } label: {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1.5)
                    .padding(.vertical, 4)

                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .tracking(0.2)
                        .foregroundColor(.white.opacity(0.78))
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.30))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
    }

    private func menuItem(icon: String, label: String, color: Color, tab: AppTab) -> some View {
        Button {
            HapticManager.shared.light()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedTab = tab
                isShowing   = false
            }
        } label: {
            menuRowLabel(
                icon: icon, label: label, color: color,
                isActive: selectedTab == tab,
                expandable: false, expanded: false
            )
        }
    }

    private var menuFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().background(Color.white.opacity(0.08))
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green.opacity(0.50))
                Text("Fully offline  ·  Private  ·  No cloud")
                    .font(.system(size: 11))
                    .tracking(0.3)
                    .foregroundColor(.white.opacity(0.28))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}
