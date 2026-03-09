// ContentView.swift
// Main application dashboard.
// Handles navigation, camera permission flow, auto archival logic,
// and floating action scanning entry point.
// Designed for offline-first privacy architecture.
import SwiftUI
import SwiftData
import Combine
import AVFoundation
#if os(macOS)
import AppKit
#endif

enum AppTab: String, CaseIterable {
    case expiry = "Expiry"
    case health = "Health"
    case about  = "About"

    var icon: String {
        switch self {
        case .expiry: return "leaf.fill"
        case .health: return "heart.fill"
        case .about:  return "info.circle.fill"
        }
    }
}

enum HealthSubTab {
    case thisWeek
    case pastHistory
}

// Root view managing application navigation and lifecycle-aware data maintenance.

struct ContentView: View {
    @State private var selectedTab:  AppTab       = .expiry
    @State private var showMenu                   = false
    @State private var showScan                   = false
    @State private var expirySubTab: ExpirySubTab = .live
    @State private var healthSubTab: HealthSubTab = .thisWeek
    @State private var menuDragOffset: CGFloat    = 0
    @State private var expirySweepTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var showCameraPermissionAlert = false
    @State private var cameraPermissionMessage = "This app needs camera access to scan expiry dates. Please allow camera permission in Settings."

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allItems: [ScannedItem]

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                // Top navigation bar containing menu toggle and brand mark.
                // Provides consistent app identity across screens.
                topBar
                ZStack {
                    switch selectedTab {
                    case .expiry:
                        ExpiryView(subTab: $expirySubTab).transition(.opacity)
                    case .health:
                        Group {
                            switch healthSubTab {
                            case .thisWeek:
                                HealthView()
                            case .pastHistory:
                                PastHealthView()
                            }
                        }
                        .transition(.opacity)
                    case .about:
                        AboutView().transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: selectedTab)
            }
            // Floating Action Button used to trigger scanning workflow.
            // Requires camera permission before opening scanner.
            if selectedTab == .expiry && expirySubTab == .live {
                fabButton(icon: "barcode.viewfinder") { openScanWithCameraPermission(for: .expiry) }
            }
            if selectedTab == .health {
                fabButton(icon: "barcode.viewfinder") { openScanWithCameraPermission(for: .health) }
            }
            if showMenu {
                SideMenuView(
                    isShowing: $showMenu,
                    selectedTab: $selectedTab,
                    expirySubTab: $expirySubTab,
                    healthSubTab: $healthSubTab
                )
                    .transition(.move(edge: .leading))
                    .zIndex(10)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .gesture(
            DragGesture()
                .onChanged { val in
                    if val.startLocation.x < 30 && val.translation.width > 0 {
                        menuDragOffset = val.translation.width
                    }
                }
                .onEnded { val in
                    if val.startLocation.x < 30 && val.translation.width > 60 {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { showMenu = true }
                    }
                    menuDragOffset = 0
                }
        )
        #if os(iOS)
        .fullScreenCover(isPresented: $showScan) {
            ScanView(context: selectedTab == .health ? .health : .expiry)
        }
        #else
        .sheet(isPresented: $showScan) {
            ScanView(context: selectedTab == .health ? .health : .expiry)
        }
        #endif
        .onAppear { autoArchiveExpiredItems() }
        .onReceive(expirySweepTimer) { _ in
            autoArchiveExpiredItems()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                autoArchiveExpiredItems()
            }
        }
        .alert("Camera Access Needed", isPresented: $showCameraPermissionAlert) {
            Button("Open Settings") { openAppSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cameraPermissionMessage)
        }
    }
    private func openScanWithCameraPermission(for context: ScanContext) {
        cameraPermissionMessage =
        context == .health
            ? "This app needs camera access to scan ingredients for the health tracker. It will not work without camera permission."
            : "This app needs camera access to scan expiry dates of products. It will not work without camera permission."

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showScan = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showScan = true
                    } else {
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert = true
        @unknown default:
            showCameraPermissionAlert = true
        }
    }
    private func openAppSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
    // Automatically archives expired items during app lifecycle events.
    private func autoArchiveExpiredItems() {
        for item in allItems {
            if !item.isArchived && !item.usedSuccessfully && item.daysRemaining < 0 {
                item.isArchived = true
                NotificationManager.shared.cancelNotifications(for: item)
            }
        }
        try? modelContext.save()
    }

    private var topBar: some View {
        HStack {
            Button {
                HapticManager.shared.light()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { showMenu.toggle() }
            } label: {
                VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.80))
                            .frame(width: 22, height: 2.5)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            Spacer()
            IntakeBrandMark()
        }
        .padding(.horizontal, 20)
        .padding(.top, safeAreaTop)
        .padding(.bottom, 12)
        .background(Color(red: 0.04, green: 0.10, blue: 0.06).ignoresSafeArea(edges: .top))
    }

    private func fabButton(icon: String, action: @escaping () -> Void) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    HapticManager.shared.medium()
                    action()
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.18, green: 0.75, blue: 0.35),
                                         Color(red: 0.08, green: 0.50, blue: 0.22)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 62, height: 62)
                            .shadow(color: .green.opacity(0.45), radius: 14, y: 6)
                        Image(systemName: icon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .padding(.trailing, 24)
                .padding(.bottom, 36)
            }
        }
    }

    private var safeAreaTop: CGFloat {
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44
        #else
        return 44
        #endif
    }
}
struct IntakeBrandMark: View {
    @State private var glowOn: Bool = false
    @State private var flowX: CGFloat = -160

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text("Intake")
                .font(.system(size: 23, weight: .black))
                .italic()
                .tracking(2.6)
                .foregroundColor(Color(red: 0.30, green: 0.90, blue: 0.45).opacity(glowOn ? 0.35 : 0.0))
                .blur(radius: 8)
                .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: glowOn)

            Text("Intake")
                .font(.system(size: 23, weight: .black))
                .italic()
                .tracking(2.6)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(red: 0.04, green: 0.10, blue: 0.06).opacity(0.95),
                    Color(red: 0.12, green: 0.32, blue: 0.18).opacity(0.75),
                    Color(red: 0.04, green: 0.10, blue: 0.06).opacity(0.95),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 124, height: 34)
            .offset(x: flowX)
            .mask(
                Text("Intake")
                    .font(.system(size: 23, weight: .black))
                    .italic()
                    .tracking(2.6)
            )
            Image(systemName: "leaf.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.35, green: 0.92, blue: 0.52))
                .offset(x: -6, y: 4)
        }
        .frame(width: 132, height: 40, alignment: .trailing)
        .onAppear {
            glowOn = true
            flowX = -160
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                flowX = 160
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ScannedItem.self, HealthEntry.self], inMemory: true)
}
